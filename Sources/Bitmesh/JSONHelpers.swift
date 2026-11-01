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

    /// The JSON the server hashes for a multipart upload's non-file fields.
    ///
    /// The server reads the fields as text (see `MultipartFieldFlattener.wireFields`),
    /// trims every string, turns empty strings into `null`, sorts the top-level
    /// keys and JSON-encodes the result without escaping slashes. Nested keys keep
    /// the order they were sent in, which is sorted too. With no fields it hashes `[]`.
    static func multipartSigningJSON(_ fields: [String: Any]) throws -> String {
        let wire = MultipartFieldFlattener.wireFields(fields)
        if wire.isEmpty { return "[]" }
        guard let received = asReceived(wire) as? [String: Any],
              JSONSerialization.isValidJSONObject(received)
        else {
            throw BitmeshError.encodingFailed
        }
        let data = try JSONSerialization.data(
            withJSONObject: received,
            options: [.withoutEscapingSlashes, .sortedKeys]
        )
        guard let string = String(data: data, encoding: .utf8) else {
            throw BitmeshError.encodingFailed
        }
        return string
    }

    /// Mirrors the server's TrimStrings and ConvertEmptyStringsToNull middleware.
    private static func asReceived(_ value: Any) -> Any {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? NSNull() : trimmed
        case let map as [String: Any]:
            return map.mapValues { asReceived($0) }
        case let list as [Any]:
            return list.map { asReceived($0) }
        default:
            return value
        }
    }

    static func decodeJSONObject(from data: Data) throws -> BitmeshJSON {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? BitmeshJSON else {
            throw BitmeshError.invalidJSON
        }
        return object
    }
}
