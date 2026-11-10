import Foundation

// MARK: - Chat message helpers

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

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

/// Tokens the request was billed for.
public struct ChatUsage: Codable, Sendable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

public struct ChatChoice: Codable, Sendable {
    public let message: ChatMessage
    public let index: Int?
    public let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case index
        case finishReason = "finish_reason"
    }
}

public struct ChatResponse: Codable, Sendable {
    public let choices: [ChatChoice]
    public let model: String?
    public let id: String?
    public let usage: ChatUsage?

    public var content: String? {
        choices.first?.message.content
    }
}

/// One piece of a streamed reply.
public struct ChatStreamChunk: Decodable, Sendable {
    public struct Delta: Decodable, Sendable {
        public let role: String?
        public let content: String?
    }

    public struct Choice: Decodable, Sendable {
        public let index: Int?
        public let delta: Delta?
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    public let id: String?
    public let model: String?
    public let choices: [Choice]

    /// Set on the last chunk only.
    public let usage: ChatUsage?

    /// The text this chunk adds to the first choice, or `""`.
    public var text: String {
        choices.first?.delta?.content ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, model, choices, usage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        usage = try container.decodeIfPresent(ChatUsage.self, forKey: .usage)
    }
}

public extension BitmeshClient {
    /// Default model when using the simple chat helpers.
    static let defaultChatModel = "bitmeshai/chat-now-nano"

    /// Sends a chat request built from plain-text messages.
    func chat(
        messages: [ChatMessage],
        model: String? = nil,
        extraPayload: BitmeshJSON = [:]
    ) async throws -> ChatResponse {
        let json = try await chat(payload: Self.chatPayload(messages, model, extraPayload))
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    /// Single user prompt convenience.
    func chat(_ prompt: String, model: String? = nil) async throws -> ChatResponse {
        try await chat(messages: [.user(prompt)], model: model)
    }

    /// Returns assistant text from the first choice.
    func chatContent(_ prompt: String, model: String? = nil) async throws -> String {
        guard let content = try await chat(prompt, model: model).content else {
            throw BitmeshError.validation("No content in response")
        }
        return content
    }

    /// Streams the reply to plain-text messages while it is written.
    ///
    /// ```swift
    /// for try await chunk in client.streamChat(messages: [.user("Hello")]) {
    ///     reply += chunk.text
    /// }
    /// ```
    func streamChat(
        messages: [ChatMessage],
        model: String? = nil,
        extraPayload: BitmeshJSON = [:]
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let raw = chatStream(payload: Self.chatPayload(messages, model, extraPayload))
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await json in raw {
                        let data = try JSONSerialization.data(withJSONObject: json)
                        continuation.yield(try JSONDecoder().decode(ChatStreamChunk.self, from: data))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func chatPayload(_ messages: [ChatMessage], _ model: String?, _ extra: BitmeshJSON) -> BitmeshJSON {
        var payload: BitmeshJSON = [
            "model": model ?? defaultChatModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }
}
