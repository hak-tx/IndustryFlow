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

    private func startRecognitionRequest(vocabularyHints: [String]) {
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
                // The recognizer hit a limit or an actual error
                let nsError = error as NSError
                // Error code 1101 = "request limit reached" — this is normal, chain a new one
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101 {
                    if self.isRunning {
                        Logger.transcription.info("Request limit reached, chaining new request")
                        self.chainNewRequest(vocabularyHints: self.recognitionRequest?.contextualStrings ?? [])
                    }
                } else if self.isRunning {
                    Logger.transcription.error("Recognition error: \(error.localizedDescription)")
                    self.continuation?.yield(.error(error.localizedDescription))
                    self.continuation?.finish()
                    self.isRunning = false
                }
            }
        }
    }

    private func chainNewRequest(vocabularyHints: [String]) {
        // Remove existing tap before installing a new one
        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Short delay to let the system settle, then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startRecognitionRequest(vocabularyHints: vocabularyHints)
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
