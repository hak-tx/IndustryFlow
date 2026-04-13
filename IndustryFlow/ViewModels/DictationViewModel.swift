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
    /// This is the source of truth for what the user sees.
    private var actuallyInDocument = ""

    /// Most recent text from the recognizer (may be mid-revision).
    private var latestRecognizerText = ""

    /// Debounce timer — waits for recognizer to stabilize before typing.
    private var debounceTask: Task<Void, Never>?

    /// How long to wait for the recognizer to stop revising before we commit text.
    /// 250ms is imperceptible to the user but enough for the recognizer to settle.
    private let debounceInterval: UInt64 = 250_000_000 // 250ms in nanoseconds

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

        // Reset all state
        actuallyInDocument = ""
        latestRecognizerText = ""
        debounceTask?.cancel()
        debounceTask = nil

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
                    self.onRecognizerUpdate(text)

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

        transcriptionService.stopTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        appState.isDictating = false

        // Commit any pending text immediately (don't wait for debounce)
        debounceTask?.cancel()
        debounceTask = nil
        if latestRecognizerText != actuallyInDocument {
            commitText(latestRecognizerText)
        }

        Logger.app.info("Dictation stopped — \(self.actuallyInDocument.count) characters in document")

        // Wait for typing queue to finish, then polish
        let rawText = actuallyInDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        let charCount = actuallyInDocument.count
        guard !rawText.isEmpty else {
            Logger.app.info("No text was transcribed")
            return
        }

        let service = accessibilityService
        Task.detached { [weak self] in
            service.drainTypingQueue()
            await MainActor.run {
                self?.polishAndReplace(rawText: rawText, characterCount: charCount)
            }
        }
    }

    // MARK: - Debounce + Diff

    /// Called on every partial/final from the recognizer.
    /// Does NOT type immediately. Stores the text and resets a 250ms timer.
    /// When the timer fires (text has been stable for 250ms), commitText runs.
    private func onRecognizerUpdate(_ text: String) {
        latestRecognizerText = text

        // Reset the debounce timer
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceInterval ?? 250_000_000)
            guard let self, !Task.isCancelled, self.appState.isDictating else { return }
            self.commitText(self.latestRecognizerText)
        }
    }

    /// Commits stable text to the document. Computes a proper diff against
    /// what's already typed, backspaces to the divergence point, and types
    /// the corrected text from there.
    ///
    /// This handles ALL recognizer revision cases correctly:
    /// - Capitalization changes ("hello" → "Hello")
    /// - Punctuation insertion ("Hello world" → "Hello, world")
    /// - Word corrections ("their" → "there")
    /// - New text appended ("Hello" → "Hello world")
    private func commitText(_ stableText: String) {
        guard stableText != actuallyInDocument else { return }

        // Find the longest common prefix (case-sensitive, exact match)
        let commonLen = commonPrefixLength(actuallyInDocument, stableText)

        // How many characters to delete from the end of what's in the document
        let charsToDelete = actuallyInDocument.count - commonLen

        // What to type after the common prefix
        let newSuffix = String(stableText.dropFirst(commonLen))

        Logger.app.debug("""
        Commit: common=\(commonLen), delete=\(charsToDelete), \
        type=\(newSuffix.count) chars
        """)

        // Backspace the divergent portion, then type the new text
        if charsToDelete > 0 {
            accessibilityService.enqueueBackspaces(charsToDelete)
        }
        if !newSuffix.isEmpty {
            accessibilityService.enqueueTyping(newSuffix)
        }

        actuallyInDocument = stableText
    }

    /// Returns the length of the longest common prefix between two strings.
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
