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
        let stream = AsyncStream<TranscriptionUpdate> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.cleanupAudio()
                }
            }

            do {
                try self.configureAndStartAudio(vocabularyHints: vocabularyHints)
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
        recognitionRequest?.endAudio()
        cleanupAudio()
        isRunning = false
    }

    // MARK: - Private

    private func configureAndStartAudio(vocabularyHints: [String]) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        accumulatedTranscript = ""
        isRunning = true

        startRecognitionRequest(vocabularyHints: vocabularyHints)
    }

    private var isChaining = false

    private func startRecognitionRequest(vocabularyHints: [String]) {
        isChaining = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        if !vocabularyHints.isEmpty {
            request.contextualStrings = vocabularyHints
        }

        // Prefer on-device recognition if available (avoids network dependency)
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
                Logger.transcription.info("Using on-device recognition")
            }
        }

        self.recognitionRequest = request

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            Logger.transcription.info("Audio engine started")
        } catch {
            Logger.transcription.error("Audio engine failed to start: \(error.localizedDescription)")
            continuation?.yield(.error("Failed to start audio: \(error.localizedDescription)"))
            continuation?.finish()
            return
        }

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString

                if result.isFinal {
                    // Accumulate final segments
                    if !self.accumulatedTranscript.isEmpty {
                        self.accumulatedTranscript += " "
                    }
                    self.accumulatedTranscript += text
                    self.continuation?.yield(.final_(self.accumulatedTranscript))

                    // If still running, chain a new recognition request
                    // (handles Apple's ~1 minute limit per request)
                    if self.isRunning {
                        Logger.transcription.info("Chaining new recognition request")
                        self.chainNewRequest(vocabularyHints: self.recognitionRequest?.contextualStrings ?? [])
                    }
                } else {
                    // Partial result — show accumulated + current partial
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

                // During chaining, the old task is cancelled which triggers an error.
                // Ignore ALL errors while chaining — the new request is already starting.
                if self.isChaining {
                    Logger.transcription.debug("Ignoring error during chain: \(nsError.code)")
                    return
                }

                // Error 1101 = request limit reached — chain a new request
                // Error 216, 209 = task/request cancelled — also chain
                // Error 1110 = no speech detected timeout — chain (user might resume speaking)
                let recoverableCodes = [1101, 216, 209, 1110]
                if recoverableCodes.contains(nsError.code) || nsError.domain == "kAFAssistantErrorDomain" {
                    if self.isRunning {
                        Logger.transcription.info("Recoverable error (\(nsError.code)), chaining new request")
                        self.chainNewRequest(vocabularyHints: self.recognitionRequest?.contextualStrings ?? [])
                    }
                } else if self.isRunning {
                    // Truly fatal error — log it but try to recover anyway
                    Logger.transcription.error("Recognition error (\(nsError.domain) \(nsError.code)): \(error.localizedDescription)")
                    // Try to chain rather than giving up
                    self.chainNewRequest(vocabularyHints: self.recognitionRequest?.contextualStrings ?? [])
                }
            }
        }
    }

    private func chainNewRequest(vocabularyHints: [String]) {
        // Set flag BEFORE cancelling to suppress error callbacks from the dying task
        isChaining = true

        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Short delay to let the system settle, then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startRecognitionRequest(vocabularyHints: vocabularyHints)
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
