import Foundation
import os

final class ClaudePolishingService {

    // MARK: - API Types

    private struct MessagesRequest: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

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
        }
    }

    private struct APIError: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let type: String
            let message: String
        }
    }

    // MARK: - Polishing

    func polish(text: String, profile: IndustryProfile) async throws -> PolishingResult {
        guard let apiKey = KeychainHelper.retrieve(), !apiKey.isEmpty else {
            throw PolishingError.missingAPIKey
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PolishingError.emptyText
        }

        Logger.polishing.info("Polishing \(trimmed.count) characters with profile: \(profile.name)")

        let requestBody = MessagesRequest(
            model: Constants.defaultModel,
            max_tokens: Constants.maxPolishingTokens,
            system: profile.systemPrompt,
            messages: [
                .init(
                    role: "user",
                    content: """
                    Polish the following dictated text. Return ONLY the polished text, \
                    no commentary, explanation, or preamble:

                    <dictated_text>
                    \(trimmed)
                    </dictated_text>
                    """
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

            let result = PolishingResult(
                original: trimmed,
                polished: polishedText.trimmingCharacters(in: .whitespacesAndNewlines),
                profile: profile,
                tokensUsed: messagesResponse.usage.map { $0.input_tokens + $0.output_tokens }
            )

            Logger.polishing.info("Polishing complete. Tokens used: \(result.tokensUsed ?? 0)")
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

    /// Quick validation that the API key works by sending a minimal request.
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
            system: "Reply with OK",
            messages: [.init(role: "user", content: "Hi")]
        )
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode == 200
            }
            return false
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
        case .missingAPIKey:
            return "No API key configured. Please add your Anthropic API key in Settings."
        case .invalidAPIKey:
            return "The API key is invalid. Please check your Anthropic API key in Settings."
        case .emptyText:
            return "No text to polish."
        case .invalidResponse:
            return "Received an invalid response from the API."
        case .emptyResponse:
            return "The API returned an empty response."
        case .rateLimited:
            return "API rate limit reached. Please wait a moment and try again."
        case .serverError:
            return "The Anthropic API is experiencing issues. Please try again later."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
