import Foundation
import AppKit
import UniformTypeIdentifiers
import os

@Observable
@MainActor
final class SettingsViewModel {
    var apiKey: String = ""
    var isValidatingKey: Bool = false
    var keyValidationResult: KeyValidationResult?
    var selectedProfileID: String = "general"
    var autoPolish: Bool = true

    // Glossary state
    var glossaryImportError: String?
    var isImportingGlossary: Bool = false

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

    // MARK: - Glossary Import

    /// Opens a file picker and imports the selected CSV/TSV file as a custom glossary.
    func importGlossary(into appState: AppState) {
        glossaryImportError = nil

        let panel = NSOpenPanel()
        panel.title = "Import Company Terminology"
        panel.message = "Select a CSV or TSV file with your company's terminology. Column 1: Term/Acronym, Column 2: Definition (optional)."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType.tabSeparatedText,
            UTType.plainText,
        ]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        isImportingGlossary = true

        do {
            let glossary = try GlossaryImporter.importFile(at: url)
            try GlossaryStorage.save(glossary)
            appState.customGlossary = glossary
            glossaryImportError = nil
            Logger.app.info("Imported glossary: \(glossary.terms.count) terms from \(glossary.sourceFileName)")
        } catch {
            glossaryImportError = error.localizedDescription
            Logger.app.error("Glossary import failed: \(error.localizedDescription)")
        }

        isImportingGlossary = false
    }

    /// Removes the custom glossary.
    func deleteGlossary(from appState: AppState) {
        GlossaryStorage.delete()
        appState.customGlossary = nil
        glossaryImportError = nil
        Logger.app.info("Custom glossary deleted")
    }
}
