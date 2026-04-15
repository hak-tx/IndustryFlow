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
    private var speechRecognizer: SFSpeechRecognizer?

    /// Serial queue protecting recognitionRequest/recognitionTask access.
    /// The audio tap callback runs on a high-priority audio thread and
    /// reads recognitionRequest. Chain swap runs on main. Without this lock,
    /// the audio thread could see a nil request mid-swap and drop frames.
    private let stateLock = NSLock()

    /// Generation counter — incremented on every task creation.
    /// Each callback captures its own generation. If the current generation
    /// has moved past the callback's generation, the callback is from a stale
    /// task and must be ignored. Prevents cascading swaps from old tasks
    /// firing terminal callbacks after they've been replaced.
    private var taskGeneration: Int = 0

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var accumulatedTranscript = ""
    private var isRunning = false
    private var savedVocabularyHints: [String] = []
    private var isOnDevice = false

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

    // MARK: - Public API

    func startTranscription(vocabularyHints: [String] = []) -> AsyncStream<TranscriptionUpdate> {
        savedVocabularyHints = vocabularyHints

        return AsyncStream<TranscriptionUpdate> { continuation in
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
    }

    func stopTranscription() {
        Logger.transcription.info("Stopping transcription")
        isRunning = false
        stateLock.lock()
        recognitionRequest?.endAudio()
        stateLock.unlock()
        cleanupAudio()
    }

    // MARK: - Audio Setup

    private func configureAndStartAudio() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        accumulatedTranscript = ""
        isRunning = true

        // Create the FIRST recognition request BEFORE installing the audio tap.
        // This ensures the tap always has a request to feed audio into.
        stateLock.lock()
        taskGeneration = 1
        let firstGen = taskGeneration
        stateLock.unlock()

        let firstRequest = createNewRequest()
        let firstTask = startTask(for: firstRequest, generation: firstGen)

        stateLock.lock()
        self.recognitionRequest = firstRequest
        self.recognitionTask = firstTask
        stateLock.unlock()

        // Install audio tap — feeds audio to whatever request is currently active.
        // The lock ensures atomic read of recognitionRequest during chain swaps.
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.stateLock.lock()
            let request = self.recognitionRequest
            self.stateLock.unlock()
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        Logger.transcription.info("Audio engine started, recognition active")
    }

    // MARK: - Recognition Request Lifecycle

    private func createNewRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        if !savedVocabularyHints.isEmpty {
            request.contextualStrings = savedVocabularyHints
        }

        if #available(macOS 13.0, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
                isOnDevice = true
            } else {
                isOnDevice = false
            }
        }

        return request
    }

    private func startTask(for request: SFSpeechAudioBufferRecognitionRequest, generation: Int) -> SFSpeechRecognitionTask? {
        return speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            // Check if this callback is from the CURRENT task or a stale one.
            // If a newer task has been created since this one was started,
            // ignore all callbacks from this old task — including its terminal
            // error/cancellation. This is what prevents cascading swaps.
            self.stateLock.lock()
            let currentGen = self.taskGeneration
            self.stateLock.unlock()
            guard generation == currentGen else {
                Logger.transcription.debug("Ignoring callback from stale task (gen \(generation) vs current \(currentGen))")
                return
            }

            if let result {
                let text = result.bestTranscription.formattedString

                if result.isFinal {
                    // Accumulate this final segment
                    if !self.accumulatedTranscript.isEmpty {
                        self.accumulatedTranscript += " "
                    }
                    self.accumulatedTranscript += text
                    self.continuation?.yield(.final_(self.accumulatedTranscript))

                    // Task is done after isFinal. Swap to a new one.
                    if self.isRunning {
                        self.swapToNewRequest()
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
                Logger.transcription.debug("Task gen \(generation) ended: \(nsError.domain) \(nsError.code)")

                guard self.isRunning else { return }

                // Current task died (timeout, no speech, etc.). Restart.
                self.swapToNewRequest()
            }
        }
    }

    /// Atomically swaps to a new recognition request. The audio tap will
    /// see the new request immediately on its next read and feed audio to it.
    /// There is NO gap where audio could be lost.
    ///
    /// Bumps taskGeneration so any stale callbacks from the old task (including
    /// its terminal error after cancel) will be ignored.
    private func swapToNewRequest() {
        guard isRunning else { return }

        // Bump generation FIRST — any in-flight callbacks from the old task
        // will see the new generation and bail out.
        stateLock.lock()
        taskGeneration += 1
        let newGen = taskGeneration
        let oldTask = self.recognitionTask
        stateLock.unlock()

        // Create the new request and start its task with the new generation.
        let newRequest = createNewRequest()
        let newTask = startTask(for: newRequest, generation: newGen)

        // Atomic swap: from this point on, the audio tap feeds the new request.
        stateLock.lock()
        self.recognitionRequest = newRequest
        self.recognitionTask = newTask
        stateLock.unlock()

        // Old task: cancel for cleanup. Its callbacks are now stale and will be ignored.
        oldTask?.cancel()
    }

    private func cleanupAudio() {
        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        stateLock.lock()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        stateLock.unlock()

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
