import Foundation

/// Errors thrown by `BitmeshClient`.
public enum BitmeshError: Error, LocalizedError, Sendable {
    case validation(String)
    case encodingFailed
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case networkError(Error)
    case invalidJSON
    case fileNotFound(field: String, path: String)

    public var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .encodingFailed:
            return "Failed to encode request body"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .httpError(let code, let body):
            return "Bitmesh API request failed with status \(code): \(body ?? "")"
        case .networkError(let error):
            return "Bitmesh request failed: \(error.localizedDescription)"
        case .invalidJSON:
            return "Bitmesh API returned a non-JSON or invalid JSON response"
        case .fileNotFound(let field, let path):
            return "File does not exist or is not readable for field \"\(field)\": \(path)"
        }
    }
}
