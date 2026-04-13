import Foundation

@Observable
final class AppState {
    var isDictating: Bool = false
    var liveTranscript: String = ""
    var selectedProfile: IndustryProfile = .general
    var polishedText: String?
    var isPolishing: Bool = false
    var showOnboarding: Bool = false
    var errorMessage: String?
    var lastSession: TranscriptionSession?

    // Track the target app so we can insert text into it
    var targetAppPID: pid_t?
    var targetAppName: String?

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
