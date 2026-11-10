import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import Bitmesh

final class BitmeshV2Tests: XCTestCase {
    private let key = "bmk_test0123456789"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeClient(apiKey: String? = nil, baseURL: String = BitmeshClient.defaultBaseURL) -> BitmeshClient {
        BitmeshClient(apiKey: apiKey ?? key, baseURL: baseURL, session: .mocked)
    }

    private func sentJSON(_ index: Int = 0) throws -> [String: Any] {
        let body = MockURLProtocol.body(of: MockURLProtocol.requests[index])
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - Requests

    func testRequestsCarryTheBearerKeyOnV2Paths() async throws {
        let client = makeClient()

        _ = try await client.chat(payload: ["model": "m", "messages": []])
        _ = try await client.getVideo(id: "job 1", query: ["test": "1"])

        let chat = MockURLProtocol.requests[0]
        XCTAssertEqual(chat.httpMethod, "POST")
        XCTAssertEqual(chat.url?.absoluteString, "https://api.bitmesh.ai/v2/chat")
        XCTAssertEqual(chat.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(chat.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(chat.value(forHTTPHeaderField: "X-Payload-Signature"))
        XCTAssertEqual(try sentJSON()["model"] as? String, "m")

        let video = MockURLProtocol.requests[1]
        XCTAssertEqual(video.httpMethod, "GET")
        XCTAssertEqual(video.url?.absoluteString, "https://api.bitmesh.ai/v2/video/job%201?test=1")
        XCTAssertEqual(video.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
    }

    func testCustomBaseURL() async throws {
        let client = makeClient(baseURL: "https://staging.example.com/")

        _ = try await client.image(payload: ["prompt": "p"])

        XCTAssertEqual(MockURLProtocol.requests.first?.url?.absoluteString, "https://staging.example.com/v2/image")
    }

    func testMultipartUploadsGoToV2() async throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("bitmesh-v2-test.m4a")
        try Data([1, 2, 3]).write(to: audio)
        let client = makeClient()

        _ = try await client.transcribeFile(audioFileURL: audio, fields: ["speech_models": ["universal-2"], "punctuate": true])

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/transcribe-recorded")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = String(decoding: MockURLProtocol.body(of: request), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"speech_models[0]\"\r\n\r\nuniversal-2\r\n"))
        XCTAssertTrue(body.contains("name=\"punctuate\"\r\n\r\n1\r\n"))
        XCTAssertTrue(body.contains("name=\"audio\"; filename=\"bitmesh-v2-test.m4a\""))
    }

    func testBalanceAndVerify() async throws {
        MockURLProtocol.reset(body: "{\"balance\":12.5}")
        let client = makeClient()

        let balance = try await client.balance()
        try await client.verify()

        XCTAssertEqual(balance, 12.5)
        XCTAssertEqual(MockURLProtocol.requests.map { $0.url?.path }, ["/v2/balance", "/v2/test"])
    }

    func testAV1KeyIsRefusedBeforeSending() async {
        for badKey in ["", "  ", "ck_live_abc"] {
            do {
                _ = try await makeClient(apiKey: badKey).balance()
                XCTFail("Expected a validation error for \"\(badKey)\"")
            } catch let error as BitmeshError {
                guard case .validation = error else { return XCTFail("Unexpected error: \(error)") }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testErrorsExposeStatusAndMessage() async {
        MockURLProtocol.reset(status: 429, body: "{\"error\":\"Too many requests\",\"message\":\"This API key is limited to 600 requests per minute.\"}")

        do {
            _ = try await makeClient().chat(payload: [:])
            XCTFail("Expected an error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.apiMessage, "This API key is limited to 600 requests per minute.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Server-sent events

    func testParserBuildsEvents() {
        var parser = ServerSentEventParser()
        var events: [ServerSentEvent] = []
        let lines = [
            ": keep-alive",
            "event: message_start\r",
            "data: {\"x\":1}",
            "",
            "data: line one",
            "data:line two",
            "",
            "data: [DONE]",
        ]
        for line in lines {
            if let event = parser.feed(line) { events.append(event) }
        }
        if let event = parser.finish() { events.append(event) }

        XCTAssertEqual(events, [
            ServerSentEvent(event: "message_start", data: "{\"x\":1}"),
            ServerSentEvent(data: "line one\nline two"),
            ServerSentEvent(data: "[DONE]"),
        ])
        XCTAssertTrue(events[2].isDone)
    }

    // MARK: - Streaming chat

    private let streamedReply = """
    data: {"choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

    data: {"choices":[{"index":0,"delta":{"content":"There"}}]}

    data: {"choices":[{"index":0,"delta":{"content":" are plenty."},"finish_reason":"stop"}]}

    data: {"choices":[],"usage":{"prompt_tokens":51,"completion_tokens":4,"total_tokens":55}}

    data: [DONE]


    """

    func testChatStreamYieldsChunksThenUsage() async throws {
        MockURLProtocol.reset(body: streamedReply)
        let client = makeClient()

        var chunks: [ChatStreamChunk] = []
        for try await chunk in client.streamChat(messages: [.user("Hello")], model: "m") {
            chunks.append(chunk)
        }

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/chat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(try sentJSON()["stream"] as? Bool, true)

        XCTAssertEqual(chunks.map(\.text).joined(), "There are plenty.")
        XCTAssertEqual(chunks[2].choices.first?.finishReason, "stop")
        XCTAssertEqual(chunks.last?.usage?.totalTokens, 55)
    }

    func testChatStreamThrowsAnErrorBeforeTheStream() async {
        MockURLProtocol.reset(status: 402, body: "{\"error\":\"Insufficient balance\"}")

        do {
            for try await _ in makeClient().chatStream(payload: ["model": "m", "messages": []]) {}
            XCTFail("Expected an error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.statusCode, 402)
            XCTAssertEqual(error.apiMessage, "Insufficient balance")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testChatStreamThrowsAnErrorEventMidStream() async {
        MockURLProtocol.reset(body: """
        data: {"choices":[{"delta":{"content":"Hal"}}]}

        data: {"error":{"message":"upstream overloaded"}}


        """)

        var texts: [String] = []
        do {
            for try await chunk in makeClient().chatStream(payload: [:]) {
                texts.append(((chunk["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?["content"] as? String ?? "")
            }
            XCTFail("Expected an error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.apiMessage, "upstream overloaded")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(texts, ["Hal"])
    }

    // MARK: - Proxy

    func testProxyForwardsWithTheKeyAndProviderHeaders() async throws {
        MockURLProtocol.reset(body: "{\"content\":[{\"text\":\"Hi\"}]}")
        let client = makeClient()

        let reply = try await client.proxy(
            provider: "anthropic",
            path: "/v1/messages",
            payload: ["model": "claude", "max_tokens": 10],
            headers: ["anthropic-version": "2023-06-01", "Authorization": "Bearer sk-provider"]
        )

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.bitmesh.ai/v2/proxy/anthropic/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(try sentJSON()["max_tokens"] as? Int, 10)
        XCTAssertNotNil(reply["content"])
    }

    func testProxyStreamYieldsProviderEvents() async throws {
        MockURLProtocol.reset(body: """
        event: content_block_delta
        data: {"delta":{"text":"Hi"}}

        event: message_stop
        data: {"type":"message_stop"}

        """)
        let client = makeClient()

        var events: [ServerSentEvent] = []
        for try await event in client.proxyStream(provider: "anthropic", path: "v1/messages", payload: ["model": "claude"]) {
            events.append(event)
        }

        XCTAssertEqual(try sentJSON()["stream"] as? Bool, true)
        XCTAssertEqual(events.map(\.event), ["content_block_delta", "message_stop"])
        XCTAssertEqual(try events[0].json()["delta"] as? [String: String], ["text": "Hi"])
    }

    func testProxyRefusesAnInvalidProviderName() async {
        do {
            _ = try await makeClient().proxy(provider: "Open AI", path: "v1/models", method: "GET")
            XCTFail("Expected a validation error")
        } catch let error as BitmeshError {
            guard case .validation = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }
}
