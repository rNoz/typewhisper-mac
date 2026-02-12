import Foundation
import FluidAudio

final class ParakeetEngine: TranscriptionEngine, @unchecked Sendable {
    let engineType: EngineType = .parakeet
    let supportsStreaming = false
    let supportsTranslation = false

    private(set) var isModelLoaded = false
    private var asrManager: AsrManager?

    var supportedLanguages: [String] {
        // Parakeet TDT v3: 25 European languages
        ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"]
    }

    func loadModel(_ model: ModelInfo, progress: @Sendable @escaping (Double, Double?) -> Void) async throws {
        guard model.engineType == .parakeet else {
            throw TranscriptionEngineError.modelLoadFailed("Not a Parakeet model")
        }

        do {
            progress(0.1, nil)

            let models = try await AsrModels.downloadAndLoad(version: .v3)
            progress(0.7, nil)

            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            progress(1.0, nil)

            asrManager = manager
            isModelLoaded = true
        } catch {
            isModelLoaded = false
            asrManager = nil
            throw TranscriptionEngineError.modelLoadFailed(error.localizedDescription)
        }
    }

    func unloadModel() {
        asrManager = nil
        isModelLoaded = false
    }

    func transcribe(
        audioSamples: [Float],
        language: String?,
        task: TranscriptionTask
    ) async throws -> TranscriptionResult {
        guard let asrManager else {
            throw TranscriptionEngineError.modelNotLoaded
        }

        if task == .translate {
            throw TranscriptionEngineError.unsupportedTask("Parakeet does not support translation")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let result = try await asrManager.transcribe(audioSamples, source: .system)

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let audioDuration = Double(audioSamples.count) / 16000.0

        let segments = Self.buildSegments(from: result, audioDuration: audioDuration)

        return TranscriptionResult(
            text: result.text,
            detectedLanguage: nil,
            duration: audioDuration,
            processingTime: processingTime,
            engineUsed: .parakeet,
            segments: segments
        )
    }

    private static func buildSegments(from result: ASRResult, audioDuration: TimeInterval) -> [TranscriptionSegment] {
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            // Fallback: single segment spanning entire duration
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [TranscriptionSegment(text: text, start: 0, end: audioDuration)]
        }

        // Aggregate word-level timings into sentence segments
        let sentenceEndings: Set<Character> = [".", "!", "?"]
        var segments: [TranscriptionSegment] = []
        var currentWords: [String] = []
        var segmentStart: TimeInterval = timings[0].startTime

        for timing in timings {
            let word = timing.token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            currentWords.append(word)

            let isSentenceEnd = word.last.map { sentenceEndings.contains($0) } ?? false
            let gapToNext = timing.endTime - segmentStart > 30.0

            if isSentenceEnd || gapToNext {
                let text = currentWords.joined(separator: " ")
                segments.append(TranscriptionSegment(
                    text: text,
                    start: segmentStart,
                    end: timing.endTime
                ))
                currentWords = []
                segmentStart = timing.endTime
            }
        }

        // Remaining words
        if !currentWords.isEmpty, let lastTiming = timings.last {
            let text = currentWords.joined(separator: " ")
            segments.append(TranscriptionSegment(
                text: text,
                start: segmentStart,
                end: lastTiming.endTime
            ))
        }

        return segments
    }
}
