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

        // Capture the target app and focused element BEFORE we do anything
        // that might steal focus
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            appState.targetAppPID = frontApp.processIdentifier
            appState.targetAppName = frontApp.localizedName
            targetIsElectronApp = AccessibilityService.isElectronApp(frontApp)
            capturedElement = accessibilityService.getFocusedElement(forPID: frontApp.processIdentifier)

            if targetIsElectronApp {
                Logger.app.info("Target is Electron app — will use pasteboard insertion")
            }
        }

        let session = TranscriptionSession(profile: appState.selectedProfile)
        appState.lastSession = session
        appState.isDictating = true

        Logger.app.info("Starting dictation with profile: \(self.appState.selectedProfile.name)")

        // Start transcription stream with combined vocabulary hints
        // (industry profile terms + custom company glossary terms)
        let hints = appState.allVocabularyHints
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
        guard let pid = appState.targetAppPID else { return }

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
                let success = self.accessibilityService.insertText(
                    text,
                    into: element,
                    targetPID: pid
                )
                if success {
                    Logger.app.info("Text inserted into target app")
                }
            } else {
                // No focused element — use pasteboard insertion directly
                Logger.app.info("No focused element — inserting via pasteboard")
                _ = self.accessibilityService.insertViaPasteboard(text)
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
                    profile: self.appState.selectedProfile,
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
                    in: element,
                    targetPID: pid
                )
                if success {
                    Logger.app.info("Replaced raw text with polished version")
                } else {
                    // AX replacement failed (Electron app, or user moved cursor).
                    // Copy polished text to clipboard so user can paste it manually.
                    Logger.app.info("AX replacement failed — polished text copied to clipboard")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(polished, forType: .string)
                    self.appState.errorMessage = "Polished text copied to clipboard. Press Cmd+V to replace your dictation."
                }
            }
        }
    }
}
