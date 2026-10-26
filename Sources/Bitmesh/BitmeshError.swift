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

/// Thrown when the client's `appCheckTokenProvider` could not supply a token,
/// so the request was not sent.
///
/// On a device this usually means App Check is not set up for the app in the
/// Firebase console (App Attest registration, or a debug token for simulators).
public struct BitmeshAppCheckTokenError: Error, LocalizedError {
    /// The error thrown by the provider, or `nil` when it returned no token.
    public let underlying: Error?

    public init(underlying: Error?) {
        self.underlying = underlying
    }

    public var errorDescription: String? {
        if let underlying {
            return "Could not get a Firebase App Check token: \(underlying.localizedDescription)"
        }
        return "The App Check token provider returned no token. Check that App Check is set up before the first request."
    }
}

extension BitmeshError {
    /// The API's reason when it refused the request's App Check token, such as
    /// `App Check token is for an unregistered app`. `nil` for any other error.
    ///
    /// The API answers these with `401` and `{"error": "<reason>"}` on keys
    /// designated as mobile.
    public var appCheckRejectionReason: String? {
        guard case .httpError(401, let body) = self,
              let data = body?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reason = object["error"] as? String,
              reason.contains("App Check") || reason.contains(BitmeshClient.appCheckHeader)
        else {
            return nil
        }
        return reason
    }

    /// True when the API could not verify App Check tokens at all, rather than
    /// refusing this one. Worth retrying after a pause; nothing on the device
    /// is wrong.
    public var isTemporaryAppCheckFailure: Bool {
        appCheckRejectionReason?.contains("temporarily unavailable") ?? false
    }
}
