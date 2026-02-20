import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import AppKit
import Combine
import os

/// Captures microphone audio via AVAudioEngine and converts to 16kHz mono Float32 samples.
final class AudioRecordingService: ObservableObject, @unchecked Sendable {

    enum AudioRecordingError: LocalizedError {
        case microphonePermissionDenied
        case engineStartFailed(String)
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                "Microphone permission denied. Please grant access in System Settings."
            case .engineStartFailed(let detail):
                "Failed to start audio engine: \(detail)"
            case .noAudioData:
                "No audio data was recorded."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var rawAudioLevel: Float = 0
    @Published private(set) var isSilent: Bool = false
    @Published private(set) var silenceDuration: TimeInterval = 0
    @Published var didAutoStop: Bool = false
    @Published private(set) var isPaused: Bool = false

    /// RMS threshold below which audio is considered silence
    var silenceThreshold: Float {
        get { configLock.withLock { _silenceThreshold } }
        set { configLock.withLock { _silenceThreshold = newValue } }
    }
    /// Duration of continuous silence before auto-stop triggers
    var silenceAutoStopDuration: TimeInterval {
        get { configLock.withLock { _silenceAutoStopDuration } }
        set { configLock.withLock { _silenceAutoStopDuration = newValue } }
    }
    /// Gain multiplier applied to audio samples (1.0 = normal, 4.0 = whisper mode)
    var gainMultiplier: Float {
        get { configLock.withLock { _gainMultiplier } }
        set { configLock.withLock { _gainMultiplier = newValue } }
    }
    /// CoreAudio device ID to use for recording. nil = system default input.
    var selectedDeviceID: AudioDeviceID? {
        get { configLock.withLock { _selectedDeviceID } }
        set { configLock.withLock { _selectedDeviceID = newValue } }
    }

    private var _silenceThreshold: Float = 0.015
    private var _silenceAutoStopDuration: TimeInterval = 4.0
    private var _gainMultiplier: Float = 1.0
    private var _selectedDeviceID: AudioDeviceID?

    private var audioEngine: AVAudioEngine?
    private var sampleBuffer: [Float] = []
    private let bufferLock = NSLock()
    private let configLock = NSLock()
    private var silenceStart: Date?
    private let processingQueue = DispatchQueue(label: "com.typewhisper.audio-processing", qos: .userInteractive)

    static let targetSampleRate: Double = 16000

    var hasMicrophonePermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func requestMicrophonePermission() async -> Bool {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .granted { return true }
        if permission == .undetermined {
            // Request permission via the official AVAudioApplication API
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        // .denied — open System Settings so user can grant manually
        DispatchQueue.main.async {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
        return false
    }

    /// Thread-safe snapshot of the current recording buffer for streaming transcription.
    func getCurrentBuffer() -> [Float] {
        bufferLock.lock()
        let copy = sampleBuffer
        bufferLock.unlock()
        return copy
    }

    /// Returns at most the last `maxDuration` seconds of audio for streaming.
    func getRecentBuffer(maxDuration: TimeInterval) -> [Float] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        let maxSamples = Int(maxDuration * Self.targetSampleRate)
        if sampleBuffer.count <= maxSamples { return sampleBuffer }
        return Array(sampleBuffer.suffix(maxSamples))
    }

    /// Total duration of the recorded audio in seconds.
    var totalBufferDuration: TimeInterval {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return Double(sampleBuffer.count) / Self.targetSampleRate
    }

    func startRecording() throws {
        guard hasMicrophonePermission else {
            throw AudioRecordingError.microphonePermissionDenied
        }

        let engine = AVAudioEngine()

        // Set the input device before reading the format
        if let deviceID = selectedDeviceID,
           let audioUnit = engine.inputNode.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecordingError.engineStartFailed("No audio input available")
        }

        // Target format: 16kHz mono Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecordingError.engineStartFailed("Cannot create target audio format")
        }

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        guard let converter else {
            throw AudioRecordingError.engineStartFailed("Cannot create audio converter")
        }

        bufferLock.lock()
        sampleBuffer.removeAll()
        bufferLock.unlock()

        silenceStart = nil
        isSilent = false
        silenceDuration = 0
        didAutoStop = false
        isPaused = false

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecordingError.engineStartFailed(error.localizedDescription)
        }

        audioEngine = engine
        isRecording = true
    }

    func pauseRecording() {
        isPaused = true
        // Trim the trailing silence from the buffer to prevent hallucination
        trimTrailingSilence()
    }

    /// Removes the trailing silent samples from the buffer.
    /// Called when pausing to avoid feeding silence to the transcription engine.
    private func trimTrailingSilence() {
        let trimSamples = Int(silenceAutoStopDuration * Self.targetSampleRate)
        bufferLock.lock()
        if sampleBuffer.count > trimSamples {
            sampleBuffer.removeLast(trimSamples)
        }
        bufferLock.unlock()
    }

    func resumeRecording() {
        isPaused = false
        silenceStart = nil
        DispatchQueue.main.async { [weak self] in
            self?.isSilent = false
            self?.silenceDuration = 0
        }
    }

    func stopRecording() -> [Float] {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Flush pending audio processing before grabbing the buffer
        processingQueue.sync { }

        isRecording = false
        isPaused = false
        audioLevel = 0
        isSilent = false
        silenceDuration = 0
        silenceStart = nil

        bufferLock.lock()
        let samples = sampleBuffer
        sampleBuffer.removeAll()
        bufferLock.unlock()

        return samples
    }

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        // Convert sample rate on the render thread (AVAudioConverter requires thread consistency)
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * Self.targetSampleRate / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        let consumed = OSAllocatedUnfairLock(initialState: false)

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            let wasConsumed = consumed.withLock { flag in
                let prev = flag
                flag = true
                return prev
            }
            if wasConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, convertedBuffer.frameLength > 0 else { return }
        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }

        // Quick copy of converted samples, then dispatch heavy work off the render thread
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))

        processingQueue.async { [weak self] in
            self?.processConvertedSamples(samples)
        }
    }

    private func processConvertedSamples(_ rawSamples: [Float]) {
        // Calculate raw RMS BEFORE gain for silence detection (gain-independent)
        let rawRms = sqrt(rawSamples.reduce(0) { $0 + $1 * $1 } / Float(rawSamples.count))
        let silent = rawRms < silenceThreshold

        var samples = rawSamples

        // Apply gain boost (whisper mode)
        if gainMultiplier != 1.0 {
            for i in samples.indices {
                samples[i] = max(-1.0, min(1.0, samples[i] * gainMultiplier))
            }
        }

        // Calculate post-gain RMS for audio level display
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let normalizedLevel = min(1.0, rms * 5) // Scale up for visibility

        // When paused, still detect silence/speech but don't write to buffer
        if !isPaused {
            bufferLock.lock()
            sampleBuffer.append(contentsOf: samples)
            bufferLock.unlock()
        }

        let now = Date()
        let capturedSilenceStart = silenceStart

        let capturedRawRms = rawRms

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.audioLevel = normalizedLevel
            self.rawAudioLevel = capturedRawRms

            if silent {
                if self.silenceStart == nil {
                    self.silenceStart = now
                }
                if let start = self.silenceStart ?? capturedSilenceStart {
                    self.silenceDuration = now.timeIntervalSince(start)
                }
                self.isSilent = true
            } else {
                self.silenceStart = nil
                self.silenceDuration = 0
                self.isSilent = false
            }
        }
    }
}
