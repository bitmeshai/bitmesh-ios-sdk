# Bitmesh iOS SDK

Swift package for calling the [Bitmesh AI API](https://bitmesh.ai) **v2** from
iOS and macOS apps: chat (streaming included), image, video, transcription
(real-time included), tools and the provider proxy.

v2 takes one bearer key (`bmk_...`), so there is nothing to sign. From 2.0.0 on
the SDK supports v2 only; use 1.2.0 for a v1 consumer key and secret. See
[Moving from 1.x](#moving-from-1x).

## Requirements

- iOS 15+ / macOS 12+
- Swift 5.9+
- A v2 key from the Bitmesh dashboard, starting `bmk_`

## Installation

In Xcode: **File → Add Package Dependencies** → `https://github.com/bitmeshai/bitmesh-ios-sdk.git`

Or add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bitmeshai/bitmesh-ios-sdk.git", from: "2.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["Bitmesh"]),
]
```

## Quick start

```swift
import Bitmesh

let client = BitmeshClient(apiKey: "bmk_...")

// Chat, full payload
let response = try await client.chat(payload: [
    "model": "bitmeshai/chat-now-nano",
    "messages": [
        ["role": "user", "content": "Hello from iOS"],
    ],
    "max_tokens": 300,
])

// Convenience helpers
let text = try await client.chatContent("Tell me a joke")
```

Never hardcode the key in your app. Load it at runtime, from Remote Config or
your own backend. A key that is empty or doesn't start with `bmk_` (a v1
consumer key) is refused with `BitmeshError.validation` before anything is sent.

## Streaming

```swift
var reply = ""
for try await chunk in client.streamChat(messages: [.user("Write a haiku")]) {
    reply += chunk.text                 // new text, "" on bookkeeping chunks
    if let usage = chunk.usage { print(usage.totalTokens ?? 0) } // last chunk
}

// Raw chunks, in OpenAI's format
for try await json in client.chatStream(payload: payload) { ... }
```

The request is billed once, when the stream ends. Stop iterating, or cancel the
task, to stop generating: you pay only for what was written. Errors before the
stream starts throw `BitmeshError.httpError`; a provider failure mid-stream
throws one with status `502`.

## App Check (mobile keys)

If your key ships inside your app, create it as a **mobile app** key in the
Bitmesh dashboard. The API then refuses any request on that key that doesn't
carry a valid [Firebase App Check](https://firebase.google.com/docs/app-check)
token, so a key extracted from your app binary is useless on its own.
Server keys don't need this; leave the parameter out.

Set up App Check for your app in the Firebase console first (App Attest). The
full walkthrough is in the [API docs](https://bitmesh.ai/docs#app-check). Then
pass a token provider:

```swift
import Bitmesh
import FirebaseAppCheck
import FirebaseCore

class AppAttestFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

// Before FirebaseApp.configure().
AppCheck.setAppCheckProviderFactory(AppAttestFactory())
FirebaseApp.configure()

let client = BitmeshClient(
    apiKey: bitmeshKey,
    appCheckTokenProvider: {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
```

- The provider is called before **every** request. Firebase caches the token
  and refreshes it before it expires, so this is cheap. Don't cache tokens
  yourself.
- The token goes in the `X-Firebase-AppCheck` header.
- `getToolsResult(path:)` is public and sends neither the key nor the token.
- This package doesn't depend on Firebase: any closure returning a token works.

### Debug tokens

On the simulator, or before Firebase is set up, a Bitmesh debug token
(`bmdbg_...`, created on the key in the dashboard) can stand in for App Check.
It goes in `X-Bitmesh-Debug-Token`, and the token provider isn't called. Keep it
out of release builds:

```swift
#if DEBUG
let debugToken: String? = ProcessInfo.processInfo.environment["BITMESH_DEBUG_TOKEN"]
#else
let debugToken: String? = nil
#endif

let client = BitmeshClient(apiKey: bitmeshKey, appCheckTokenProvider: tokenProvider, debugToken: debugToken)
```

### Handling failures

```swift
do {
    let response = try await client.chat(payload: payload)
} catch let error as BitmeshAppCheckTokenError {
    // No token on the device, so nothing was sent. error.underlying holds the
    // Firebase error. Usually App Check isn't set up for this app in Firebase.
} catch let error as BitmeshError where error.appCheckRejectionReason != nil {
    // 401: the API refused the token or debug token, e.g. "App Check token is
    // for an unregistered app". error.isTemporaryAppCheckFailure is true only
    // when the API couldn't verify tokens at all; retry later in that case.
} catch let error as BitmeshError {
    // error.statusCode (401, 402, 429, ...) and error.apiMessage, the API's reason
}
```

## Proxy

With a proxy key, send the provider's own request, minus its API key header:
Bitmesh adds your stored provider key. Bodies and replies pass through unchanged.

```swift
let proxy = BitmeshClient(apiKey: proxyKey)

let reply = try await proxy.proxy(provider: "openai", path: "v1/chat/completions", payload: [
    "model": "gpt-4o-mini",
    "messages": [["role": "user", "content": "Hello"]],
])

// Provider headers that select options are passed on
let message = try await proxy.proxy(
    provider: "anthropic",
    path: "v1/messages",
    payload: ["model": "claude-sonnet-4-5", "max_tokens": 256, "messages": messages],
    headers: ["anthropic-version": "2023-06-01"]
)

// Streaming: the provider's server-sent events, as they arrive
for try await event in proxy.proxyStream(provider: "openai", path: "v1/chat/completions", payload: body) {
    if event.isDone { break }
    let chunk = try event.json()
}
```

## Real-time transcription

Stream audio as it is recorded and get the transcript turn by turn, over a
WebSocket to `/v2/transcribe-realtime`.

```swift
let session = try await client.transcribeRealtime(
    sampleRate: 16000,
    speechModel: BitmeshRealtimeSpeechModel.universal36Pro // the default
)

Task {
    for try await event in session.events {
        // The same turn arrives again as it grows; keep the final one.
        if case .turn(let turn) = event, turn.endOfTurn { print(turn.transcript) }
    }
}

// From AVAudioEngine: raw 16-bit little-endian mono PCM, about 50 ms
// (1,600 bytes at 16 kHz) at a time
try await session.sendAudio(pcmChunk)

let end = await session.terminate()
print("\(end?.sessionDurationSeconds ?? 0) s billed")
```

- A refused connection throws `BitmeshError.httpError` before any audio is
  sent: `402` when the balance covers less than a minute, `429` when the key
  already has 5 sessions open, `422` for unknown settings. A WebSocket handshake
  has no readable body, so `apiMessage` is `nil` here.
- `session.events` ends when the session closes, throwing
  `BitmeshRealtimeClosedError` for a close other than a normal one: `3008` at
  the time limit (an hour, or what the balance covers), `1001` when the server
  restarts, `1011` when the transcription service fails.
- The session is billed per second it is open, silence included: call
  `terminate()` as soon as you are done.
- Models: `universal-3-6-pro` (32 languages), `universal-streaming-english`,
  `universal-streaming-multilingual`. `formatTurns: true` punctuates the
  streaming models; `languageDetection: true` adds `languageCode` to each turn.
  `forceEndpoint()` ends the current turn now.
- Apple platforms only: swift-corelibs-foundation on Linux can't open
  WebSockets.

## API surface

All paths are under `/v2`.

| Method | HTTP | Description |
|--------|------|-------------|
| `balance()` | `GET /balance` | Credit balance |
| `verify()` | `GET /test` | Throws unless the key (and App Check token) is accepted |
| `chat(payload:)` | `POST /chat` | Chat completion |
| `chatStream(payload:)` | `POST /chat`, `"stream": true` | Streamed chat, raw chunks |
| `streamChat(messages:model:extraPayload:)` | `POST /chat`, `"stream": true` | Streamed chat, typed chunks |
| `image(payload:)` | `POST /image` | Image generation |
| `video(payload:)` | `POST /video` | Video generation |
| `getVideo(id:query:)` | `GET /video/{id}` | Poll video job |
| `transcribeFile(audioFileURL:fields:)` | `POST /transcribe-recorded` | Upload audio |
| `getTranscribeRecorded(id:query:)` | `GET /transcribe-recorded/{id}` | Poll transcription |
| `transcribeRealtime(sampleRate:speechModel:encoding:formatTurns:languageDetection:query:)` | WebSocket `/transcribe-realtime` | Real-time transcription session |
| `toolsGeneralBackgroundRemoval(fields:imageFileURL:)` | `POST /tools/general/background-removal` | Background removal |
| `toolsPortraitTryOnClothes(fields:files:)` | `POST /tools/portrait/try-on-clothes` | Virtual try-on |
| `toolsQueryAsyncTaskResult(taskId:)` | `POST /tools/query-async-task-result` | Poll async tool task |
| `imageAnimate(payload:)` | `POST /tools/video/image-animate` | Image-to-video (JSON, image base64-encoded) |
| `getImageAnimate(taskId:query:)` | `GET /tools/video/image-animate/{task_id}` | Poll image-to-video job |
| `proxy(provider:path:method:payload:headers:)` | `/proxy/{provider}/{path}` | Proxy request (proxy keys) |
| `proxyStream(provider:path:payload:headers:)` | `POST /proxy/{provider}/{path}` | Streamed proxy request |
| `getToolsResult(path:)` | `GET /tools-result/{path}` (no `/v2`) | Download a tool result; public |

Replies use OpenAI's snake_case field names for every model (`usage.prompt_tokens`, `choices[].finish_reason`).

Multipart fields travel as text: the client sends `Bool` as `"1"`/`"0"` and numbers as strings, and leaves out `NSNull` values.

## Moving from 1.x

```swift
// 1.x, API v1
let client = BitmeshClient(key: consumerKey, secret: consumerSecret)

// 2.0, API v2
let client = BitmeshClient(apiKey: "bmk_...")
```

- Create a v2 key in the dashboard. A v1 key is refused on v2 and the other way round.
- Method names and payloads are unchanged.
- OAuth signing and `X-Payload-Signature` are gone. Replies are always snake_case:
  read `usage.prompt_tokens`, not `usage.promptTokens`.
- New: `balance()`, `verify()`, `chatStream`, `streamChat`, `proxy`, `proxyStream`,
  `debugToken`, `ChatResponse.usage`, `BitmeshError.statusCode` and `apiMessage`.
- `defaultChatModel` is now `bitmeshai/chat-now-nano`.

## Tests

```bash
swift test
```

- Unit tests always run, against a mocked `URLSession`.
- Integration tests call the live API and are skipped unless you set a v2 hosted key:

```bash
export BITMESH_TEST_API_KEY="bmk_..."
export BITMESH_TEST_BASE_URL="https://api.bitmesh.ai"   # optional
export BITMESH_TEST_MODEL="bitmeshai/chat-now-nano"     # optional, for streaming
export BITMESH_TEST_AUDIO_PCM="clip.pcm"                # optional, 16 kHz 16-bit mono PCM for real-time
swift test
```

The package also builds on Linux (swift-corelibs-foundation), where a streamed
reply is read whole and then parsed rather than piece by piece, and real-time
transcription is not available.

## Example app

Open `BitmeshExample/BitmeshExample.xcodeproj` in Xcode, add the local `Bitmesh`
package to the app target, and set `BITMESH_KEY` in the target's Info.plist.

## License

See [LICENSE](LICENSE) if present in this repository.
