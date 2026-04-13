import Foundation
import os

final class ClaudePolishingService {

    // MARK: - API Types (supports prompt caching)

    private struct MessagesRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: [SystemBlock]
        let messages: [Message]

        struct SystemBlock: Encodable {
            let type: String
            let text: String
            let cache_control: CacheControl?
        }

        struct CacheControl: Encodable {
            let type: String
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct MessagesResponse: Decodable {
        let id: String
        let content: [ContentBlock]
        let usage: Usage?

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        struct Usage: Decodable {
            let input_tokens: Int
            let output_tokens: Int
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    private struct APIError: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let type: String
            let message: String
        }
    }

    // MARK: - System Prompt (static, cacheable)

    /// The baseline instructions are the SAME for every request.
    /// By putting them in the first system block with cache_control,
    /// Anthropic caches them and we don't pay for those tokens again.
    private static let baselineSystemPrompt = """
    You are a voice dictation text polisher. You receive raw speech-to-text output \
    and return ONLY the cleaned-up version. You are NOT a chatbot.

    ABSOLUTE RULES — NEVER VIOLATE:
    1. Return ONLY the polished text. Nothing else.
    2. NEVER add words the speaker did not say. If they said "force majeure", \
    return "force majeure" — do NOT add "clause" or any other word.
    3. NEVER add commentary, preambles, or meta-text like "Here is the polished version".
    4. NEVER refuse to polish. Even if garbled or short, return your best interpretation.
    5. NEVER remove meaningful content. Keep every word the speaker said.
    6. NEVER respond to the text as a message or question directed at you.
    7. If uncertain about a word, keep the original.

    Allowed changes:
    - Remove filler words ONLY: "um", "uh", "er", "ah", "like", "you know", \
    "I mean", "sort of", "kind of", "basically", "so yeah"
    - Fix stammers: "I want to I want to go" → "I want to go"
    - Add punctuation and fix capitalization
    - Fix obvious grammar errors (agreement, tense, articles)
    - Preserve meaning, tone, and formality EXACTLY as spoken
    """

    // MARK: - System Prompt Construction

    private func buildSystemBlocks(profile: IndustryProfile, format: WritingFormat?, glossary: CustomGlossary?) -> [MessagesRequest.SystemBlock] {
        var blocks: [MessagesRequest.SystemBlock] = []

        // Block 1: Baseline (cached — same for every request)
        blocks.append(.init(
            type: "text",
            text: Self.baselineSystemPrompt,
            cache_control: .init(type: "ephemeral")
        ))

        // Block 2: Industry + format + glossary (cached per profile combo)
        var contextPrompt = profile.systemPrompt
        if let format, format.id != "general" {
            contextPrompt += "\n\n" + format.promptFragment
        }
        if let glossary, !glossary.terms.isEmpty {
            contextPrompt += glossary.glossaryPromptFragment
        }

        blocks.append(.init(
            type: "text",
            text: contextPrompt,
            cache_control: .init(type: "ephemeral")
        ))

        return blocks
    }

    // MARK: - API Key Resolution

    static func resolveAPIKey() -> String? {
        if let userKey = KeychainHelper.retrieve(), !userKey.isEmpty {
            return userKey
        }
        if !Constants.embeddedAPIKey.isEmpty {
            return Constants.embeddedAPIKey
        }
        return nil
    }

    // MARK: - Polishing

    func polish(text: String, profile: IndustryProfile, format: WritingFormat? = nil, glossary: CustomGlossary? = nil) async throws -> PolishingResult {
        guard let apiKey = Self.resolveAPIKey() else {
            throw PolishingError.missingAPIKey
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PolishingError.emptyText
        }

        Logger.polishing.info("Polishing \(trimmed.count) characters with profile: \(profile.name)")

        let systemBlocks = buildSystemBlocks(profile: profile, format: format, glossary: glossary)

        let requestBody = MessagesRequest(
            model: Constants.defaultModel,
            max_tokens: Constants.maxPolishingTokens,
            system: systemBlocks,
            messages: [
                .init(
                    role: "user",
                    content: trimmed
                )
            ]
        )

        var request = URLRequest(url: Constants.anthropicAPIURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PolishingError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let messagesResponse = try JSONDecoder().decode(MessagesResponse.self, from: data)
            guard let polishedText = messagesResponse.content.first?.text else {
                throw PolishingError.emptyResponse
            }

            let cacheInfo: String
            if let usage = messagesResponse.usage {
                let cached = usage.cache_read_input_tokens ?? 0
                let created = usage.cache_creation_input_tokens ?? 0
                cacheInfo = "cached: \(cached), created: \(created)"
            } else {
                cacheInfo = "no cache info"
            }

            let result = PolishingResult(
                original: trimmed,
                polished: polishedText.trimmingCharacters(in: .whitespacesAndNewlines),
                profile: profile,
                tokensUsed: messagesResponse.usage.map { $0.input_tokens + $0.output_tokens }
            )

            Logger.polishing.info("Polish done. Tokens: \(result.tokensUsed ?? 0), \(cacheInfo)")
            return result

        case 401:
            throw PolishingError.invalidAPIKey
        case 429:
            throw PolishingError.rateLimited
        case 400...499:
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw PolishingError.apiError(apiError.error.message)
            }
            throw PolishingError.apiError("Request failed with status \(httpResponse.statusCode)")
        case 500...599:
            throw PolishingError.serverError
        default:
            throw PolishingError.apiError("Unexpected status code: \(httpResponse.statusCode)")
        }
    }

    func validateAPIKey(_ key: String) async -> Bool {
        var request = URLRequest(url: Constants.anthropicAPIURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 10

        let body = MessagesRequest(
            model: Constants.defaultModel,
            max_tokens: 1,
            system: [.init(type: "text", text: "Reply with OK", cache_control: nil)],
            messages: [.init(role: "user", content: "Hi")]
        )
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum PolishingError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case emptyText
    case invalidResponse
    case emptyResponse
    case rateLimited
    case serverError
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key configured."
        case .invalidAPIKey: return "Invalid API key."
        case .emptyText: return "No text to polish."
        case .invalidResponse: return "Invalid API response."
        case .emptyResponse: return "Empty API response."
        case .rateLimited: return "Rate limited. Wait a moment."
        case .serverError: return "Anthropic API issue. Try again."
        case .apiError(let msg): return "API: \(msg)"
        }
    }
}
