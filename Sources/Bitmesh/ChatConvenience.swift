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

    public var content: String? {
        choices.first?.message.content
    }
}

public extension BitmeshClient {
    /// Default model when using the simple chat helpers.
    static let defaultChatModel = "meta-llama/Llama-3.2-3B-Instruct-Turbo"

    /// Sends a chat request built from plain-text messages.
    func chat(
        messages: [ChatMessage],
        model: String? = nil,
        extraPayload: BitmeshJSON = [:]
    ) async throws -> ChatResponse {
        var payload: BitmeshJSON = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let model {
            payload["model"] = model
        } else {
            payload["model"] = Self.defaultChatModel
        }
        for (key, value) in extraPayload {
            payload[key] = value
        }

        let json = try await chat(payload: payload)
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
}
