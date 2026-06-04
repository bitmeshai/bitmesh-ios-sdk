import Foundation

/// JSON object returned by Bitmesh API endpoints.
public typealias BitmeshJSON = [String: Any]

enum JSONHelpers {
    /// Matches PHP `json_encode` for request bodies (key order preserved).
    static func encodeJSONObject(_ object: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw BitmeshError.encodingFailed
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.withoutEscapingSlashes]
        )
        guard let string = String(data: data, encoding: .utf8) else {
            throw BitmeshError.encodingFailed
        }
        return string
    }

    /// Matches PHP multipart payload signature (`ksort` on top-level fields only).
    static func encodeTopLevelSortedJSONObject(_ object: [String: Any]) throws -> String {
        var sorted: [String: Any] = [:]
        for key in object.keys.sorted() {
            sorted[key] = object[key]!
        }
        return try encodeJSONObject(sorted)
    }

    static func decodeJSONObject(from data: Data) throws -> BitmeshJSON {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? BitmeshJSON else {
            throw BitmeshError.invalidJSON
        }
        return object
    }
}
