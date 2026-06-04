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
    .package(url: "https://github.com/bitmeshai/bitmesh-ios-sdk.git", from: "1.0.0"),
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
