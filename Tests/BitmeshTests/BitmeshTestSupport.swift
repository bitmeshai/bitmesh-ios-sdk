import Foundation
import XCTest
@testable import Bitmesh

enum BitmeshTestSupport {
    static var consumerKey: String {
        ProcessInfo.processInfo.environment["BITMESH_TEST_CONSUMER_KEY"] ?? ""
    }

    static var consumerSecret: String {
        ProcessInfo.processInfo.environment["BITMESH_TEST_CONSUMER_SECRET"] ?? ""
    }

    static func makeClient(timeout: TimeInterval = 120) throws -> BitmeshClient {
        guard !consumerKey.isEmpty, !consumerSecret.isEmpty else {
            throw XCTSkip("Set BITMESH_TEST_CONSUMER_KEY and BITMESH_TEST_CONSUMER_SECRET to run integration tests.")
        }
        return BitmeshClient(key: consumerKey, secret: consumerSecret, timeoutSeconds: timeout)
    }

    static func fixtureURL(_ filename: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures") else {
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
