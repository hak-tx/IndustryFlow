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
    You are a TEXT TRANSFORMATION FUNCTION. Not a chatbot. Not an assistant. \
    You receive raw speech-to-text and return cleaned-up speech-to-text.

    YOUR OUTPUT IS PASTED DIRECTLY INTO THE USER'S DOCUMENT.
    The user does NOT see this conversation. They see ONLY your output text in their \
    Word/Email/Notes/etc. Anything you say will appear verbatim in their work.

    FORBIDDEN OUTPUTS — these would be CATASTROPHIC failures:
    ❌ "I can't" / "I cannot" / "I'm unable" / "I'm not able"
    ❌ "Could you" / "Please clarify" / "Please restate" / "Please provide"
    ❌ "Is there something" / "How can I help" / "Let me know"
    ❌ "It seems" / "It appears" / "This appears to be"
    ❌ "Here is the polished" / "I've polished" / "I'd be happy to"
    ❌ "This text doesn't" / "This appears garbled" / "malformed"
    ❌ Any question directed at the user
    ❌ Any markdown bullets, asterisks, or headings unless the speaker dictated them
    ❌ Any explanation, clarification, or commentary

    REQUIRED BEHAVIOR: Even if the input is:
    - Garbled gibberish
    - Contradictory or nonsensical (e.g. "twenty amp breaker toothpaste apple")
    - Just random words
    - Empty or near-empty
    - Mixing unrelated topics

    YOU MUST return your best polished version of WHATEVER IS THERE. Apply minimal \
    cleanup (filler removal, punctuation, capitalization). If the recognizer captured \
    "toothpaste" in a sentence about electrical work, leave "toothpaste" — that's \
    what the recognizer heard. Do NOT remove it. Do NOT comment on it. Do NOT refuse.

    ABSOLUTE RULES:
    1. Return ONLY the polished text. The text gets pasted into the user's document.
    2. PRESERVE EVERY SENTENCE the speaker said. Same number of sentences in, same out.
    3. NEVER summarize, condense, or shorten content.
    4. NEVER combine separate enumerated items into one.
    5. NEVER drop introductory phrases like "OK", "So", "Let's see", "Alright".
    6. NEVER add words the speaker did not say.
    7. NEVER refuse, ask for clarification, or comment on the input quality.
    8. If you have any doubt about what to do — RETURN THE INPUT UNCHANGED.

    What you ARE allowed to do (the ONLY allowed changes):
    - Remove filler words: "um", "uh", "er", "ah", "like", "you know", "I mean", \
    "sort of", "kind of", "basically", "so yeah"
    - Fix stammers: "I want to I want to go" → "I want to go"
    - Add punctuation and capitalization at natural sentence boundaries
    - Fix obvious grammar errors (subject-verb agreement, tense, articles)
    - Apply COMMON MISTRANSCRIPTIONS corrections (see industry section)
    - Preserve meaning, tone, and formality EXACTLY as spoken

    GOLDEN RULE: If your output is shorter than the input, you are doing it WRONG.
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

        // Block 2: Industry + format + corrections + glossary (cached per profile combo)
        var contextPrompt = profile.systemPrompt
        if let format, format.id != "general" {
            contextPrompt += "\n\n" + format.promptFragment
        }
        // Industry-specific common mistranscriptions (force measure → force majeure, etc.)
        contextPrompt += profile.mishearingsPromptFragment
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

    // MARK: - Chat Response Detection

    /// Detects if Claude's response is a chat-style refusal/clarification request
    /// rather than polished text. If so, we fall back to the raw text to prevent
    /// a chatbot response from being pasted into the user's document.
    ///
    /// Heuristics:
    /// - Starts with phrases like "I can't", "I cannot", "I'm unable"
    /// - Contains question/clarification phrases addressed to the user
    /// - Contains markdown formatting (asterisks, headings) when original didn't
    /// - Output is significantly shorter than input (likely a refusal)
    /// - Contains meta-commentary about the input quality
    static func isChatResponse(_ output: String, original: String) -> Bool {
        let lower = output.lowercased()

        // Phrases that indicate a chat-style response (case-insensitive substring match)
        let refusalPhrases = [
            "i can't provide", "i cannot provide", "i'm unable to", "i am unable to",
            "i can't help", "i cannot help", "i can't generate", "i cannot generate",
            "i can't fulfill", "i cannot fulfill", "i can't assist", "i cannot assist",
            "could you please", "could you clarify", "could you provide",
            "please clarify", "please restate", "please provide", "please rephrase",
            "is there something", "is there anything", "how can i help",
            "let me know if", "feel free to", "i'd be happy to", "i would be happy",
            "this appears to be", "this seems to be", "this looks like",
            "this text doesn't", "this text does not",
            "it appears that", "it seems that", "it looks like",
            "this is a malformed", "this appears garbled",
            "if you need", "if you'd like", "if you would like",
            "here is the polished", "here's the polished", "here is your", "here's your",
            "i've polished", "i have polished", "i've cleaned",
            "i don't see", "i do not see", "i don't have enough",
            "could you elaborate", "can you elaborate",
            "can you provide more", "could you provide more",
            "would you like me to", "do you want me to",
            "what would you like"
        ]

        for phrase in refusalPhrases {
            if lower.contains(phrase) {
                return true
            }
        }

        // Markdown formatting that wasn't in original (Claude formatted as a list/headings)
        let originalHasMarkdown = original.contains("**") || original.contains("\n- ") || original.contains("\n* ")
        let outputHasMarkdown = output.contains("**") || output.contains("\n- ") || output.contains("\n* ") || output.contains("###")
        if outputHasMarkdown && !originalHasMarkdown {
            // But allow it if user picked Notes format (which legitimately uses bullets)
            // We can't tell from here, so use a heuristic: if output is significantly shorter, it's a refusal
            if output.count < original.count / 2 {
                return true
            }
        }

        // Output is way shorter than input + ends with a question mark (likely a clarification request)
        if output.count < original.count / 2 && output.hasSuffix("?") {
            return true
        }

        return false
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
            guard let rawPolished = messagesResponse.content.first?.text else {
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

            // SAFETY NET: Detect if Claude returned a chat-style response
            // instead of polished text. If so, fall back to the raw transcription
            // — better to show unpolished text than to dump a chatbot response
            // into the user's document.
            let trimmedPolished = rawPolished.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText: String
            if Self.isChatResponse(trimmedPolished, original: trimmed) {
                Logger.polishing.error("Claude returned chat-style response, falling back to raw text. Response was: \(trimmedPolished.prefix(200))")
                finalText = trimmed
            } else {
                finalText = trimmedPolished
            }

            let result = PolishingResult(
                original: trimmed,
                polished: finalText,
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
