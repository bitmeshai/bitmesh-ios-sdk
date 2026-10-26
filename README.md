# Bitmesh iOS SDK

Swift package for calling the [Bitmesh AI API](https://bitmesh.ai) from iOS and macOS apps.

## Requirements

- iOS 15+ / macOS 12+
- Swift 5.9+
- OAuth consumer key and secret from Bitmesh

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** → `https://github.com/bitmeshai/bitmesh-ios-sdk.git`

Or add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bitmeshai/bitmesh-ios-sdk.git", from: "1.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["Bitmesh"]),
]
```

## Quick start

```swift
import Bitmesh

let client = BitmeshClient(key: "your-consumer-key", secret: "your-consumer-secret")

// Chat (full payload / REST API)
let response = try await client.chat(payload: [
    "model": "openai/gpt-4o-mini",
    "messages": [
        ["role": "user", "content": "Hello from iOS"],
    ],
    "max_tokens": 64,
])

// Convenience helpers
let text = try await client.chatContent("Tell me a joke")
```

## App Check (mobile keys)

If your key ships inside your app, create it as a **Mobile app** key in the
Bitmesh dashboard. The API then refuses any request on that key that doesn't
carry a valid [Firebase App Check](https://firebase.google.com/docs/app-check)
token, so a secret extracted from your app binary is useless on its own.
Server keys don't need this; leave the parameter out.

Set up App Check for your app in the Firebase console first (App Attest, plus a
debug token for the simulator). The full walkthrough is in the
[API docs](https://bitmesh.ai/docs#app-check). Then pass a token provider:

```swift
import Bitmesh
import FirebaseAppCheck
import FirebaseCore

class AppAttestFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

// Before FirebaseApp.configure(). Debug provider in debug builds ONLY.
#if DEBUG
AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
AppCheck.setAppCheckProviderFactory(AppAttestFactory())
#endif
FirebaseApp.configure()

let client = BitmeshClient(
    key: consumerKey,
    secret: consumerSecret,
    appCheckTokenProvider: {
        try await AppCheck.appCheck().token(forcingRefresh: false).token
    }
)
```

- The provider is called before **every** signed request. Firebase caches the
  token and refreshes it before it expires, so this is cheap. Don't cache
  tokens yourself.
- The token goes in the `X-Firebase-AppCheck` header. It is not part of either
  signature.
- `getToolsResult(path:)` is unsigned and doesn't send it.
- This package doesn't depend on Firebase: any closure returning a token works.

Handling failures:

```swift
do {
    let response = try await client.chat(payload: payload)
} catch let error as BitmeshAppCheckTokenError {
    // No token on the device, so nothing was sent. error.underlying holds the
    // Firebase error. Usually App Check isn't set up for this app in Firebase.
} catch let error as BitmeshError where error.appCheckRejectionReason != nil {
    // 401: the API refused the token, e.g. "App Check token is for an
    // unregistered app". error.isTemporaryAppCheckFailure is true only when the
    // API couldn't verify tokens at all; retry later in that case.
}
```

## API surface

| Method | HTTP | Description |
|--------|------|-------------|
| `chat(payload:)` | `POST /chat` | Chat completions |
| `image(payload:)` | `POST /image` | Image generation |
| `video(payload:)` | `POST /video` | Video generation |
| `getVideo(id:query:)` | `GET /video/{id}` | Poll video job |
| `transcribeFile(audioFileURL:fields:)` | `POST /transcribe-recorded` | Upload audio |
| `getTranscribeRecorded(id:query:)` | `GET /transcribe-recorded/{id}` | Poll transcription |
| `toolsGeneralBackgroundRemoval(fields:imageFileURL:)` | `POST /tools/general/background-removal` | Background removal |
| `toolsPortraitTryOnClothes(fields:files:)` | `POST /tools/portrait/try-on-clothes` | Virtual try-on |
| `toolsQueryAsyncTaskResult(taskId:)` | `POST /tools/query-async-task-result` | Poll async tool task |
| `getToolsResult(path:)` | `GET /tools-result/{path}` | Download tool result (unsigned) |

Authentication matches the PHP SDK: OAuth 1.0 (HMAC-SHA1) plus `X-Payload-Signature` (SHA-256 of body + key + oauth signature).

## Tests

From the package root:

```bash
swift test
```

- **Validation & OAuth tests** always run (no credentials).
- **Integration tests** call `https://api.bitmesh.ai` and are skipped unless you set:

```bash
export BITMESH_TEST_CONSUMER_KEY="your-oauth-consumer-key"
export BITMESH_TEST_CONSUMER_SECRET="your-oauth-consumer-secret"
swift test
```

## Example app

Open `BitmeshExample/BitmeshExample.xcodeproj` in Xcode and add the local `Bitmesh` package to the app target.

## License

See [LICENSE](LICENSE) if present in this repository.
