import XCTest
@testable import Bitmesh

final class BitmeshClientImageIntegrationTests: XCTestCase {
    func testImageCallsAPI() async throws {
        let client = try BitmeshTestSupport.makeClient()

        let response = try await client.image(payload: [
            "prompt": "Make this cat smile",
            "model": "wan-ai/wan2.6-image",
            "reference_images": [
                "https://placecats.com/800/600",
            ],
        ])

        XCTAssertFalse(response.isEmpty)
        XCTAssertFalse((response["id"] as? String ?? "").isEmpty)
    }
}
