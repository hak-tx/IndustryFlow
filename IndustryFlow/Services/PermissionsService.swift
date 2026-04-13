import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit
import os

@Observable
final class PermissionsService {

    var microphoneGranted: Bool = false
    var speechRecognitionGranted: Bool = false
    var accessibilityGranted: Bool = false

    var allPermissionsGranted: Bool {
        microphoneGranted && speechRecognitionGranted && accessibilityGranted
    }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        microphoneGranted = checkMicrophone()
        speechRecognitionGranted = checkSpeechRecognition()
        accessibilityGranted = checkAccessibility()

        Logger.app.info("""
        Permissions status — Mic: \(self.microphoneGranted), \
        Speech: \(self.speechRecognitionGranted), \
        Accessibility: \(self.accessibilityGranted)
        """)
    }

    // MARK: - Microphone

    private func checkMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestMicrophone() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        await MainActor.run { microphoneGranted = granted }
        return granted
    }

    // MARK: - Speech Recognition

    private func checkSpeechRecognition() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestSpeechRecognition() async -> Bool {
        let status = await SpeechTranscriptionService.requestAuthorization()
        let granted = status == .authorized
        await MainActor.run { speechRecognitionGranted = granted }
        return granted
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        AccessibilityService.requestAccessibilityPermission()

        // Start polling for accessibility access since it requires user action in System Settings
        pollAccessibilityStatus()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func pollAccessibilityStatus() {
        // Poll every second for up to 60 seconds
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                if AXIsProcessTrusted() {
                    accessibilityGranted = true
                    Logger.app.info("Accessibility permission granted")
                    return
                }
            }
        }
    }
}
