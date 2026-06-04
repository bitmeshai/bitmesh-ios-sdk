import XCTest
@testable import Bitmesh

final class BitmeshClientValidationTests: XCTestCase {
    private let client = BitmeshClient(key: "key", secret: "secret")

    func testGetTranscribeRecordedRejectsEmptyId() async {
        do {
            _ = try await client.getTranscribeRecorded(id: "  ")
            XCTFail("Expected validation error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.errorDescription, "Transcription job id is required.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetVideoRejectsEmptyId() async {
        do {
            _ = try await client.getVideo(id: "\n")
            XCTFail("Expected validation error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.errorDescription, "Video job id is required.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testToolsQueryAsyncTaskResultRejectsEmptyTaskId() async {
        do {
            _ = try await client.toolsQueryAsyncTaskResult(taskId: "\t")
            XCTFail("Expected validation error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.errorDescription, "Task id is required.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGetToolsResultRejectsEmptyPath() async {
        do {
            _ = try await client.getToolsResult(path: "")
            XCTFail("Expected validation error")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.errorDescription, "Tools result path is required.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testToolsPortraitTryOnRejectsMissingFile() async {
        let missing = URL(fileURLWithPath: "/no/such/file.png")
        do {
            _ = try await client.toolsPortraitTryOnClothes(fields: [:], files: ["person_image": missing])
            XCTFail("Expected file error")
        } catch let error as BitmeshError {
            if case .fileNotFound(let field, let path) = error {
                XCTAssertEqual(field, "person_image")
                XCTAssertEqual(path, missing.path)
            } else {
                XCTFail("Expected fileNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
