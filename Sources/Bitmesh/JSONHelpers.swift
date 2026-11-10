import Foundation

/// JSON object returned by Bitmesh API endpoints.
public typealias BitmeshJSON = [String: Any]

enum JSONHelpers {
    /// Encodes a request body without escaping slashes.
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

    static func decodeJSONObject(from data: Data) throws -> BitmeshJSON {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? BitmeshJSON else {
            throw BitmeshError.invalidJSON
        }
        return object
    }
}
