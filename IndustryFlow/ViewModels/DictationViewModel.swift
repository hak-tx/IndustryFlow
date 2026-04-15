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

    /// What is physically typed into the target document right now.
    /// Source of truth — kept in sync with what we've sent to the typing queue.
    private var actuallyInDocument = ""

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

        // If started from popover, close it and return focus to the previous app
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
        actuallyInDocument = ""

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appState.targetAppName = frontApp.localizedName
        }

        appState.isDictating = true
        Logger.app.info("Dictation started — \(self.appState.selectedProfile.name) / \(self.appState.selectedFormat.name)")

        let hints = appState.allVocabularyHints
        let stream = transcriptionService.startTranscription(vocabularyHints: hints)

        transcriptionTask = Task { [weak self] in
            for await update in stream {
                guard let self else { break }
                // Don't break on !isDictating — we may still receive the final
                // transcription from stopTranscription() after isDictating is false.

                switch update {
                case .partial(let text), .final_(let text):
                    self.appState.liveTranscript = text
                    self.commitText(text)

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

        appState.isDictating = false

        // stopTranscription will yield one FINAL transcript before finishing the stream.
        // We need to wait for that final yield to be processed before polishing.
        // Run stopTranscription off the main thread (it blocks for up to 5s).
        let service = transcriptionService
        Task.detached { [weak self] in
            service.stopTranscription()

            // Now the stream has finished. Wait a moment for any pending UI updates.
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

            await MainActor.run {
                self?.transcriptionTask?.cancel()
                self?.transcriptionTask = nil
                self?.finalizeAndPolish()
            }
        }
    }

    private func finalizeAndPolish() {
        Logger.app.info("Finalizing dictation — \(self.actuallyInDocument.count) chars in document")

        let rawText = actuallyInDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            Logger.app.info("No text was transcribed")
            return
        }

        // Wait for any in-flight typing to complete
        let charCount = actuallyInDocument.count
        let axService = accessibilityService
        Task.detached { [weak self] in
            axService.drainTypingQueue()
            await MainActor.run {
                self?.polishAndReplace(rawText: rawText, characterCount: charCount)
            }
        }
    }

    // MARK: - Commit (Diff + Type)

    /// Commits a stable transcript to the document.
    /// Computes a real string diff against what we've already typed,
    /// backspaces to the divergence point, and types the corrected text.
    ///
    /// This handles ALL recognizer revision cases:
    /// - Capitalization changes ("hello" → "Hello")
    /// - Punctuation insertion ("Hello world" → "Hello, world")
    /// - Word corrections ("their" → "there")
    /// - New text appended ("Hello" → "Hello world")
    private func commitText(_ stableText: String) {
        guard stableText != actuallyInDocument else { return }

        let commonLen = commonPrefixLength(actuallyInDocument, stableText)
        let charsToDelete = actuallyInDocument.count - commonLen
        let newSuffix = String(stableText.dropFirst(commonLen))

        Logger.app.debug("Commit: common=\(commonLen), del=\(charsToDelete), type=\(newSuffix.count)")

        if charsToDelete > 0 {
            accessibilityService.enqueueBackspaces(charsToDelete)
        }
        if !newSuffix.isEmpty {
            accessibilityService.enqueueTyping(newSuffix)
        }

        actuallyInDocument = stableText
    }

    private func commonPrefixLength(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let minLen = min(aChars.count, bChars.count)
        for i in 0..<minLen {
            if aChars[i] != bChars[i] {
                return i
            }
        }
        return minLen
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
