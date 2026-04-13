import SwiftUI
import AppKit

struct MenuBarPopover: View {
    @Bindable var appState: AppState
    var viewModel: DictationViewModel
    @Bindable var permissionsService: PermissionsService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Permission status (always visible until all granted)
            if !permissionsService.allPermissionsGranted {
                permissionStatusBar
            }

            // Permission revocation warning
            if let revoked = permissionsService.revokedPermission {
                permissionWarning(revoked)
            }

            // Main content
            ScrollView {
                VStack(spacing: 16) {
                    // Industry + Format pickers side by side
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Industry")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $appState.selectedProfile) {
                                ForEach(IndustryProfile.allProfiles) { profile in
                                    Label(profile.name, systemImage: profile.icon).tag(profile)
                                }
                            }
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Format")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Picker("", selection: $appState.selectedFormat) {
                                ForEach(WritingFormat.allFormats) { format in
                                    Label(format.name, systemImage: format.icon).tag(format)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // Status: show polishing result or recording state (no live transcript)
                    if appState.isPolishing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Polishing with AI...")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else if let polished = appState.polishedText {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Last dictation polished")
                                    .font(.caption)
                            }
                        }
                    } else if appState.isDictating {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Recording — speak into \(appState.targetAppName ?? "target app")...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Double-tap Control to dictate at your cursor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    if let error = appState.errorMessage {
                        errorBanner(error)
                    }

                    dictationButton
                }
                .padding(16)
            }

            Divider()

            footer
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
        .onAppear {
            permissionsService.refreshStatus()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(Color.accentColor)
            Text("IndustryFlow")
                .font(.headline)
            Spacer()
            if let appName = appState.targetAppName, appState.isDictating {
                Text(appName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Permission Status Bar

    private var permissionStatusBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                permissionDot("Mic", granted: permissionsService.microphoneGranted)
                permissionDot("Speech", granted: permissionsService.speechRecognitionGranted)
                permissionDot("Accessibility", granted: permissionsService.accessibilityGranted)
                Spacer()
                Button("Refresh") {
                    permissionsService.refreshStatus()
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if !permissionsService.microphoneGranted || !permissionsService.speechRecognitionGranted {
                Button("Grant Microphone & Speech") {
                    Task {
                        if !permissionsService.microphoneGranted {
                            _ = await permissionsService.requestMicrophone()
                        }
                        if !permissionsService.speechRecognitionGranted {
                            _ = await permissionsService.requestSpeechRecognition()
                        }
                    }
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !permissionsService.accessibilityGranted {
                Button("Open Accessibility Settings") {
                    permissionsService.openAccessibilitySettings()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: Rectangle())
    }

    private func permissionDot(_ label: String, granted: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(granted ? .secondary : .primary)
        }
    }

    // MARK: - Dictation Button

    private var dictationButton: some View {
        Button(action: { viewModel.toggleDictation() }) {
            HStack(spacing: 8) {
                if appState.isDictating {
                    Image(systemName: "stop.fill")
                    Text("Stop & Polish")
                } else if appState.isPolishing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Polishing...")
                } else {
                    Image(systemName: "mic.fill")
                    Text("Start Dictation")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(appState.isDictating ? .red : .accentColor)
        .disabled(appState.isPolishing)
    }

    // MARK: - Permission Warning

    private func permissionWarning(_ permission: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(permission) permission was removed")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("Open System Settings to restore it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Fix") {
                permissionsService.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(.red.opacity(0.08), in: Rectangle())
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
            Button(action: { appState.clearError() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Settings") {
                openSettingsWindow()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            Spacer()

            Text("Ctrl \u{00D7}2")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Open Settings as Standalone Window

    private func openSettingsWindow() {
        let settingsView = SettingsView(
            appState: appState,
            permissionsService: permissionsService
        )

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "IndustryFlow Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 540, height: 460))
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Keep window alive
        NSApp.activate(ignoringOtherApps: true)
    }
}
