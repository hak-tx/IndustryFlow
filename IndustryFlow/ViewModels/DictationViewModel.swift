import Foundation
import AppKit
import os

@Observable
@MainActor
final class DictationViewModel {
    let appState: AppState
    let permissionsService: PermissionsService

    private let transcriptionService = SpeechTranscriptionService()
    private let accessibilityService = AccessibilityService()
    private let polishingService = ClaudePolishingService()

    private var transcriptionTask: Task<Void, Never>?

    /// The longest transcript we've seen — we only type forward past this.
    private var highWaterText = ""

    /// Total characters we've typed into the target app.
    private var typedCharacterCount = 0

    init(appState: AppState, permissionsService: PermissionsService) {
        self.appState = appState
        self.permissionsService = permissionsService
    }

    // MARK: - Dictation Control

    func toggleDictation() {
        if appState.isDictating {
            stopDictation()
        } else {
            startDictation()
        }
    }

    func startDictation() {
        permissionsService.refreshStatus()

        if !permissionsService.allPermissionsGranted {
            var missing: [String] = []
            if !permissionsService.microphoneGranted { missing.append("Microphone") }
            if !permissionsService.speechRecognitionGranted { missing.append("Speech Recognition") }
            if !permissionsService.accessibilityGranted { missing.append("Accessibility") }
            appState.errorMessage = "Missing: \(missing.joined(separator: ", "))"
            return
        }

        // If started from the popover, close it and return focus to previous app
        let ourBundleID = Bundle.main.bundleIdentifier ?? "com.industryflow.app"
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ourBundleID {
            NotificationCenter.default.post(name: .closePopoverForDictation, object: nil)

            // Find and activate the previous app
            for app in NSWorkspace.shared.runningApplications where
                app.activationPolicy == .regular &&
                app.bundleIdentifier != ourBundleID &&
                !app.isTerminated {
                app.activate()
                break
            }
            usleep(300_000) // 300ms for focus to settle
        }

        appState.clearError()
        appState.liveTranscript = ""
        appState.polishedText = nil

        // Reset live typing state
        highWaterText = ""
        typedCharacterCount = 0

        // Record target app name for UI display
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appState.targetAppName = frontApp.localizedName
        }

        appState.isDictating = true

        Logger.app.info("Dictation started — \(self.appState.selectedProfile.name) / \(self.appState.selectedFormat.name)")

        // Start transcription with industry vocabulary hints
        let hints = appState.allVocabularyHints
        let stream = transcriptionService.startTranscription(vocabularyHints: hints)

        transcriptionTask = Task { [weak self] in
            for await update in stream {
                guard let self, self.appState.isDictating else { break }

                switch update {
                case .partial(let text), .final_(let text):
                    self.appState.liveTranscript = text
                    self.handlePartialResult(text)

                case .error(let message):
                    Logger.app.error("Transcription error: \(message)")
                    self.appState.errorMessage = "Transcription error: \(message)"
                    self.appState.isDictating = false
                }
            }
        }
    }

    func stopDictation() {
        guard appState.isDictating else { return }

        Logger.app.info("Dictation stopped — \(self.typedCharacterCount) characters typed")

        transcriptionService.stopTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        appState.isDictating = false

        let rawText = highWaterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            Logger.app.info("No text was transcribed")
            return
        }

        // Raw text is already in the target app (typed live via CGEvent).
        // Now polish it and replace.
        polishAndReplace(rawText: rawText, characterCount: typedCharacterCount)
    }

    // MARK: - Live Typing

    /// Called on every partial/final transcription result.
    /// Types ONLY new characters beyond what we've already typed.
    /// Never backspaces — only moves forward.
    ///
    /// IMPORTANT: Typing is dispatched off the main actor so it doesn't
    /// block the transcription stream from delivering the next update.
    private func handlePartialResult(_ newText: String) {
        guard newText.count > typedCharacterCount else { return }

        let delta = String(newText.suffix(newText.count - typedCharacterCount))
        guard !delta.isEmpty else { return }

        let service = accessibilityService
        typedCharacterCount += delta.count
        highWaterText = newText

        // Type on a background queue so we don't block the main thread
        // (typeText uses usleep for inter-character timing)
        DispatchQueue.global(qos: .userInteractive).async {
            service.typeText(delta)
        }
    }

    // MARK: - Polish and Replace

    private func polishAndReplace(rawText: String, characterCount: Int) {
        appState.isPolishing = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.polishingService.polish(
                    text: rawText,
                    profile: self.appState.selectedProfile,
                    format: self.appState.selectedFormat,
                    glossary: self.appState.customGlossary
                )

                await MainActor.run {
                    self.appState.polishedText = result.polished
                    self.appState.isPolishing = false

                    if result.polished != rawText {
                        // Select the raw text we typed and replace with polished version
                        self.accessibilityService.selectAndReplace(
                            result.polished,
                            characterCount: characterCount
                        )
                        Logger.app.info("Replaced raw text with polished version")
                    }
                }
            } catch {
                await MainActor.run {
                    self.appState.errorMessage = error.localizedDescription
                    self.appState.isPolishing = false
                    Logger.app.error("Polishing failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
