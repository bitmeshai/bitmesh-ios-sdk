//
//  OAuthHelper.swift
//  AIPoemCreator
//
//  Created by Guest Dev on 1/12/25.
//


import Foundation
import CommonCrypto

enum OAuthHelper {
    static func generateOAuthParams(method: String,
                                    url: String,
                                    consumerKey: String,
                                    consumerSecret: String) -> [String: String] {
        var params: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": String(Int(Date().timeIntervalSince1970)),
            "oauth_nonce": randomNonceHex(length: 16),  // 8 bytes hex
            "oauth_version": "1.0"
        ]
        
        let signature = generateSignature(method: method,
                                          url: url,
                                          params: params,
                                          consumerSecret: consumerSecret)
        params["oauth_signature"] = signature
        return params
    }
    
    static func generateSignature(method: String,
                                  url: String,
                                  params: [String: String],
                                  consumerSecret: String) -> String {
        guard var components = URLComponents(string: url) else { return "" }
        
        let scheme = components.scheme ?? "http"
        let host   = components.host ?? "localhost"
        let port   = components.port
        let path   = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        var normalizedUrl = "\(scheme)://\(host)"
        if (scheme == "http" && port != nil && port != 80) ||
           (scheme == "https" && port != nil && port != 443) {
            normalizedUrl += ":\(port!)"
        }
        normalizedUrl += "/\(path)"
        
        // query params
        var queryParams: [String: String] = [:]
        if let items = components.queryItems {
            for item in items {
                queryParams[item.name] = item.value ?? ""
            }
        }
        
        var allParams = params
        for (k, v) in queryParams { allParams[k] = v }
        allParams.removeValue(forKey: "oauth_signature")
        
        let sortedKeys = allParams.keys.sorted()
        let normalizedPairs: [String] = sortedKeys.compactMap { key in
            guard let value = allParams[key] else { return nil }
            return "\(rfc3986Encode(key))=\(rfc3986Encode(value))"
        }
        let paramString = normalizedPairs.joined(separator: "&")
        
        let baseString = "\(method.uppercased())&\(rfc3986Encode(normalizedUrl))&\(rfc3986Encode(paramString))"
        let signingKey = "\(rfc3986Encode(consumerSecret))&"
        
        let signatureData = hmacSHA1(data: baseString.data(using: .utf8)!,
                                     key: signingKey.data(using: .utf8)!)
        let signature = signatureData.base64EncodedString()
        
        // Optional debug:
        print("Signature base string:", baseString)
        print("signingKey:", signingKey)
        print("signature:", signature)
        
        return signature
    }
    
    static func buildAuthorizationHeader(oauthParams: [String: String]) -> String {
        var parts: [String] = []
        
        for (key, value) in oauthParams where key.hasPrefix("oauth_") {
            parts.append("\(rfc3986Encode(key))=\"\(rfc3986Encode(value))\"")
        }
        
        return "OAuth " + parts.sorted().joined(separator: ", ")
    }
    
    static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { dataPtr in
            CC_SHA256(dataPtr.baseAddress, CC_LONG(data.count), &result)
        }
        return result.map { String(format: "%02x", $0) }.joined()
    }
    
    private static func rfc3986Encode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
    
    private static func hmacSHA1(data: Data, key: Data) -> Data {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { dataPtr in
            key.withUnsafeBytes { keyPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1),
                       keyPtr.baseAddress, key.count,
                       dataPtr.baseAddress, data.count,
                       &result)
            }
        }
        return Data(result)
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
