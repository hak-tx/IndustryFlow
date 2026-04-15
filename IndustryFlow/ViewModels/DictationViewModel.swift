import Foundation
import AppKit
import AudioToolbox
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

    // System sound IDs for start/stop dictation cues
    private static let startSoundID: SystemSoundID = {
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        AudioServicesCreateSystemSoundID(url as CFURL, &id)
        return id
    }()
    private static let stopSoundID: SystemSoundID = {
        var id: SystemSoundID = 0
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
        AudioServicesCreateSystemSoundID(url as CFURL, &id)
        return id
    }()

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

        // Play "ready" sound BEFORE starting audio capture.
        // This way:
        // 1. The Tink sound is NOT captured by the mic (would confuse the recognizer)
        // 2. The user hears the cue and knows to wait briefly
        // 3. By the time audio capture begins, the system is ready
        AudioServicesPlaySystemSound(Self.startSoundID)

        let hints = appState.allVocabularyHints

        // Delay audio capture start by ~180ms so the Tink finishes playing and
        // doesn't end up in the recognition buffer. The user is naturally waiting
        // anyway because they hear the Tink.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000) // 180ms

            await MainActor.run {
                guard let self, self.appState.isDictating else { return }
                let stream = self.transcriptionService.startTranscription(vocabularyHints: hints)
                self.consumeTranscriptionStream(stream)
            }
        }
    }

    private func consumeTranscriptionStream(_ stream: AsyncStream<TranscriptionUpdate>) {
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

        // Play "stop" sound so user knows dictation has ended
        AudioServicesPlaySystemSound(Self.stopSoundID)

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

        // Case 5: Strong shared prefix (case-insensitive) → adopt new (refinement)
        let commonLen = caseInsensitivePrefixLength(longestTranscript, newText)
        let prefixRatio = Double(commonLen) / Double(longestTranscript.count)

        if prefixRatio > 0.5 {
            longestTranscript = newText
            return
        }

        // Case 5.5: FUZZY CONTAINMENT — if new text has MOST of canonical's words
        // AND is at least as long, it's a refined version of the same content
        // (recognizer just changed some words like "200"→"240"). Adopt new.
        // This catches the case where the recognizer revises early content.
        if isRefinementOf(canonical: longestTranscript, new: newText) {
            longestTranscript = newText
            Logger.app.debug("Adopting fuzzy refinement (most words match, new is longer)")
            return
        }

        // Case 6: Weak prefix match — recognizer dropped earlier text or
        // we have a continuation. Use TOKEN-LEVEL overlap detection: find
        // the longest sequence of words at the end of canonical that matches
        // the start of newText. If found, REPLACE canonical from that point
        // with the full newText (it has corrections to those words).
        if let mergedText = mergeWithTokenOverlap(canonical: longestTranscript, new: newText) {
            longestTranscript = mergedText
            return
        }

        // No useful overlap found — append with space separator.
        let needsSpace = !longestTranscript.hasSuffix(" ")
            && !newText.hasPrefix(" ")
            && !".,;:!?".contains(newText.first ?? " ")
        let separator = needsSpace ? " " : ""
        longestTranscript += separator + newText
        Logger.app.debug("Append (no overlap): \(newText.count) chars")
    }

    /// Token-level overlap merge. Looks for the longest sequence of words
    /// that overlap between END of canonical and START of new text. If found,
    /// returns canonical's prefix (everything before the overlap) plus the
    /// full new text (which contains updated/corrected words).
    ///
    /// This handles cases like:
    ///   canonical: "20A 240V 2P breakers Using 2-#12G and 1k"
    ///   new:       "Using 2-#12G and 1-#10G"
    ///   3-word overlap: "Using 2-#12G and"
    ///   merged:    "20A 240V 2P breakers Using 2-#12G and 1-#10G"
    ///
    /// Words are compared case-insensitively. Returns nil if no overlap.
    private func mergeWithTokenOverlap(canonical: String, new: String) -> String? {
        let canonicalTokens = tokenize(canonical)
        let newTokens = tokenize(new)
        let maxOverlap = min(canonicalTokens.count, newTokens.count)
        guard maxOverlap > 0 else { return nil }

        // Try longest possible overlap first
        for k in (1...maxOverlap).reversed() {
            let canonicalSuffix = canonicalTokens.suffix(k).map { $0.lowercased() }
            let newPrefix = newTokens.prefix(k).map { $0.lowercased() }
            if canonicalSuffix == newPrefix {
                // Found k-word overlap. Take canonical tokens before overlap, append new text.
                let prefixTokens = canonicalTokens.prefix(canonicalTokens.count - k)
                let prefix = prefixTokens.joined(separator: " ")
                let separator = prefix.isEmpty ? "" : " "
                Logger.app.debug("Token overlap merge: \(k) words")
                return prefix + separator + new
            }
        }
        return nil
    }

    private func tokenize(_ s: String) -> [String] {
        return s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Returns true if `new` appears to be a refined version of `canonical`:
    /// most of canonical's words appear in new (case-insensitive), AND new
    /// is at least roughly the same length as canonical.
    ///
    /// This catches cases where the recognizer revises a word mid-sentence
    /// (e.g. "200" → "240") which breaks both prefix matching and exact
    /// token overlap, but the new text is clearly the same content + extension.
    private func isRefinementOf(canonical: String, new: String) -> Bool {
        let canonicalTokens = tokenize(canonical)
        let newTokens = tokenize(new)

        // Need at least a few words in canonical to make this judgment safely
        guard canonicalTokens.count >= 3 else { return false }

        // New must be at least 90% of canonical's word count to count as refinement.
        // Otherwise it's likely a partial transcript (recognizer dropped earlier audio).
        guard Double(newTokens.count) >= Double(canonicalTokens.count) * 0.9 else {
            return false
        }

        // Count how many of canonical's words appear in new (case-insensitive)
        let newSet = Set(newTokens.map { $0.lowercased() })
        let matches = canonicalTokens.filter { newSet.contains($0.lowercased()) }.count
        let matchRatio = Double(matches) / Double(canonicalTokens.count)

        // 60% of canonical's words must be in new for it to count as refinement.
        // This threshold is intentionally conservative to avoid false positives
        // that would replace legitimate canonical content.
        return matchRatio >= 0.6
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

        // Safety check uses NET data loss, not raw deletion count.
        // If we delete 24 chars and type 24 new chars, no data is lost — safe.
        // We only block if we'd be deleting significantly MORE than we type
        // (which would be true catastrophic loss).
        let netLoss = max(0, charsToDelete - suffix.count)
        let lossThreshold = max(actuallyInDocument.count / 2, 50)

        if netLoss > lossThreshold {
            Logger.app.warning("""
                Refusing replacement: would lose \(netLoss) chars (delete \(charsToDelete), \
                type \(suffix.count)). Appending instead.
                """)
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
