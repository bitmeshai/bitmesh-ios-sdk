import XCTest
@testable import Bitmesh

/// Multipart fields travel as text: booleans as "1"/"0", numbers as their
/// string form, nils and empty collections left out.
final class BitmeshMultipartFieldTests: XCTestCase {
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
}
