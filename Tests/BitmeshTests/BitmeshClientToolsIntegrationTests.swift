import XCTest
@testable import Bitmesh

/// Tools in test mode: the full round trip, without running a tool or
/// spending credits.
final class BitmeshClientToolsIntegrationTests: XCTestCase {
    func testBackgroundRemovalInTestMode() async throws {
        let client = try BitmeshTestSupport.makeClient()

        // A Swift Bool is sent as "1".
        let response = try await client.toolsGeneralBackgroundRemoval(
            fields: ["test": true, "return_form": "crop"],
            imageFileURL: try BitmeshTestSupport.fixtureURL("stool.png")
        )

        XCTAssertEqual(response["status"] as? String, "success")
        let data = response["data"] as? [String: Any]
        XCTAssertFalse((data?["image_url"] as? String ?? "").isEmpty)
    }

    func testTryOnClothesInTestMode() async throws {
        let client = try BitmeshTestSupport.makeClient()

        let response = try await client.toolsPortraitTryOnClothes(
            fields: ["test": true, "restore_face": true, "resolution": 1024],
            files: [
                "person_image": try BitmeshTestSupport.fixtureURL("person.png"),
                "top_garment": try BitmeshTestSupport.fixtureURL("top_garment.png"),
            ]
        )

        XCTAssertEqual(response["status"] as? String, "success")
        XCTAssertFalse((response["task_id"] as? String ?? "").isEmpty)
    }

    func testImageAnimateInTestMode() async throws {
        let client = try BitmeshTestSupport.makeClient()
        let image = try Data(contentsOf: try BitmeshTestSupport.fixtureURL("person.png"))

        let created = try await client.imageAnimate(payload: [
            "model": "animate-2.4-faster",
            "image": ["bytes_base64_encoded": image.base64EncodedString()],
            "seconds": 5,
            "test": true,
        ])
        let taskId = (created["data"] as? [String: Any])?["task_id"] as? String ?? ""
        XCTAssertFalse(taskId.isEmpty)

        let status = try await client.getImageAnimate(taskId: taskId, query: ["test": "1"])
        let data = status["data"] as? [String: Any]
        XCTAssertEqual(data?["status"] as? String, "SUCCESS")
        let videos = data?["output_videos"] as? [[String: Any]]
        XCTAssertFalse((videos?.first?["url"] as? String ?? "").isEmpty)
    }
}
