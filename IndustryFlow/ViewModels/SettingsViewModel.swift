import Foundation
import os

@Observable
@MainActor
final class SettingsViewModel {
    var apiKey: String = ""
    var isValidatingKey: Bool = false
    var keyValidationResult: KeyValidationResult?
    var selectedProfileID: String = "general"
    var autoPolish: Bool = true

    private let polishingService = ClaudePolishingService()

    enum KeyValidationResult: Equatable {
        case valid
        case invalid
        case error(String)
    }

    init() {
        loadSettings()
    }

    func loadSettings() {
        apiKey = KeychainHelper.retrieve() ?? ""
        selectedProfileID = UserDefaults.standard.string(forKey: "selectedProfileID") ?? "general"
        autoPolish = UserDefaults.standard.object(forKey: "autoPolish") as? Bool ?? true
    }

    func saveAPIKey() {
        do {
            try KeychainHelper.save(apiKey: apiKey)
            Logger.app.info("API key saved to keychain")
        } catch {
            Logger.app.error("Failed to save API key: \(error.localizedDescription)")
        }
    }

    func validateAPIKey() {
        guard !apiKey.isEmpty else {
            keyValidationResult = .invalid
            return
        }

        isValidatingKey = true
        keyValidationResult = nil

        Task {
            let valid = await polishingService.validateAPIKey(apiKey)
            await MainActor.run {
                isValidatingKey = false
                keyValidationResult = valid ? .valid : .invalid
            }
        }
    }

    func deleteAPIKey() {
        KeychainHelper.delete()
        apiKey = ""
        keyValidationResult = nil
        Logger.app.info("API key deleted from keychain")
    }

    func saveProfileSelection() {
        UserDefaults.standard.set(selectedProfileID, forKey: "selectedProfileID")
    }

    func saveAutoPolish() {
        UserDefaults.standard.set(autoPolish, forKey: "autoPolish")
    }

    var selectedProfile: IndustryProfile {
        IndustryProfile.allProfiles.first { $0.id == selectedProfileID } ?? .general
    }
}
