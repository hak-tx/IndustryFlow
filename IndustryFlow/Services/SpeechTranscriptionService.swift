import Foundation
import Speech
import AVFoundation
import os

enum TranscriptionUpdate: Sendable {
    case partial(String)
    case final_(String)
    case error(String)
}

/// Rolling re-transcription engine.
///
/// Architecture: Audio is captured continuously to an in-memory buffer.
/// Every 1.5 seconds, we transcribe the FULL accumulated audio in a fresh,
/// independent recognition request. Each transcription returns the complete
/// transcript from the start of the session.
///
/// Why this works where chained recognition fails:
/// - Each transcription is INDEPENDENT (no isFinal, no chaining, no swap)
/// - Each result is the COMPLETE transcript (no accumulation bugs)
/// - Audio is NEVER lost (it's all in the buffer)
/// - The diff is reliable because we always compare full strings
///
/// Trade-off: ~1.5s latency before text appears, vs. character-by-character.
/// But 100% reliability.
final class SpeechTranscriptionService: @unchecked Sendable {

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?

    /// All audio buffers captured during the session.
    /// Protected by bufferLock — written by audio tap, read by transcription cycle.
    private let bufferLock = NSLock()
    private var allBuffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?

    /// The currently running transcription task (if any).
    /// Cancelled and replaced on each transcription cycle.
    private var activeTask: SFSpeechRecognitionTask?
    private let taskLock = NSLock()

    private var transcriptionTimer: DispatchSourceTimer?
    private var continuation: AsyncStream<TranscriptionUpdate>.Continuation?
    private var savedVocabularyHints: [String] = []
    private var isRunning = false

    /// How often to perform a transcription cycle.
    private let transcriptionIntervalSeconds: TimeInterval = 1.5

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
                    self.cleanup()
                }
            }

            do {
                try self.startAudioCapture()
                self.startTranscriptionTimer()
                Logger.transcription.info("Rolling transcription started (interval: \(self.transcriptionIntervalSeconds)s)")
            } catch {
                Logger.transcription.error("Failed to start: \(error.localizedDescription)")
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
            }
        }
    }

    func stopTranscription() {
        Logger.transcription.info("Stopping rolling transcription")
        isRunning = false

        // Stop the periodic timer
        transcriptionTimer?.cancel()
        transcriptionTimer = nil

        // Stop audio capture
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Cancel any in-flight transcription
        taskLock.lock()
        activeTask?.cancel()
        activeTask = nil
        taskLock.unlock()

        // Run ONE FINAL transcription to capture every last word
        performFinalTranscription()
    }

    // MARK: - Audio Capture

    private func startAudioCapture() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        bufferLock.lock()
        allBuffers.removeAll()
        bufferLock.unlock()

        isRunning = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputFormat = recordingFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Copy the buffer (the original is only valid during the callback)
            guard let copy = self.copyBuffer(buffer) else { return }
            self.bufferLock.lock()
            self.allBuffers.append(copy)
            self.bufferLock.unlock()
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Seed the buffer with ~200ms of silence to help the recognizer's VAD
        // calibrate to the noise floor. Combined with the 180ms delay before
        // audio capture starts (in DictationViewModel), this gives the
        // recognizer ~380ms of total warmup before any user speech arrives.
        prependSilenceWarmup(format: recordingFormat, durationMS: 200)

        Logger.transcription.info("Audio engine started (200ms VAD warmup)")
    }

    /// Prepends silence buffers to allBuffers so the recognizer has settling time.
    /// This prevents the first words from being lost to VAD warmup.
    private func prependSilenceWarmup(format: AVAudioFormat, durationMS: Int) {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * Double(durationMS) / 1000.0)

        guard let silenceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        silenceBuffer.frameLength = frameCount

        // Buffers are zero-initialized by default, which is silence.
        bufferLock.lock()
        allBuffers.insert(silenceBuffer, at: 0)
        bufferLock.unlock()
    }

    private func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], frameLength * MemoryLayout<Float>.size)
            }
        } else if let src = buffer.int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], frameLength * MemoryLayout<Int16>.size)
            }
        } else if let src = buffer.int32ChannelData, let dst = copy.int32ChannelData {
            for ch in 0..<channelCount {
                memcpy(dst[ch], src[ch], frameLength * MemoryLayout<Int32>.size)
            }
        }
        return copy
    }

    // MARK: - Transcription Timer

    private func startTranscriptionTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + transcriptionIntervalSeconds, repeating: transcriptionIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.performTranscription(isFinal: false)
        }
        timer.resume()
        transcriptionTimer = timer
    }

    // MARK: - Transcription Cycle

    private func performTranscription(isFinal: Bool) {
        guard isRunning || isFinal else { return }

        // Snapshot the audio buffers under lock
        bufferLock.lock()
        let snapshot = allBuffers
        bufferLock.unlock()

        guard !snapshot.isEmpty else { return }

        // Cancel any in-flight transcription — we always work on the latest snapshot
        taskLock.lock()
        activeTask?.cancel()
        activeTask = nil
        taskLock.unlock()

        // Build a fresh request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true

        if !savedVocabularyHints.isEmpty {
            request.contextualStrings = savedVocabularyHints
        }

        if #available(macOS 13.0, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
        }

        let updateType: (String) -> TranscriptionUpdate = isFinal ? { .final_($0) } : { .partial($0) }

        let task = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result, result.isFinal {
                let text = result.bestTranscription.formattedString
                self.continuation?.yield(updateType(text))
                Logger.transcription.debug("Cycle complete: \(text.count) chars from \(snapshot.count) buffers")
            }

            if let error {
                let nsError = error as NSError
                // 1110 = no speech detected — happens at very start, ignore
                if nsError.code != 1110 {
                    Logger.transcription.debug("Transcription cycle error: \(nsError.code)")
                }
            }
        }

        taskLock.lock()
        activeTask = task
        taskLock.unlock()

        // Append all buffered audio to the request, then signal end
        for buffer in snapshot {
            request.append(buffer)
        }
        request.endAudio()
    }

    /// Run one final transcription synchronously to capture the very last words.
    /// Called when the user stops dictation.
    private func performFinalTranscription() {
        bufferLock.lock()
        let snapshot = allBuffers
        bufferLock.unlock()

        guard !snapshot.isEmpty else {
            continuation?.finish()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.addsPunctuation = true
        if !savedVocabularyHints.isEmpty {
            request.contextualStrings = savedVocabularyHints
        }
        if #available(macOS 13.0, *) {
            if speechRecognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true
            }
        }

        // Use a semaphore to make this synchronous so the caller waits for the result
        let semaphore = DispatchSemaphore(value: 0)
        var didFinish = false

        let task = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard !didFinish else { return }

            if let result, result.isFinal {
                didFinish = true
                let text = result.bestTranscription.formattedString
                self?.continuation?.yield(.final_(text))
                Logger.transcription.info("Final transcription: \(text.count) chars")
                semaphore.signal()
            }

            if let _ = error {
                if !didFinish {
                    didFinish = true
                    semaphore.signal()
                }
            }
        }

        for buffer in snapshot {
            request.append(buffer)
        }
        request.endAudio()

        // Wait up to 5 seconds for final transcription
        _ = semaphore.wait(timeout: .now() + 5.0)
        task?.cancel()

        continuation?.finish()
    }

    // MARK: - Cleanup

    private func cleanup() {
        isRunning = false
        transcriptionTimer?.cancel()
        transcriptionTimer = nil

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        taskLock.lock()
        activeTask?.cancel()
        activeTask = nil
        taskLock.unlock()

        bufferLock.lock()
        allBuffers.removeAll()
        bufferLock.unlock()

        Logger.transcription.info("Cleanup complete")
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
