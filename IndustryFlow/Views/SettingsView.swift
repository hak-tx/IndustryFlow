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

            terminologyTab
                .tabItem {
                    Label("Terminology", systemImage: "character.book.closed")
                }

            apiTab
                .tabItem {
                    Label("API", systemImage: "key")
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
        .frame(width: 520, height: 440)
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

        }
        .formStyle(.grouped)
    }

    // MARK: - Terminology Tab

    private var terminologyTab: some View {
        Form {
            Section("Company Terminology") {
                Text("Upload a CSV or TSV file with your company's internal terminology, acronyms, and jargon. This improves both voice recognition accuracy and AI polishing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Import CSV / TSV File") {
                        settingsVM.importGlossary(into: appState)
                    }
                    .buttonStyle(.borderedProminent)

                    if settingsVM.isImportingGlossary {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let error = settingsVM.glossaryImportError {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    .font(.caption)
                }
            }

            if let glossary = appState.customGlossary, !glossary.terms.isEmpty {
                Section("Loaded: \(glossary.sourceFileName)") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(glossary.terms.count) terms loaded")
                                .font(.body)
                            Text("Imported \(glossary.importedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            settingsVM.deleteGlossary(from: appState)
                        }
                        .controlSize(.small)
                    }
                }

                Section("Preview") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(glossary.terms.prefix(50)) { term in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(term.term)
                                        .fontWeight(.medium)
                                        .frame(minWidth: 80, alignment: .leading)
                                    if !term.definition.isEmpty {
                                        Text(term.definition)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                            }
                            if glossary.terms.count > 50 {
                                Text("... and \(glossary.terms.count - 50) more terms")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
            }

            Section("File Format") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Expected format:")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("""
                    Column 1: Term or acronym (required)
                    Column 2: Definition or explanation (recommended)

                    Example:
                    FTUX, First Time User Experience
                    XFN, Cross-Functional
                    L10n, Localization
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text("Export as CSV from Excel, Google Sheets, or Numbers. Header rows are auto-detected and skipped.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - API Tab

    private var apiTab: some View {
        Form {
            if !Constants.embeddedAPIKey.isEmpty {
                Section("Built-in API Key") {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("IndustryFlow includes a built-in API key. No setup needed.")
                    }
                    .font(.caption)
                }
            }

            Section(Constants.embeddedAPIKey.isEmpty ? "Anthropic API Key" : "Custom API Key (Optional Override)") {
                SecureField("sk-ant-...", text: $settingsVM.apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save") {
                        settingsVM.saveAPIKey()
                    }
                    .disabled(settingsVM.apiKey.isEmpty)

                    Spacer()

                    if !settingsVM.apiKey.isEmpty {
                        Button("Remove", role: .destructive) {
                            settingsVM.deleteAPIKey()
                        }
                    }
                }

                if let current = ClaudePolishingService.resolveAPIKey() {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Active key: \(String(current.prefix(12)))...")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("No API key configured. Enter your Anthropic key above.")
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
                .foregroundStyle(Color.accentColor)

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
