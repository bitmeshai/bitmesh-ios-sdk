import XCTest
@testable import Bitmesh

final class BitmeshClientTranscribeIntegrationTests: XCTestCase {
    func testTranscribeFileCallsAPI() async throws {
        let client = try BitmeshTestSupport.makeClient()
        let audioURL = try BitmeshTestSupport.fixtureURL("test_audio.mp3")

        let response = try await client.transcribeFile(audioFileURL: audioURL, fields: [
            "speech_models": [
                ["model": "gpt-4o-mini-transcribe"],
            ],
        ])

        XCTAssertFalse(response.isEmpty)
        XCTAssertFalse((response["id"] as? String ?? "").isEmpty)
    }
}
