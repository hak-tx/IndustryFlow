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
        longestTranscript = ""

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

    /// The longest transcript we've ever received from any cycle.
    /// This is the canonical state — the document mirrors this.
    /// Recognizer cycles can return shorter/different text intermittently,
    /// but we always keep the longest version we've ever seen.
    private var longestTranscript = ""

    // MARK: - Commit (Ratchet — never deletes user's text)

    /// Updates the canonical transcript and syncs the document to it.
    ///
    /// Strategy:
    /// 1. Compute case-insensitive overlap between current canonical and new
    /// 2. If new extends current strongly → update canonical to new
    /// 3. If new is contained in current (case-insensitively) → no-op
    /// 4. If new diverges → find suffix/prefix overlap, merge into canonical
    /// 5. Sync document to canonical via diff (case-sensitive — preserves
    ///    capitalization the recognizer chose)
    private func commitText(_ stableText: String) {
        guard !stableText.isEmpty else { return }

        // Update the canonical longestTranscript using case-insensitive logic
        updateLongestTranscript(with: stableText)

        // Sync the document to match the canonical
        syncDocumentToCanonical()
    }

    private func updateLongestTranscript(with newText: String) {
        // Case 1: Empty canonical → adopt
        if longestTranscript.isEmpty {
            longestTranscript = newText
            return
        }

        // Case 2: Identical (ignoring case) → keep new (more recent capitalization)
        if longestTranscript.lowercased() == newText.lowercased() {
            // Prefer the longer one if they differ in length (e.g. trailing space)
            if newText.count >= longestTranscript.count {
                longestTranscript = newText
            }
            return
        }

        // Case 3: New text is contained in canonical (case-insensitive) → no-op
        if longestTranscript.lowercased().contains(newText.lowercased()) {
            return
        }

        // Case 4: Canonical is contained in new text (case-insensitive) → adopt new
        // (this is the normal "extension" case — recognizer added more words)
        if newText.lowercased().contains(longestTranscript.lowercased()) {
            longestTranscript = newText
            return
        }

        // Case 5: Strong shared prefix (case-insensitive) → adopt new (it's a refinement)
        let commonLen = caseInsensitivePrefixLength(longestTranscript, newText)
        let prefixRatio = Double(commonLen) / Double(longestTranscript.count)

        if prefixRatio > 0.5 {
            longestTranscript = newText
            return
        }

        // Case 6: Weak prefix match — recognizer dropped earlier text or
        // we have a continuation. Find the overlap between END of canonical
        // and START of new text (case-insensitive).
        let overlap = caseInsensitiveSuffixPrefixOverlap(suffixOf: longestTranscript, prefixOf: newText)
        let toAppend = String(newText.dropFirst(overlap))

        guard !toAppend.isEmpty else { return }

        let needsSpace = !longestTranscript.hasSuffix(" ")
            && !toAppend.hasPrefix(" ")
            && !".,;:!?".contains(toAppend.first ?? " ")
        let separator = needsSpace ? " " : ""
        longestTranscript += separator + toAppend

        Logger.app.debug("Append: overlap=\(overlap), appended \(toAppend.count) chars")
    }

    /// Diffs the document against longestTranscript and types the changes.
    /// Uses case-sensitive prefix matching (we want exact characters in the document).
    private func syncDocumentToCanonical() {
        guard longestTranscript != actuallyInDocument else { return }

        if actuallyInDocument.isEmpty {
            accessibilityService.enqueueTyping(longestTranscript)
            actuallyInDocument = longestTranscript
            return
        }

        let common = exactPrefixLength(actuallyInDocument, longestTranscript)
        let charsToDelete = actuallyInDocument.count - common
        let suffix = String(longestTranscript.dropFirst(common))

        // Safety check: never backspace more than half the document at once.
        // This prevents catastrophic deletion if logic somehow goes wrong.
        let maxSafeDelete = max(actuallyInDocument.count / 2, 20)
        if charsToDelete > maxSafeDelete {
            Logger.app.warning("Refusing to delete \(charsToDelete) chars (max \(maxSafeDelete)) — appending instead")
            // Just append the new content with a separator
            let needsSpace = !actuallyInDocument.hasSuffix(" ") && !suffix.hasPrefix(" ")
            let toType = (needsSpace ? " " : "") + suffix
            accessibilityService.enqueueTyping(toType)
            actuallyInDocument += toType
            return
        }

        if charsToDelete > 0 {
            accessibilityService.enqueueBackspaces(charsToDelete)
        }
        if !suffix.isEmpty {
            accessibilityService.enqueueTyping(suffix)
        }
        actuallyInDocument = longestTranscript
    }

    // MARK: - String Comparison Helpers

    private func caseInsensitivePrefixLength(_ a: String, _ b: String) -> Int {
        let aL = Array(a.lowercased())
        let bL = Array(b.lowercased())
        let minLen = min(aL.count, bL.count)
        for i in 0..<minLen {
            if aL[i] != bL[i] { return i }
        }
        return minLen
    }

    private func exactPrefixLength(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let minLen = min(aChars.count, bChars.count)
        for i in 0..<minLen {
            if aChars[i] != bChars[i] { return i }
        }
        return minLen
    }

    private func caseInsensitiveSuffixPrefixOverlap(suffixOf a: String, prefixOf b: String) -> Int {
        let aL = Array(a.lowercased())
        let bL = Array(b.lowercased())
        let maxLen = min(aL.count, bL.count)
        guard maxLen > 0 else { return 0 }

        // Try longest overlap first
        for len in (1...maxLen).reversed() {
            var matches = true
            for i in 0..<len {
                if aL[aL.count - len + i] != bL[i] {
                    matches = false
                    break
                }
            }
            if matches { return len }
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
