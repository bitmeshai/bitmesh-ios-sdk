import CryptoKit
import Foundation

enum OAuthHelper {
    static func generateOAuthParams(
        method: String,
        url: String,
        consumerKey: String,
        consumerSecret: String,
        timestamp: String? = nil,
        nonce: String? = nil
    ) -> [String: String] {
        var params: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": timestamp ?? String(Int(Date().timeIntervalSince1970)),
            "oauth_nonce": nonce ?? randomNonceHex(length: 16),
            "oauth_version": "1.0",
        ]

        let signature = generateSignature(
            method: method,
            url: url,
            params: params,
            consumerSecret: consumerSecret
        )
        params["oauth_signature"] = signature
        return params
    }

    static func generateSignature(
        method: String,
        url: String,
        params: [String: String],
        consumerSecret: String
    ) -> String {
        guard let components = URLComponents(string: url) else { return "" }

        let scheme = components.scheme ?? "http"
        let host = components.host ?? "localhost"
        let port = components.port
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var normalizedUrl = "\(scheme)://\(host)"
        if (scheme == "http" && port != nil && port != 80)
            || (scheme == "https" && port != nil && port != 443)
        {
            normalizedUrl += ":\(port!)"
        }
        normalizedUrl += "/\(path)"

        var queryParams: [String: String] = [:]
        if let items = components.queryItems {
            for item in items {
                queryParams[item.name] = item.value ?? ""
            }
        }

        var allParams = params
        for (key, value) in queryParams { allParams[key] = value }
        allParams.removeValue(forKey: "oauth_signature")

        let sortedKeys = allParams.keys.sorted()
        let normalizedPairs = sortedKeys.compactMap { key -> String? in
            guard let value = allParams[key] else { return nil }
            return "\(rfc3986Encode(key))=\(rfc3986Encode(value))"
        }
        let paramString = normalizedPairs.joined(separator: "&")

        let baseString = "\(method.uppercased())&\(rfc3986Encode(normalizedUrl))&\(rfc3986Encode(paramString))"
        let signingKey = "\(rfc3986Encode(consumerSecret))&"

        let signatureData = hmacSHA1(
            data: Data(baseString.utf8),
            key: Data(signingKey.utf8)
        )
        return signatureData.base64EncodedString()
    }

    static func buildAuthorizationHeader(oauthParams: [String: String]) -> String {
        var parts: [String] = []
        for (key, value) in oauthParams where key.hasPrefix("oauth_") {
            parts.append("\(rfc3986Encode(key))=\"\(rfc3986Encode(value))\"")
        }
        return "OAuth " + parts.joined(separator: ", ")
    }

    static func payloadSignature(body: String, consumerKey: String, oauthSignature: String) -> String {
        sha256Hex(body + consumerKey + oauthSignature)
    }

    static func multipartPayloadSignature(fields: [String: Any], consumerKey: String, oauthSignature: String) throws -> String {
        let json = try JSONHelpers.encodeTopLevelSortedJSONObject(fields)
        return sha256Hex(json + consumerKey + oauthSignature)
    }

    static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func rfc3986Encode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private static func hmacSHA1(data: Data, key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    private static func randomNonceHex(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length / 2)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
