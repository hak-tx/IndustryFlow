import Foundation
import Speech
import AVFoundation
import os

enum TranscriptionUpdate: Sendable {
    case partial(String)
    case final_(String)
    case error(String)
}

final class SpeechTranscriptionService: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var continuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var accumulatedTranscript = ""
    private var isRunning = false
    private var isChaining = false
    private var savedVocabularyHints: [String] = []

    init(locale: Locale = .current) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Transcription

    func startTranscription(vocabularyHints: [String] = []) -> AsyncStream<TranscriptionUpdate> {
        savedVocabularyHints = vocabularyHints

        let stream = AsyncStream<TranscriptionUpdate> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.cleanupAudio()
                }
            }

            do {
                try self.configureAndStartAudio()
            } catch {
                Logger.transcription.error("Failed to start transcription: \(error.localizedDescription)")
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
            }
        }
        return stream
    }

    func stopTranscription() {
        Logger.transcription.info("Stopping transcription")
        isRunning = false
        recognitionRequest?.endAudio()
        cleanupAudio()
    }

    // MARK: - Private

    /// Audio buffers captured during the chain gap — replayed into the new request.
    private var pendingBuffers: [AVAudioPCMBuffer] = []

    private func configureAndStartAudio() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        accumulatedTranscript = ""
        pendingBuffers = []
        isRunning = true

        // Start the audio engine ONCE — it stays running for the entire session
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if let request = self.recognitionRequest {
                // Normal path: feed audio to the active recognizer
                request.append(buffer)
            } else {
                // Chain gap: buffer the audio so no words are lost
                self.pendingBuffers.append(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        Logger.transcription.info("Audio engine started")

        // Start the first recognition request
        startRecognitionRequest()
    }

    private func startRecognitionRequest() {
        isChaining = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        if !savedVocabularyHints.isEmpty {
            request.contextualStrings = savedVocabularyHints
        }

        // On-device recognition has NO time limit (no 1-minute cap).
        // This eliminates the need for chaining entirely.
        if #available(macOS 13.0, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
                Logger.transcription.info("Using on-device recognition (no time limit)")
            } else {
                Logger.transcription.info("On-device not available, using server (1-min limit, will chain)")
            }
        }

        self.recognitionRequest = request

        // Replay any audio buffers captured during the chain gap
        if !pendingBuffers.isEmpty {
            Logger.transcription.info("Replaying \(self.pendingBuffers.count) buffered audio frames")
            for buffer in pendingBuffers {
                request.append(buffer)
            }
            pendingBuffers.removeAll()
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString

                if result.isFinal {
                    if !self.accumulatedTranscript.isEmpty {
                        self.accumulatedTranscript += " "
                    }
                    self.accumulatedTranscript += text
                    self.continuation?.yield(.final_(self.accumulatedTranscript))

                    // Chain a new request if still running
                    // (only needed for server-based recognition hitting the 1-min limit)
                    if self.isRunning {
                        Logger.transcription.info("Final result received, chaining new request")
                        self.chainNewRequest()
                    }
                } else {
                    var fullText = self.accumulatedTranscript
                    if !fullText.isEmpty {
                        fullText += " "
                    }
                    fullText += text
                    self.continuation?.yield(.partial(fullText))
                }
            }

            if let error {
                let nsError = error as NSError

                // Ignore errors during chaining — the old task is being torn down
                if self.isChaining {
                    Logger.transcription.debug("Ignoring error during chain: \(nsError.code)")
                    return
                }

                if self.isRunning {
                    Logger.transcription.info("Recognition error (\(nsError.code)), attempting recovery")
                    self.chainNewRequest()
                }
            }
        }
    }

    private func chainNewRequest() {
        isChaining = true

        // Cancel the old recognition task but DO NOT stop the audio engine.
        // The audio tap keeps running — no gap in audio capture.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Brief delay for the system to release the old task, then start a new one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startRecognitionRequest()
        }
    }

    private func cleanupAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        continuation?.finish()
        continuation = nil

        Logger.transcription.info("Audio cleanup completed")
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case microphoneAccessDenied
    case speechRecognitionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available on this device."
        case .microphoneAccessDenied:
            return "Microphone access was denied. Please enable it in System Settings."
        case .speechRecognitionDenied:
            return "Speech recognition access was denied. Please enable it in System Settings."
        }
    }
}
