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

    /// What we have ACTUALLY typed into the target app via CGEvent.
    /// This is the source of truth — not the recognizer's output.
    private var actuallyTypedText = ""

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

            for app in NSWorkspace.shared.runningApplications where
                app.activationPolicy == .regular &&
                app.bundleIdentifier != ourBundleID &&
                !app.isTerminated {
                app.activate()
                break
            }
            usleep(300_000)
        }

        appState.clearError()
        appState.liveTranscript = ""
        appState.polishedText = nil
        actuallyTypedText = ""

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appState.targetAppName = frontApp.localizedName
        }

        appState.isDictating = true

        Logger.app.info("Dictation started — \(self.appState.selectedProfile.name) / \(self.appState.selectedFormat.name)")

        let hints = appState.allVocabularyHints
        let stream = transcriptionService.startTranscription(vocabularyHints: hints)

        transcriptionTask = Task { [weak self] in
            for await update in stream {
                guard let self, self.appState.isDictating else { break }

                switch update {
                case .partial(let text), .final_(let text):
                    self.appState.liveTranscript = text
                    self.handleTranscriptionUpdate(text)

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

        Logger.app.info("Dictation stopped — \(self.actuallyTypedText.count) characters typed")

        transcriptionService.stopTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        appState.isDictating = false

        let rawText = actuallyTypedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            Logger.app.info("No text was transcribed")
            return
        }

        polishAndReplace(rawText: rawText, characterCount: actuallyTypedText.count)
    }

    // MARK: - Live Typing

    /// Compares the new transcription text with what we've already typed.
    /// Types only the genuinely new suffix.
    ///
    /// Uses string prefix matching — finds how much of `actuallyTypedText`
    /// matches the beginning of `newText`, then types only what's after that.
    ///
    /// When the recognizer chains (new session after pause), the accumulated
    /// transcript includes old text + new text. Since `actuallyTypedText`
    /// already matches the old portion, we only type the new words.
    private func handleTranscriptionUpdate(_ newText: String) {
        // Find the longest prefix of newText that matches actuallyTypedText
        // (case-insensitive because the recognizer may change capitalization)
        let newLower = newText.lowercased()
        let typedLower = actuallyTypedText.lowercased()

        // How much of what we typed is still present at the start of the new text?
        var matchLength = 0
        let minLen = min(newLower.count, typedLower.count)

        for i in 0..<minLen {
            let newIdx = newLower.index(newLower.startIndex, offsetBy: i)
            let typedIdx = typedLower.index(typedLower.startIndex, offsetBy: i)
            if newLower[newIdx] == typedLower[typedIdx] {
                matchLength = i + 1
            } else {
                break
            }
        }

        // If the new text extends beyond what we've typed, type the delta
        guard newText.count > matchLength else { return }

        let deltaStartIndex = newText.index(newText.startIndex, offsetBy: matchLength)
        let delta = String(newText[deltaStartIndex...])
        guard !delta.isEmpty else { return }

        // Update our record BEFORE dispatching the typing
        actuallyTypedText += delta

        // Type on background queue (typeText uses usleep for timing)
        let service = accessibilityService
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
