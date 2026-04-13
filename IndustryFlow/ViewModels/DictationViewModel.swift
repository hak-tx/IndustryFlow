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
    private var capturedElement: AXUIElement?
    private var targetIsElectronApp = false

    // Live insertion tracking
    private var previouslyInsertedText = ""
    private var insertionStartPosition = -1
    private var useAXInsertion = true

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
        // Refresh permission status before checking
        permissionsService.refreshStatus()

        if !permissionsService.allPermissionsGranted {
            var missing: [String] = []
            if !permissionsService.microphoneGranted { missing.append("Microphone") }
            if !permissionsService.speechRecognitionGranted { missing.append("Speech Recognition") }
            if !permissionsService.accessibilityGranted { missing.append("Accessibility") }
            appState.errorMessage = "Missing permissions: \(missing.joined(separator: ", ")). Grant them above or in Settings."
            return
        }

        appState.clearError()
        appState.liveTranscript = ""
        appState.polishedText = nil

        // Reset live insertion state
        previouslyInsertedText = ""
        insertionStartPosition = -1
        useAXInsertion = true

        // Capture the target app and focused element BEFORE anything.
        // Focus must stay in the target app — we never activate IndustryFlow.
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appState.targetAppPID = frontApp.processIdentifier
            appState.targetAppName = frontApp.localizedName
            targetIsElectronApp = AccessibilityService.isElectronApp(frontApp)
            capturedElement = accessibilityService.getFocusedElement(forPID: frontApp.processIdentifier)

            if targetIsElectronApp {
                useAXInsertion = false
                Logger.app.info("Target is Electron app — using backspace+paste for live insertion")
            }

            // Record the cursor position for AX range-based insertion
            if useAXInsertion, let element = capturedElement {
                insertionStartPosition = accessibilityService.getCursorPosition(in: element)
                Logger.app.info("Captured cursor position: \(self.insertionStartPosition)")
            }
        }

        let session = TranscriptionSession(profile: appState.selectedProfile)
        appState.lastSession = session
        appState.isDictating = true

        Logger.app.info("Starting dictation — profile: \(self.appState.selectedProfile.name), format: \(self.appState.selectedFormat.name)")

        // Start transcription with combined vocabulary hints
        // (industry profile terms + custom company glossary terms)
        let hints = appState.allVocabularyHints
        let stream = transcriptionService.startTranscription(vocabularyHints: hints)

        transcriptionTask = Task { [weak self] in
            for await update in stream {
                guard let self, self.appState.isDictating else { break }

                switch update {
                case .partial(let text):
                    // Update app state (for popover display if user opens it)
                    self.appState.liveTranscript = text
                    self.appState.lastSession?.rawTranscript = text

                    // PRIMARY: Stream text live into the target app
                    self.liveInsertPartialResult(text)

                case .final_(let text):
                    self.appState.liveTranscript = text
                    self.appState.lastSession?.rawTranscript = text

                    // Insert the finalized segment
                    self.liveInsertPartialResult(text)

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

        Logger.app.info("Stopping dictation")

        transcriptionService.stopTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        appState.isDictating = false
        appState.lastSession?.status = .processing

        let rawText = previouslyInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            Logger.app.info("No text was transcribed")
            appState.lastSession?.status = .completed
            return
        }

        // Raw text is already in the target app (inserted live during dictation).
        // Now polish it and replace.
        polishTranscript(rawText)
    }

    // MARK: - Live Text Insertion

    /// Inserts or updates partial transcription results in the target app in real-time.
    /// Called on every `.partial` and `.final_` update from the speech recognizer.
    ///
    /// Strategy for AX-compatible apps (most native apps):
    ///   - First partial: insert at cursor, record the start position
    ///   - Subsequent partials: replace the range [start..start+prevLength] with new text
    ///
    /// Strategy for Electron apps (no AX):
    ///   - Simulate backspaces to delete previous text, then paste new text
    private func liveInsertPartialResult(_ newText: String) {
        guard let pid = appState.targetAppPID else { return }

        if useAXInsertion {
            liveInsertViaAX(newText, pid: pid)
        } else {
            liveInsertViaBackspaceAndPaste(newText)
        }
    }

    /// AX-based live insertion: directly manipulate the text field's value.
    /// This is instant, invisible, and doesn't disrupt the user.
    private func liveInsertViaAX(_ newText: String, pid: pid_t) {
        let element = capturedElement
            ?? accessibilityService.getFocusedElement(forPID: pid)

        guard let element else {
            Logger.app.warning("Lost focused element during live insertion")
            return
        }

        if previouslyInsertedText.isEmpty && insertionStartPosition >= 0 {
            // First insertion: insert at the captured cursor position
            let result = accessibilityService.replaceRange(
                in: element,
                start: insertionStartPosition,
                length: 0,
                with: newText
            )
            if result >= 0 {
                previouslyInsertedText = newText
            }
        } else if insertionStartPosition >= 0 {
            // Subsequent insertions: replace the range we previously inserted
            let result = accessibilityService.replaceRange(
                in: element,
                start: insertionStartPosition,
                length: previouslyInsertedText.count,
                with: newText
            )
            if result >= 0 {
                previouslyInsertedText = newText
            }
        } else {
            // Fallback: couldn't get cursor position, switch to backspace method
            Logger.app.info("No cursor position — falling back to backspace insertion")
            useAXInsertion = false
            liveInsertViaBackspaceAndPaste(newText)
        }
    }

    /// Electron/fallback live insertion: delete previous text with backspaces, paste new text.
    /// Visually noisier than AX but works universally.
    private func liveInsertViaBackspaceAndPaste(_ newText: String) {
        // Delete what we previously inserted
        if !previouslyInsertedText.isEmpty {
            accessibilityService.simulateBackspaces(count: previouslyInsertedText.count)
            usleep(10_000) // 10ms for backspaces to register
        }

        // Paste the new text
        _ = accessibilityService.insertViaPasteboard(newText)
        previouslyInsertedText = newText
    }

    // MARK: - AI Polishing

    private func polishTranscript(_ rawText: String) {
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
                    self.appState.lastSession?.polishedText = result.polished
                    self.appState.lastSession?.status = .completed
                    self.appState.isPolishing = false

                    // Replace the raw text with polished text in the target app
                    if result.polished != rawText {
                        self.replaceWithPolishedText(original: rawText, polished: result.polished)
                    }

                    Logger.app.info("Polishing complete")
                }
            } catch {
                await MainActor.run {
                    self.appState.errorMessage = error.localizedDescription
                    self.appState.lastSession?.status = .failed(error.localizedDescription)
                    self.appState.isPolishing = false
                    Logger.app.error("Polishing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func replaceWithPolishedText(original: String, polished: String) {
        guard let pid = appState.targetAppPID else { return }

        if useAXInsertion, insertionStartPosition >= 0 {
            // Use AX range replacement — swap the raw text with polished in-place
            let element = capturedElement
                ?? accessibilityService.getFocusedElement(forPID: pid)

            if let element {
                let result = accessibilityService.replaceRange(
                    in: element,
                    start: insertionStartPosition,
                    length: original.count,
                    with: polished
                )
                if result >= 0 {
                    Logger.app.info("Replaced raw text with polished version via AX")
                    previouslyInsertedText = polished
                    return
                }
            }
        }

        // Fallback: try string-based AX replacement
        if let element = capturedElement ?? accessibilityService.getFocusedElement(forPID: pid) {
            let success = accessibilityService.replaceText(
                original: original,
                replacement: polished,
                in: element,
                targetPID: pid
            )
            if success {
                Logger.app.info("Replaced raw text with polished version")
                return
            }
        }

        // Final fallback: copy polished text to clipboard
        Logger.app.info("AX replacement failed — polished text copied to clipboard")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(polished, forType: .string)
        appState.errorMessage = "Polished text copied to clipboard. Press Cmd+V to replace."
    }
}
