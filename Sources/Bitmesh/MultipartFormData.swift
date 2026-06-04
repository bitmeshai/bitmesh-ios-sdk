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
    static func flatten(_ fields: [String: Any], prefix: String = "") -> [String: String] {
        var flattened: [String: String] = [:]

        for (key, value) in fields {
            let fieldName = prefix.isEmpty ? key : "\(prefix)[\(key)]"
            if let nested = value as? [String: Any] {
                for (nestedKey, nestedValue) in flatten(nested, prefix: fieldName) {
                    flattened[nestedKey] = nestedValue
                }
            } else if let array = value as? [Any] {
                for (index, element) in array.enumerated() {
                    let indexedName = "\(fieldName)[\(index)]"
                    if let nestedDict = element as? [String: Any] {
                        for (nestedKey, nestedValue) in flatten(nestedDict, prefix: indexedName) {
                            flattened[nestedKey] = nestedValue
                        }
                    } else {
                        flattened[indexedName] = stringValue(element)
                    }
                }
            } else {
                flattened[fieldName] = stringValue(value)
            }
        }

        return flattened
    }

    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return "\(value)"
        }
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
