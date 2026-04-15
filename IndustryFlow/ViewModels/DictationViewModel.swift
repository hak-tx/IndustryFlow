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

    // MARK: - Commit (Ratchet — never deletes user's text)

    /// Commits a stable transcript to the document using a RATCHET approach:
    /// text can only grow, never shrink. We never delete content the recognizer
    /// previously gave us, even if a later transcription cycle returns shorter
    /// text (which happens when SFSpeechRecognizer drops earlier audio after
    /// a long pause).
    ///
    /// Three cases:
    /// 1. STRONG PREFIX MATCH (>50% of typed text matches): Normal refinement.
    ///    Backspace divergent suffix, type new content. Handles capitalization,
    ///    punctuation, and word correction revisions.
    ///
    /// 2. NEW TEXT ALREADY CONTAINED: Recognizer returned a subset of what we
    ///    have. No-op.
    ///
    /// 3. WEAK MATCH (recognizer dropped earlier text): Find any overlap
    ///    between the END of what we typed and the START of new text.
    ///    Append only the non-overlapping suffix.
    private func commitText(_ stableText: String) {
        guard !stableText.isEmpty else { return }
        guard stableText != actuallyInDocument else { return }

        // Empty document — just type everything
        if actuallyInDocument.isEmpty {
            accessibilityService.enqueueTyping(stableText)
            actuallyInDocument = stableText
            return
        }

        let commonLen = commonPrefixLength(actuallyInDocument, stableText)
        let prefixThreshold = max(actuallyInDocument.count / 2, 8)

        // CASE 1: Strong prefix match → safe to refine (delete divergent suffix, retype)
        if commonLen >= prefixThreshold {
            let charsToDelete = actuallyInDocument.count - commonLen
            let newSuffix = String(stableText.dropFirst(commonLen))

            if charsToDelete > 0 {
                accessibilityService.enqueueBackspaces(charsToDelete)
            }
            if !newSuffix.isEmpty {
                accessibilityService.enqueueTyping(newSuffix)
            }
            actuallyInDocument = stableText
            Logger.app.debug("Refine: common=\(commonLen), del=\(charsToDelete), type=\(newSuffix.count)")
            return
        }

        // CASE 2: Recognizer's text is already contained in our document — no-op
        if actuallyInDocument.contains(stableText) {
            Logger.app.debug("Skip: stableText already in document")
            return
        }

        // CASE 3: Weak match — recognizer dropped earlier text. Find suffix/prefix
        // overlap and append only the new content.
        let overlapLen = suffixPrefixOverlap(suffixOf: actuallyInDocument, prefixOf: stableText)
        let toAppend = String(stableText.dropFirst(overlapLen))

        guard !toAppend.isEmpty else {
            Logger.app.debug("Skip: full overlap, nothing new to append")
            return
        }

        // Add a space separator if needed
        let needsSpace = !actuallyInDocument.hasSuffix(" ")
            && !toAppend.hasPrefix(" ")
            && !".,;:!?".contains(toAppend.first ?? " ")
        let finalAppend = needsSpace ? " " + toAppend : toAppend

        accessibilityService.enqueueTyping(finalAppend)
        actuallyInDocument += finalAppend

        Logger.app.info("Append (recognizer dropped earlier text): overlap=\(overlapLen), appended=\(finalAppend.count) chars")
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

    /// Finds the longest length L such that the last L chars of `suffixOf`
    /// equal the first L chars of `prefixOf`. Used to detect overlap when
    /// the recognizer's new transcript starts with words we already typed.
    private func suffixPrefixOverlap(suffixOf a: String, prefixOf b: String) -> Int {
        let maxLen = min(a.count, b.count)
        guard maxLen > 0 else { return 0 }

        let aChars = Array(a)
        let bChars = Array(b)

        // Try from longest possible overlap down to 1
        for len in (1...maxLen).reversed() {
            var matches = true
            for i in 0..<len {
                if aChars[aChars.count - len + i] != bChars[i] {
                    matches = false
                    break
                }
            }
            if matches {
                return len
            }
        }
        return 0
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
