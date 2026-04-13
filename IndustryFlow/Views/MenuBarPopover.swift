import SwiftUI

struct MenuBarPopover: View {
    @Bindable var appState: AppState
    @Bindable var viewModel: DictationViewModel
    @Bindable var permissionsService: PermissionsService

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Main content
            ScrollView {
                VStack(spacing: 16) {
                    // Industry picker
                    IndustryPickerView(selectedProfile: $appState.selectedProfile)

                    // Dictation status / transcript
                    DictationStatusView(appState: appState)

                    // Error display
                    if let error = appState.errorMessage {
                        errorBanner(error)
                    }

                    // Dictation button
                    dictationButton
                }
                .padding(16)
            }

            Divider()

            // Footer
            footer
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverHeight)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState, permissionsService: permissionsService)
        }
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView(permissionsService: permissionsService)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.accent)
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
        .keyboardShortcut("d", modifiers: [.command, .shift])
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
                showSettings = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            Spacer()

            Text("\u{2318}\u{21E7}D")
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
}
