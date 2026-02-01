//
//  BitmeshClient.swift
//  AIPoemCreator
//
//  Created on 1/7/26.
//

import Foundation

// MARK: - Chat Message Types

public struct ChatMessage: Codable, Sendable {
    public let role: String
    public let content: String
    
    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }
    
    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }
    
    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

// MARK: - Request/Response Types

public struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    
    // Additional fields can be added via extraPayload in chat()
}

public struct ChatChoice: Codable, Sendable {
    let message: ChatMessage
    let index: Int?
    let finishReason: String?
    
    public enum CodingKeys: String, CodingKey {
        case message
        case index
        case finishReason = "finish_reason"
    }
}

public struct ChatResponse: Codable, Sendable {
    let choices: [ChatChoice]
    let model: String?
    let id: String?
    
    /// Convenience accessor for the first choice's message content
    public var content: String? {
        choices.first?.message.content
    }
}

// MARK: - Errors

public enum BitmeshClientError: LocalizedError {
    case encodingFailed
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case noContent
    case decodingFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode request body"
        case .invalidResponse:
            return "Invalid HTTP response"
        case .httpError(let code, let body):
            return "HTTP error \(code): \(body ?? "No body")"
        case .noContent:
            return "No content in response"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - BitmeshClient

/// A client for calling the Bitmesh AI Proxy API using OAuth 1.0 authentication.
///
/// Usage examples:
/// ```swift
/// // Basic usage with async/await
/// let client = BitmeshClient(consumerKey: "...", consumerSecret: "...")
/// let response = try await client.chat("What is the meaning of life?")
/// print(response.content ?? "No response")
///
/// // With custom model
/// let response2 = try await client.chat("Hello", model: "gpt-4")
///
/// // Get just the content string
/// let content = try await client.chatContent("Tell me a joke")
///
/// // With full message array
/// let messages = [
///     ChatMessage.system("You are a helpful assistant."),
///     ChatMessage.user("What is AI?")
/// ]
/// let response3 = try await client.chat(messages: messages)
///
/// // Using credentials from Bundle (auto-loads from Info.plist)
/// let bundleClient = BitmeshClient()
///
/// // Completion handler style (for older code)
/// bundleClient.chat("Hello") { result in
///     switch result {
///     case .success(let response):
///         print(response.content ?? "")
///     case .failure(let error):
///         print("Error: \(error)")
///     }
/// }
/// ```
public final actor BitmeshClient {
    
    // MARK: - Properties
    
    private let consumerKey: String
    private let consumerSecret: String
    private let baseURL: URL
    private let session: URLSession
    
    /// Default model used when none is specified
    public static let defaultModel = "meta-llama/Llama-3.2-3B-Instruct-Turbo"
    
    // MARK: - Initialization
    
    /// Creates a new BitmeshClient instance.
    /// - Parameters:
    ///   - consumerKey: OAuth consumer key
    ///   - consumerSecret: OAuth consumer secret
    ///   - baseURL: Base URL for the API (defaults to production)
    ///   - session: URLSession to use (defaults to shared)
    public init(
        consumerKey: String,
        consumerSecret: String,
        baseURL: String = "https://aiproxyapi-production.up.railway.app",
        session: URLSession = .shared
    ) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.baseURL = URL(string: baseURL)!
        self.session = session
    }
    
    /// Convenience initializer that loads credentials from Bundle
    public init(baseURL: String = "https://aiproxyapi-production.up.railway.app") {
        let consumerKey = Bundle.main.infoDictionary?["CONSUMER_KEY"] as? String ?? ""
        let consumerSecret = Bundle.main.infoDictionary?["CONSUMER_SECRET"] as? String ?? ""
        
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.baseURL = URL(string: baseURL)!
        self.session = .shared
    }
    
    // MARK: - Chat API (Async/Await)
    
    /// Sends a chat request with a simple string prompt.
    /// - Parameters:
    ///   - prompt: The user's message
    ///   - model: Model to use (defaults to Llama-3.2-3B-Instruct-Turbo)
    /// - Returns: The chat response
    @concurrent public func chat(_ prompt: String, model: String? = nil) async throws -> ChatResponse {
        let messages = [ChatMessage.user(prompt)]
        return try await chat(messages: messages, model: model)
    }
    
    /// Sends a chat request with a full messages array.
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - model: Model to use (defaults to Llama-3.2-3B-Instruct-Turbo)
    ///   - extraPayload: Additional fields to merge into the request JSON
    /// - Returns: The chat response
    @concurrent public func chat(
        messages: [ChatMessage],
        model: String? = nil,
        extraPayload: [String: Any] = [:]
    ) async throws -> ChatResponse {
        let url = baseURL.appendingPathComponent("chat")
        let modelToUse = model ?? Self.defaultModel
        
        // Build request payload
        var payload: [String: Any] = [
            "model": modelToUse,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        
        // Merge extra payload
        for (key, value) in extraPayload {
            payload[key] = value
        }
        
        // Encode to JSON
        guard
            let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
            let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            throw BitmeshClientError.encodingFailed
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60 * 60 * 6 
        
        // OAuth 1.0 signing
        let oauthParams = OAuthHelper.generateOAuthParams(
            method: "POST",
            url: url.absoluteString,
            consumerKey: consumerKey,
            consumerSecret: consumerSecret
        )
        
        let authHeader = OAuthHelper.buildAuthorizationHeader(oauthParams: oauthParams)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        // X-Payload-Signature = sha256(jsonBody + consumerKey + oauth_signature)
        let payloadSignatureInput = jsonString + consumerKey + (oauthParams["oauth_signature"] ?? "")
        let payloadSignature = OAuthHelper.sha256Hex(payloadSignatureInput)
        request.setValue(payloadSignature, forHTTPHeaderField: "X-Payload-Signature")
        
        // Execute request
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BitmeshClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw BitmeshClientError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
        
        do {
            let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
            return chatResponse
        } catch {
            throw BitmeshClientError.decodingFailed(error)
        }
    }
    
    // MARK: - Chat API (Completion Handler)
    
    /// Sends a chat request with a simple string prompt using completion handler.
    /// - Parameters:
    ///   - prompt: The user's message
    ///   - model: Model to use (defaults to Llama-3.2-3B-Instruct-Turbo)
    ///   - completion: Completion handler with Result
    public func chat(
        _ prompt: String,
        model: String? = nil,
        completion: @escaping @Sendable (Result<ChatResponse, Error>) -> Void
    ) {
        let messages = [ChatMessage.user(prompt)]
        chat(messages: messages, model: model, completion: completion)
    }
    
    /// Sends a chat request with a full messages array using completion handler.
    /// - Parameters:
    ///   - messages: Array of chat messages
    ///   - model: Model to use (defaults to Llama-3.2-3B-Instruct-Turbo)
    ///   - extraPayload: Additional fields to merge into the request JSON
    ///   - completion: Completion handler with Result
    public func chat(
        messages: [ChatMessage],
        model: String? = nil,
        extraPayload: [String: Any] = [:],
        completion: @escaping @MainActor (Result<ChatResponse, Error>) -> Void
    ) {
        Task {
            do {
                let response = try await self.chat(
                    messages: messages,
                    model: model,
                    extraPayload: extraPayload
                )
                await completion(.success(response))
            } catch {
                await completion(.failure(error))
            }
        }
    }
}

// MARK: - Convenience Extensions

public extension BitmeshClient {
    
    /// Quick helper to get just the content string from a chat response
    @concurrent public func chatContent(_ prompt: String, model: String? = nil) async throws -> String {
        let response = try await chat(prompt, model: model)
        guard let content = response.content else {
            throw BitmeshClientError.noContent
        }
        return content
    }
    
    /// Quick helper with completion handler
    public func chatContent(
        _ prompt: String,
        model: String? = nil,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        Task {
            do {
                let content = try await chatContent(prompt, model: model)
                await completion(.success(content))
            } catch {
                await completion(.failure(error))
            }
        }
    }
}
