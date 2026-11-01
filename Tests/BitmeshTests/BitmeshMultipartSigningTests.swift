import XCTest
@testable import Bitmesh

/// Multipart uploads are signed over the JSON of the non-file fields as the
/// server receives them: text values, trimmed, empty strings as null, keys sorted.
final class BitmeshMultipartSigningTests: XCTestCase {
    func testValuesAreSentAsText() {
        let wire = MultipartFieldFlattener.wireFields([
            "restore_face": true,
            "test": false,
            "resolution": 1024,
            "return_form": "crop",
            "skipped": NSNull(),
            "empty": [String](),
        ])

        XCTAssertEqual(wire.count, 4)
        XCTAssertEqual(wire["restore_face"] as? String, "1")
        XCTAssertEqual(wire["test"] as? String, "0")
        XCTAssertEqual(wire["resolution"] as? String, "1024")
        XCTAssertEqual(wire["return_form"] as? String, "crop")
    }

    func testFlattenOrderIsFixed() {
        let fields = MultipartFieldFlattener.flatten(MultipartFieldFlattener.wireFields([
            "zeta": "z",
            "speech_models": ["universal-3-pro", "universal-2"],
            "alpha": ["b": 2, "a": 1],
        ]))

        XCTAssertEqual(fields.map(\.name), [
            "alpha[a]", "alpha[b]", "speech_models[0]", "speech_models[1]", "zeta",
        ])
        XCTAssertEqual(fields.map(\.value), ["1", "2", "universal-3-pro", "universal-2", "z"])
    }

    func testSigningJSONMatchesWhatTheServerHashes() throws {
        let json = try JSONHelpers.multipartSigningJSON([
            "test": true,
            "resolution": 1024,
            "return_form": " crop ",
            "blank": "",
            "speech_models": ["universal-2"],
        ])

        XCTAssertEqual(
            json,
            #"{"blank":null,"resolution":"1024","return_form":"crop","speech_models":["universal-2"],"test":"1"}"#
        )
    }

    func testNoFieldsSignsAnEmptyJSONArray() throws {
        XCTAssertEqual(try JSONHelpers.multipartSigningJSON([:]), "[]")
        XCTAssertEqual(try JSONHelpers.multipartSigningJSON(["gone": NSNull()]), "[]")
    }
}
