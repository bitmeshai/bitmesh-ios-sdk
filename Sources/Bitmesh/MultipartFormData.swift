import Foundation

struct MultipartFormData {
    let boundary: String
    private var body = Data()

    init(boundary: String = "BitmeshBoundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    func finalize() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}

enum MultipartFieldFlattener {
    /// The fields as they go over the wire. Multipart carries text, so booleans
    /// become `"1"` or `"0"` and numbers their string form; `nil`, `NSNull` and
    /// empty collections are left out. Nested maps and arrays are kept.
    static func wireFields(_ fields: [String: Any]) -> [String: Any] {
        var wire: [String: Any] = [:]
        for (key, value) in fields {
            if let converted = wireValue(value) {
                wire[key] = converted
            }
        }
        return wire
    }

    /// Flattens wire fields into `name[child]` / `name[0]` form fields, in a
    /// fixed order: keys sorted at every level, array items in index order.
    static func flatten(_ fields: [String: Any], prefix: String = "") -> [(name: String, value: String)] {
        var flattened: [(name: String, value: String)] = []
        for key in fields.keys.sorted() {
            let fieldName = prefix.isEmpty ? key : "\(prefix)[\(key)]"
            flattened += flattenValue(fields[key]!, name: fieldName)
        }
        return flattened
    }

    private static func flattenValue(_ value: Any, name: String) -> [(name: String, value: String)] {
        switch value {
        case let nested as [String: Any]:
            return flatten(nested, prefix: name)
        case let array as [Any]:
            return array.enumerated().flatMap { flattenValue($0.element, name: "\(name)[\($0.offset)]") }
        case let string as String:
            return [(name, string)]
        default:
            return [(name, "\(value)")]
        }
    }

    private static func wireValue(_ value: Any) -> Any? {
        if isNil(value) || value is NSNull { return nil }
        if let string = value as? String { return string }
        // A Swift Bool, or an NSNumber holding one (decoded JSON).
        if type(of: value) == Bool.self { return (value as! Bool) ? "1" : "0" }
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue ? "1" : "0" }
            return number.stringValue
        }
        if let map = value as? [String: Any] {
            let wire = wireFields(map)
            return wire.isEmpty ? nil : wire
        }
        if let array = value as? [Any] {
            let wire = array.compactMap { wireValue($0) }
            return wire.isEmpty ? nil : wire
        }
        return "\(value)"
    }

    private static func isNil(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        return String(cString: number.objCType) == "c"
        #endif
    }
}

enum FileValidator {
    static func validateReadableFile(at url: URL, field: String) throws -> Data {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path),
              FileManager.default.isReadableFile(atPath: path)
        else {
            throw BitmeshError.fileNotFound(field: field, path: path)
        }
        return try Data(contentsOf: url)
    }

    static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
}
