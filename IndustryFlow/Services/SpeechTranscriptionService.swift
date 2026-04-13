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

    private var isOnDevice = false

    private func startRecognitionRequest() {
        isChaining = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Keep the recognition task alive even after long pauses
        request.addsPunctuation = true

        if !savedVocabularyHints.isEmpty {
            request.contextualStrings = savedVocabularyHints
        }

        // On-device recognition has NO time limit.
        // When on-device, we NEVER chain — one request runs the entire session.
        if #available(macOS 13.0, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
                isOnDevice = true
                Logger.transcription.info("Using on-device recognition (no time limit, no chaining)")
            } else {
                isOnDevice = false
                Logger.transcription.info("On-device not available, using server")
            }
        }

        self.recognitionRequest = request

        // Replay any audio buffers captured during a chain gap
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

                    // ALWAYS chain after a final result. The recognition task is
                    // DONE after isFinal — it will never send another callback.
                    // This is true for BOTH on-device and server modes.
                    // The debounce+diff typing strategy handles chaining safely.
                    if self.isRunning {
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

                if self.isChaining {
                    Logger.transcription.debug("Ignoring error during chain: \(nsError.code)")
                    return
                }

                guard self.isRunning else { return }

                // On-device mode: the task ended (timeout, no speech detected, etc.)
                // Restart seamlessly — accumulate what we have, start fresh.
                Logger.transcription.info("Recognition ended (\(nsError.domain) \(nsError.code)), restarting")
                self.chainNewRequest()
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
