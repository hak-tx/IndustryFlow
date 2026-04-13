import SwiftUI
import ServiceManagement

struct OnboardingView: View {
    @Bindable var permissionsService: PermissionsService
    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var isValidating = false
    @State private var keyIsValid: Bool?
    @State private var launchAtLogin = true

    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 5
    private let steps = [
        "Microphone Access",
        "Speech Recognition",
        "Accessibility",
        "API Key",
        "Launch at Login"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 4) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0: microphoneStep
                case 1: speechStep
                case 2: accessibilityStep
                case 3: apiKeyStep
                case 4: launchAtLoginStep
                default: completionStep
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if currentStep < steps.count {
                    Button(currentStep == steps.count - 1 ? "Finish" : "Next") {
                        if currentStep >= steps.count - 1 {
                            finishOnboarding()
                        } else {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 440, height: 360)
    }

    // MARK: - Step Views

    private var microphoneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.accent)

            Text("Microphone Access")
                .font(.title3)
                .fontWeight(.semibold)

            Text("IndustryFlow needs access to your microphone to transcribe your voice in real time.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if permissionsService.microphoneGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Microphone Access") {
                    Task { await permissionsService.requestMicrophone() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var speechStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.accent)

            Text("Speech Recognition")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Speech recognition converts your spoken words to text. This can be processed on-device for privacy.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if permissionsService.speechRecognitionGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant Speech Recognition") {
                    Task { await permissionsService.requestSpeechRecognition() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "universal.access")
                .font(.system(size: 40))
                .foregroundStyle(.accent)

            Text("Accessibility Access")
                .font(.title3)
                .fontWeight(.semibold)

            Text("IndustryFlow needs accessibility access to insert text at your cursor position in other applications. You'll need to add IndustryFlow in System Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if permissionsService.accessibilityGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 8) {
                    Button("Open System Settings") {
                        permissionsService.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Button("Check Again") {
                        permissionsService.refreshStatus()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.accent)

            Text("Anthropic API Key")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enter your Anthropic API key to enable AI-powered text polishing with Claude. Your key is stored securely in your Mac's Keychain.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SecureField("sk-ant-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            HStack(spacing: 12) {
                Button("Save & Validate") {
                    saveAndValidateKey()
                }
                .buttonStyle(.bordered)
                .disabled(apiKey.isEmpty || isValidating)

                if isValidating {
                    ProgressView()
                        .controlSize(.small)
                }

                if let valid = keyIsValid {
                    Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(valid ? .green : .red)
                }
            }
        }
    }

    private var launchAtLoginStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "power")
                .font(.system(size: 40))
                .foregroundStyle(.accent)

            Text("Launch at Login")
                .font(.title3)
                .fontWeight(.semibold)

            Text("IndustryFlow works best when it's always running in your menu bar, ready when you need it. We recommend enabling launch at login so you never have to think about starting it.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle("Launch IndustryFlow at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .frame(maxWidth: 260)
        }
    }

    private var completionStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Double-tap Control anywhere to start dictating.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func saveAndValidateKey() {
        guard !apiKey.isEmpty else { return }
        isValidating = true
        keyIsValid = nil

        do {
            try KeychainHelper.save(apiKey: apiKey)
        } catch {
            isValidating = false
            keyIsValid = false
            return
        }

        Task {
            let service = ClaudePolishingService()
            let valid = await service.validateAPIKey(apiKey)
            await MainActor.run {
                isValidating = false
                keyIsValid = valid
            }
        }
    }

    private func finishOnboarding() {
        if launchAtLogin {
            AppDelegate.registerLoginItem()
        }
        dismiss()
    }
}
