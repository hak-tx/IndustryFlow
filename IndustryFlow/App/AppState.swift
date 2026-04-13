import Foundation

@Observable
final class AppState {
    var isDictating: Bool = false
    var liveTranscript: String = ""
    var selectedProfile: IndustryProfile = .general
    var selectedFormat: WritingFormat = .general
    var customGlossary: CustomGlossary?
    var polishedText: String?
    var isPolishing: Bool = false
    var showOnboarding: Bool = false
    var errorMessage: String?
    var lastSession: TranscriptionSession?

    // Track the target app so we can insert text into it
    var targetAppPID: pid_t?
    var targetAppName: String?

    /// Combined vocabulary hints: industry profile + custom glossary terms.
    var allVocabularyHints: [String] {
        var hints = selectedProfile.vocabularyHints
        if let glossary = customGlossary {
            hints.append(contentsOf: glossary.vocabularyHints)
        }
        return hints
    }

    init() {
        // Load saved glossary on startup
        customGlossary = GlossaryStorage.load()
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
