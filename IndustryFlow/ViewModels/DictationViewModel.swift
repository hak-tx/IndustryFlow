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
        guard permissionsService.allPermissionsGranted else {
            appState.errorMessage = "Please grant all required permissions before dictating."
            appState.showOnboarding = true
            return
        }

        appState.clearError()
        appState.liveTranscript = ""
        appState.polishedText = nil

        // Capture the target app and focused element BEFORE we do anything
        // that might steal focus
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appState.targetAppPID = frontApp.processIdentifier
            appState.targetAppName = frontApp.localizedName
            capturedElement = accessibilityService.getFocusedElement(forPID: frontApp.processIdentifier)
        }

        let session = TranscriptionSession(profile: appState.selectedProfile)
        appState.lastSession = session
        appState.isDictating = true

        Logger.app.info("Starting dictation with profile: \(self.appState.selectedProfile.name)")

        // Start transcription stream
        let hints = appState.selectedProfile.vocabularyHints
        let stream = transcriptionService.startTranscription(vocabularyHints: hints)

        transcriptionTask = Task { [weak self] in
            for await update in stream {
                guard let self, self.appState.isDictating else { break }

                switch update {
                case .partial(let text):
                    self.appState.liveTranscript = text
                    self.appState.lastSession?.rawTranscript = text

                case .final_(let text):
                    self.appState.liveTranscript = text
                    self.appState.lastSession?.rawTranscript = text

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

        let rawText = appState.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            Logger.app.info("No text was transcribed")
            appState.lastSession?.status = .completed
            return
        }

        // Insert the raw transcript into the target app immediately
        insertTextIntoTargetApp(rawText)

        // Then polish it
        polishTranscript(rawText)
    }

    // MARK: - Text Insertion

    private func insertTextIntoTargetApp(_ text: String) {
        // Re-acquire the focused element in the target app
        if let pid = appState.targetAppPID {
            // Activate the target app first
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
            }

            // Small delay for focus to settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                let element = self.capturedElement
                    ?? self.accessibilityService.getFocusedElement(forPID: pid)

                if let element {
                    let success = self.accessibilityService.insertText(text, into: element)
                    if success {
                        Logger.app.info("Text inserted into target app")
                    } else {
                        Logger.app.warning("Failed to insert text via accessibility, trying pasteboard")
                    }
                } else {
                    Logger.app.warning("No focused element found, text available in clipboard")
                    // As final fallback, put it on the pasteboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    self.appState.errorMessage = "Could not find cursor. Text copied to clipboard — press Cmd+V to paste."
                }
            }
        }
    }

    // MARK: - AI Polishing

    private func polishTranscript(_ rawText: String) {
        appState.isPolishing = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let result = try await self.polishingService.polish(
                    text: rawText,
                    profile: self.appState.selectedProfile
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

        // Activate the target app
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let element = self.capturedElement
                ?? self.accessibilityService.getFocusedElement(forPID: pid)

            if let element {
                let success = self.accessibilityService.replaceText(
                    original: original,
                    replacement: polished,
                    in: element
                )
                if success {
                    Logger.app.info("Replaced raw text with polished version")
                }
            }
        }
    }
}
