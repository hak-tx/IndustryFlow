import SwiftUI

struct DictationStatusView: View {
    let appState: AppState

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 10) {
            // Status indicator
            statusIndicator

            // Transcript display
            transcriptArea
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            if appState.isDictating {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .opacity(pulseAnimation ? 0.6 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }

                Text("Recording...")
                    .font(.caption)
                    .foregroundStyle(.red)

            } else if appState.isPolishing {
                ProgressView()
                    .controlSize(.small)
                Text("Polishing with AI...")
                    .font(.caption)
                    .foregroundStyle(.orange)

            } else if appState.polishedText != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Complete")
                    .font(.caption)
                    .foregroundStyle(.green)

            } else {
                Image(systemName: "mic.slash")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Transcript Area

    private var transcriptArea: some View {
        Group {
            if appState.isDictating || !appState.liveTranscript.isEmpty || appState.polishedText != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if appState.isDictating || (!appState.liveTranscript.isEmpty && appState.polishedText == nil) {
                        // Live transcript
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Live Transcript")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ScrollView {
                                Text(appState.liveTranscript.isEmpty ? "Listening..." : appState.liveTranscript)
                                    .font(.body)
                                    .foregroundStyle(appState.liveTranscript.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 60, maxHeight: 120)
                        }
                    }

                    if let polished = appState.polishedText {
                        // Polished result
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Polished")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            ScrollView {
                                Text(polished)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 60, maxHeight: 120)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Press Start or double-tap Control to begin dictating")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
