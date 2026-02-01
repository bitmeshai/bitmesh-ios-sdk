import Foundation
import Bitmesh

// MARK: - Result Model

struct TogetherStoryResult: Codable {
    let title: String
    let body: String
}

// MARK: - TogetherAPIClient (Bitmesh-backed) — SINGLE REQUEST PER FEATURE

final class TogetherAPIClient {
    
    enum APIError: LocalizedError {
        case missingCredentials
        case invalidResponse
        case server(String)
        
        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Missing CONSUMER_KEY / CONSUMER_SECRET in Info.plist."
            case .invalidResponse:
                return "Could not read content from the AI response."
            case .server(let message):
                return message
            }
        }
    }
    
    private let session: URLSession
    private let client: BitmeshClient
    
    // ✅ DeepSeek V3 on Together
    private let storyModel = "openai/gpt-4o-mini"
    private let paraphraseModel = "openai/gpt-4o-mini"
    
    init() {
            let config = URLSessionConfiguration.default

            // “Effectively infinite” (use a very large value)
            config.timeoutIntervalForRequest = 60 * 60 * 6       // 6 hours
            config.timeoutIntervalForResource = 60 * 60 * 6      // 6 hours

            // Optional: helps on bad networks
            config.waitsForConnectivity = true

            self.session = URLSession(configuration: config)

            // IMPORTANT:
            // BitmeshClient must use THIS session, otherwise these timeouts do nothing.
            self.client = BitmeshClient(
                consumerKey: Bundle.main.infoDictionary?["CONSUMER_KEY"] as? String ?? "",
                consumerSecret: Bundle.main.infoDictionary?["CONSUMER_SECRET"] as? String ?? "",
                session: self.session // <-- add this to BitmeshClient
            )
        }
    
    private func ensureCredentials() throws {
        let ck = Bundle.main.infoDictionary?["CONSUMER_KEY"] as? String
        let cs = Bundle.main.infoDictionary?["CONSUMER_SECRET"] as? String
        if (ck ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (cs ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APIError.missingCredentials
        }
    }
    
    // MARK: - Length Spec
    
    private struct LengthSpec {
        let minWords: Int
        let maxWords: Int
        let minParagraphs: Int
        let maxParagraphs: Int
        let chapters: Int? // only for long (optional)
    }
    
    // MARK: - Public API
    
    /// Single request paraphrase (returns ONLY the rewritten prompt).
    func generateParaphrase(for prompt: String, language: String? = nil) async throws -> String {
        try ensureCredentials()
        
        let langRule: String = {
            let l = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if l.isEmpty {
                return "Write in the same language as the user's text."
            }
            return "Write strictly in \(l). Do not use any other language."
        }()
        
        let messages: [TogetherMessage] = [
            TogetherMessage(
                role: "system",
                content: """
                You rewrite user story prompts.
                
                RULES:
                - Keep the original meaning.
                - Make it short, clear, and easy to understand.
                - Do NOT add new details.
                - Return ONLY the rewritten prompt (no quotes, no bullets, no extra text).
                - \(langRule)
                """
            ),
            TogetherMessage(role: "user", content: prompt)
        ]
        
        let raw = try await requestCompletion(model: paraphraseModel, messages: messages)
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleaned.isEmpty else { throw APIError.invalidResponse }
        return cleaned
    }
    
    // MARK: - Bitmesh Request
    
    private func requestCompletion(
        model: String,
        messages: [TogetherMessage]
    ) async throws -> String {
        
        let chatMessages: [ChatMessage] = messages.map { msg in
            switch msg.role {
            case "system": return .system(msg.content)
            case "assistant": return .assistant(msg.content)
            default: return .user(msg.content)
            }
        }
        
        do {
            let response = try await client.chat(
                messages: chatMessages,
                model: model
            )
            
            let content = (response.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { throw APIError.invalidResponse }
            return content
        } catch {
            throw APIError.server(error.localizedDescription)
        }
    }
}

// MARK: - Local DTOs

private struct TogetherMessage: Codable {
    let role: String
    let content: String
}
