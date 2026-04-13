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

    /// Types only genuinely NEW characters that extend past what we've already typed.
    ///
    /// Dead simple: track the count of characters we've typed. If the recognizer
    /// sends text longer than that count, type the suffix. If it sends shorter
    /// text (during revision or chain), ignore it completely.
    ///
    /// This means: we ONLY ever type forward. Never overwrite. Never backspace.
    /// Mid-dictation text might have small inaccuracies from recognizer revisions,
    /// but Claude fixes everything during polishing. Zero words are lost.
    private func handleTranscriptionUpdate(_ newText: String) {
        let currentCount = actuallyTypedText.count

        // ONLY type forward — if recognizer text is shorter or equal, skip entirely.
        // This prevents overwrites during chain transitions and recognizer revisions.
        guard newText.count > currentCount else { return }

        // Extract only the characters past what we've already typed
        let deltaStart = newText.index(newText.startIndex, offsetBy: currentCount)
        let delta = String(newText[deltaStart...])
        guard !delta.isEmpty else { return }

        // Update our record BEFORE dispatching (prevents race with next partial)
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
