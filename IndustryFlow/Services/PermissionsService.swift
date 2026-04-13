import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit
import os

/// Centralized permission manager with continuous monitoring.
///
/// Production features:
/// - Single source of truth for all permission states
/// - Continuous accessibility monitoring (not one-shot polling)
/// - Reactive notifications when permissions change
/// - Cancellable operations — no fire-and-forget polling
@Observable
final class PermissionsService {

    // MARK: - Permission State

    var microphoneGranted: Bool = false
    var speechRecognitionGranted: Bool = false
    var accessibilityGranted: Bool = false

    var allPermissionsGranted: Bool {
        microphoneGranted && speechRecognitionGranted && accessibilityGranted
    }

    /// A permission that was previously granted but has been revoked.
    var revokedPermission: String?

    // MARK: - Private

    private var accessibilityMonitorTimer: Timer?
    private var accessibilityCheckTask: Task<Void, Never>?
    private var isMonitoringAccessibility = false

    init() {
        refreshStatus()
        startContinuousAccessibilityMonitoring()
    }

    deinit {
        stopAllMonitoring()
    }

    // MARK: - Status Refresh

    func refreshStatus() {
        let prevMic = microphoneGranted
        let prevSpeech = speechRecognitionGranted
        let prevAx = accessibilityGranted

        microphoneGranted = checkMicrophone()
        speechRecognitionGranted = checkSpeechRecognition()
        accessibilityGranted = checkAccessibility()

        // Detect revocations
        if prevMic && !microphoneGranted {
            revokedPermission = "Microphone"
            Logger.app.error("Microphone permission was revoked")
        } else if prevSpeech && !speechRecognitionGranted {
            revokedPermission = "Speech Recognition"
            Logger.app.error("Speech Recognition permission was revoked")
        } else if prevAx && !accessibilityGranted {
            revokedPermission = "Accessibility"
            Logger.app.error("Accessibility permission was revoked")
            NotificationCenter.default.post(name: .hotkeyPermissionLost, object: nil)
        }

        // Detect restorations
        if !prevAx && accessibilityGranted {
            revokedPermission = nil
            Logger.app.info("Accessibility permission restored")
            NotificationCenter.default.post(name: .hotkeyPermissionRestored, object: nil)
        }

        Logger.app.info("""
        Permissions — Mic: \(self.microphoneGranted), \
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
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        let granted = status == .authorized
        await MainActor.run { speechRecognitionGranted = granted }
        return granted
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Opens the System Settings prompt for accessibility access.
    func requestAccessibility() {
        AccessibilityService.requestAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Continuous Accessibility Monitoring

    /// Monitors accessibility status continuously for the lifetime of the app.
    /// Uses a Timer on the main run loop — lightweight, cancellable, and reliable.
    ///
    /// Checks every 2 seconds when accessibility is NOT granted (fast feedback during setup),
    /// and every 10 seconds once granted (light touch to detect revocation).
    private func startContinuousAccessibilityMonitoring() {
        guard !isMonitoringAccessibility else { return }
        isMonitoringAccessibility = true

        scheduleAccessibilityCheck()
    }

    private func scheduleAccessibilityCheck() {
        accessibilityMonitorTimer?.invalidate()

        // Check faster when not yet granted (during onboarding)
        let interval: TimeInterval = accessibilityGranted ? 10.0 : 2.0

        accessibilityMonitorTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }

            let wasGranted = self.accessibilityGranted
            let nowGranted = AXIsProcessTrusted()

            if wasGranted != nowGranted {
                self.accessibilityGranted = nowGranted

                if nowGranted {
                    Logger.app.info("Accessibility permission granted")
                    self.revokedPermission = nil
                    NotificationCenter.default.post(name: .hotkeyPermissionRestored, object: nil)
                    // Switch to slower polling now that we have permission
                    self.scheduleAccessibilityCheck()
                } else {
                    Logger.app.error("Accessibility permission revoked")
                    self.revokedPermission = "Accessibility"
                    NotificationCenter.default.post(name: .hotkeyPermissionLost, object: nil)
                    // Switch to faster polling to detect re-grant quickly
                    self.scheduleAccessibilityCheck()
                }
            }
        }
    }

    func stopAllMonitoring() {
        accessibilityMonitorTimer?.invalidate()
        accessibilityMonitorTimer = nil
        accessibilityCheckTask?.cancel()
        accessibilityCheckTask = nil
        isMonitoringAccessibility = false
    }

    /// Waits for accessibility to be granted, returning once it is.
    /// Cancellable via the returned Task.
    func waitForAccessibility() -> Task<Bool, Never> {
        accessibilityCheckTask?.cancel()

        let task = Task { @MainActor [weak self] -> Bool in
            // Check up to 5 minutes (150 checks at 2-second intervals)
            for _ in 0..<150 {
                guard !Task.isCancelled else { return false }

                if AXIsProcessTrusted() {
                    self?.accessibilityGranted = true
                    return true
                }

                try? await Task.sleep(for: .seconds(2))
            }
            return false
        }

        accessibilityCheckTask = task
        return task
    }
}
