import XCTest
@testable import Bitmesh

final class BitmeshClientChatIntegrationTests: XCTestCase {
    func testChatCallsAPI() async throws {
        let client = try BitmeshTestSupport.makeClient()

        var payload: BitmeshJSON = [
            "model": "openai/gpt-4o-mini",
            "messages": [
                [
                    "role": "user",
                    "content": "Reply with exactly: sdk-ok",
                ],
            ],
            "max_tokens": 16,
            "temperature": 0,
        ]

        let response: BitmeshJSON
        do {
            response = try await client.chat(payload: payload)
        } catch let error as BitmeshError {
            guard case .httpError(_, let body) = error,
                  let body,
                  body.contains("This API key uses a fixed model")
            else {
                throw error
            }
            payload.removeValue(forKey: "model")
            response = try await client.chat(payload: payload)
        }

        XCTAssertFalse(response.isEmpty)
        XCTAssertNotNil(response["id"] as? String)
        XCTAssertFalse((response["id"] as? String ?? "").isEmpty)
    }

    func testChatWithImageURLCallsAPI() async throws {
        let client = try BitmeshTestSupport.makeClient()

        let payload: BitmeshJSON = [
            "model": "qwen/qwen3.5-9b",
            "messages": [
                ["role": "system", "content": "You are a riddle solver."],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "Describe the image in one short phrase."],
                        [
                            "type": "image_url",
                            "image_url": ["url": "https://placecats.com/600/400"],
                        ],
                    ],
                ],
            ],
            "max_tokens": 64,
        ]

        let response = try await client.chat(payload: payload)
        XCTAssertFalse(response.isEmpty)
        XCTAssertFalse((response["id"] as? String ?? "").isEmpty)
    }

    func testStreamChatCallsAPI() async throws {
        let client = try BitmeshTestSupport.makeClient()
        let model = ProcessInfo.processInfo.environment["BITMESH_TEST_MODEL"] ?? BitmeshClient.defaultChatModel

        var text = ""
        var usage: ChatUsage?
        for try await chunk in client.streamChat(messages: [.user("Count from 1 to 5.")], model: model, extraPayload: ["max_tokens": 300]) {
            text += chunk.text
            usage = chunk.usage ?? usage
        }

        XCTAssertFalse(text.isEmpty)
        XCTAssertGreaterThan(usage?.totalTokens ?? 0, 0)
    }

    func testBalanceAndVerify() async throws {
        let client = try BitmeshTestSupport.makeClient()

        try await client.verify()
        let balance = try await client.balance()
        XCTAssertGreaterThanOrEqual(balance, 0)
    }
}
