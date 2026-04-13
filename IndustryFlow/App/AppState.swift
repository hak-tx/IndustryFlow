import Foundation

@Observable
final class AppState {
    var isDictating: Bool = false
    var liveTranscript: String = ""
    var polishedText: String?
    var isPolishing: Bool = false
    var showOnboarding: Bool = false
    var errorMessage: String?
    var lastSession: TranscriptionSession?
    var targetAppPID: pid_t?
    var targetAppName: String?
    var customGlossary: CustomGlossary?

    /// Selected industry profile — persisted across launches.
    var selectedProfile: IndustryProfile = .general {
        didSet { UserDefaults.standard.set(selectedProfile.id, forKey: "selectedProfileID") }
    }

    /// Selected writing format — persisted across launches.
    var selectedFormat: WritingFormat = .general {
        didSet { UserDefaults.standard.set(selectedFormat.id, forKey: "selectedFormatID") }
    }

    /// Combined vocabulary hints: industry profile + custom glossary terms.
    var allVocabularyHints: [String] {
        var hints = selectedProfile.vocabularyHints
        if let glossary = customGlossary {
            hints.append(contentsOf: glossary.vocabularyHints)
        }
        return hints
    }

    init() {
        customGlossary = GlossaryStorage.load()

        // Restore saved selections
        if let profileID = UserDefaults.standard.string(forKey: "selectedProfileID"),
           let profile = IndustryProfile.allProfiles.first(where: { $0.id == profileID }) {
            selectedProfile = profile
        }
        if let formatID = UserDefaults.standard.string(forKey: "selectedFormatID"),
           let format = WritingFormat.allFormats.first(where: { $0.id == formatID }) {
            selectedFormat = format
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func reset() {
        isDictating = false
        liveTranscript = ""
        polishedText = nil
        isPolishing = false
        errorMessage = nil
        lastSession = nil
        targetAppPID = nil
        targetAppName = nil
    }
}
