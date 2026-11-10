import Foundation
import XCTest
@testable import Bitmesh

enum BitmeshTestSupport {
    static var apiKey: String {
        ProcessInfo.processInfo.environment["BITMESH_TEST_API_KEY"] ?? ""
    }

    static var baseURL: String {
        ProcessInfo.processInfo.environment["BITMESH_TEST_BASE_URL"] ?? BitmeshClient.defaultBaseURL
    }

    /// A client for the live API, with a v2 hosted key.
    static func makeClient(timeout: TimeInterval = 120) throws -> BitmeshClient {
        guard !apiKey.isEmpty else {
            throw XCTSkip("Set BITMESH_TEST_API_KEY (a v2 hosted key, bmk_...) to run integration tests.")
        }
        return BitmeshClient(apiKey: apiKey, timeoutSeconds: timeout, baseURL: baseURL)
    }

    static func fixtureURL(_ filename: String) throws -> URL {
        // `.process` may flatten the Fixtures folder, depending on the platform.
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: filename, withExtension: nil)
        else {
            XCTFail("Missing fixture: \(filename)")
            throw NSError(domain: "BitmeshTests", code: 1)
        }
        return url
    }

    static func toolsResultPath(fromImageURL imageURL: String) throws -> String {
        guard let url = URL(string: imageURL) else {
            throw BitmeshError.validation("Invalid tools-result image URL: \(imageURL)")
        }
        let path = url.path
        let marker = "/tools-result/"
        guard let range = path.range(of: marker) else {
            throw BitmeshError.validation("URL does not contain /tools-result/ path: \(imageURL)")
        }
        return String(path[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
