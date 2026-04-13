import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var appState: AppState
    @Bindable var permissionsService: PermissionsService
    @State private var settingsVM = SettingsViewModel()
    @State private var launchAtLogin = AppDelegate.isLoginItemEnabled

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            apiTab
                .tabItem {
                    Label("API", systemImage: "key")
                }

            profilesTab
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }

            permissionsTab
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 380)
        .padding()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Launch IndustryFlow at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if newValue {
                            AppDelegate.registerLoginItem()
                        } else {
                            AppDelegate.unregisterLoginItem()
                        }
                    }
                Text("Recommended. Ensures IndustryFlow is always ready when you need it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dictation") {
                Toggle("Auto-polish after dictation", isOn: $settingsVM.autoPolish)
                    .onChange(of: settingsVM.autoPolish) { _, _ in
                        settingsVM.saveAutoPolish()
                    }
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Toggle Dictation:")
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Control")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                        Text("\u{00D7}2")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Tap the Control key twice quickly to start or stop dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default Industry") {
                Picker("Profile:", selection: $appState.selectedProfile) {
                    ForEach(IndustryProfile.allProfiles) { profile in
                        Label(profile.name, systemImage: profile.icon)
                            .tag(profile)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - API Tab

    private var apiTab: some View {
        Form {
            Section("Anthropic API Key") {
                SecureField("sk-ant-...", text: $settingsVM.apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Key") {
                        settingsVM.saveAPIKey()
                    }
                    .disabled(settingsVM.apiKey.isEmpty)

                    Button("Validate") {
                        settingsVM.validateAPIKey()
                    }
                    .disabled(settingsVM.apiKey.isEmpty || settingsVM.isValidatingKey)

                    if settingsVM.isValidatingKey {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if settingsVM.apiKey.isEmpty {
                        // No button shown
                    } else {
                        Button("Delete", role: .destructive) {
                            settingsVM.deleteAPIKey()
                        }
                    }
                }

                if let result = settingsVM.keyValidationResult {
                    HStack(spacing: 4) {
                        switch result {
                        case .valid:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("API key is valid")
                                .foregroundStyle(.green)
                        case .invalid:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("API key is invalid")
                                .foregroundStyle(.red)
                        case .error(let msg):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(msg)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }

            Section("Model") {
                HStack {
                    Text("Polishing model:")
                    Spacer()
                    Text(Constants.defaultModel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Profiles Tab

    private var profilesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select the industry profile that matches your work context. The AI will use industry-specific vocabulary and formatting conventions when polishing your dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                IndustryGridView(selectedProfile: $appState.selectedProfile)
            }
            .padding()
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            permissionRow(
                title: "Microphone",
                icon: "mic.fill",
                granted: permissionsService.microphoneGranted,
                action: {
                    Task { await permissionsService.requestMicrophone() }
                }
            )

            permissionRow(
                title: "Speech Recognition",
                icon: "waveform",
                granted: permissionsService.speechRecognitionGranted,
                action: {
                    Task { await permissionsService.requestSpeechRecognition() }
                }
            )

            permissionRow(
                title: "Accessibility",
                icon: "universal.access",
                granted: permissionsService.accessibilityGranted,
                action: {
                    permissionsService.requestAccessibility()
                },
                helpText: "Required to insert text at your cursor in other apps. Must be enabled in System Settings > Privacy & Security > Accessibility."
            )

            Section {
                Button("Refresh Status") {
                    permissionsService.refreshStatus()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(
        title: String,
        icon: String,
        granted: Bool,
        action: @escaping () -> Void,
        helpText: String? = nil
    ) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .frame(width: 20)
                    Text(title)
                    Spacer()
                    if granted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Grant Access") { action() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
                if let helpText, !granted {
                    Text(helpText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

            Text("IndustryFlow")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Live Voice Dictation with Industry-Aware AI Polishing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Version 1.0.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Text("Powered by Apple Speech Recognition & Claude AI")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
