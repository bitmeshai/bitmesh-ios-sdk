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
            "model": "google/gemma-3n-e4b-it",
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
}
