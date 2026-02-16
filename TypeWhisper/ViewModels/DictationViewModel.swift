import Foundation
import Combine

/// Orchestrates the dictation flow: recording → transcription → text insertion.
@MainActor
final class DictationViewModel: ObservableObject {
    nonisolated(unsafe) static var _shared: DictationViewModel?
    static var shared: DictationViewModel {
        guard let instance = _shared else {
            fatalError("DictationViewModel not initialized")
        }
        return instance
    }

    enum State: Equatable {
        case idle
        case recording
        case processing
        case inserting
        case copiedToClipboard
        case error(String)
    }

    @Published var state: State = .idle
    @Published var audioLevel: Float = 0
    @Published var recordingDuration: TimeInterval = 0
    @Published var hotkeyMode: HotkeyService.HotkeyMode?
    @Published var partialText: String = ""
    @Published var isStreaming: Bool = false
    @Published var whisperModeEnabled: Bool {
        didSet { UserDefaults.standard.set(whisperModeEnabled, forKey: "whisperModeEnabled") }
    }
    @Published var audioDuckingEnabled: Bool {
        didSet { UserDefaults.standard.set(audioDuckingEnabled, forKey: "audioDuckingEnabled") }
    }
    @Published var audioDuckingLevel: Double {
        didSet { UserDefaults.standard.set(audioDuckingLevel, forKey: "audioDuckingLevel") }
    }
    @Published var mediaPauseEnabled: Bool {
        didSet { UserDefaults.standard.set(mediaPauseEnabled, forKey: "mediaPauseEnabled") }
    }
    @Published var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: "soundFeedbackEnabled") }
    }
    @Published var singleKeyMode: Bool {
        didSet { UserDefaults.standard.set(singleKeyMode, forKey: "hotkeyUseSingleKey") }
    }
    @Published var singleKeyLabel: String
    @Published var activeProfileName: String?

    enum OverlayPosition: String, CaseIterable {
        case top
        case bottom
    }

    @Published var overlayPosition: OverlayPosition {
        didSet { UserDefaults.standard.set(overlayPosition.rawValue, forKey: "overlayPosition") }
    }

    private let audioRecordingService: AudioRecordingService
    private let textInsertionService: TextInsertionService
    private let hotkeyService: HotkeyService
    private let modelManager: ModelManagerService
    private let settingsViewModel: SettingsViewModel
    private let historyService: HistoryService
    private let profileService: ProfileService
    private let translationService: TranslationService
    private let audioDuckingService: AudioDuckingService
    private let mediaPlaybackService: MediaPlaybackService
    private let dictionaryService: DictionaryService
    private let snippetService: SnippetService
    private let soundService: SoundService
    private var matchedProfile: Profile?
    private var capturedActiveApp: (name: String?, bundleId: String?, url: String?)?

    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var streamingTask: Task<Void, Never>?
    private var silenceCancellable: AnyCancellable?

    init(
        audioRecordingService: AudioRecordingService,
        textInsertionService: TextInsertionService,
        hotkeyService: HotkeyService,
        modelManager: ModelManagerService,
        settingsViewModel: SettingsViewModel,
        historyService: HistoryService,
        profileService: ProfileService,
        translationService: TranslationService,
        audioDuckingService: AudioDuckingService,
        mediaPlaybackService: MediaPlaybackService,
        dictionaryService: DictionaryService,
        snippetService: SnippetService,
        soundService: SoundService
    ) {
        self.audioRecordingService = audioRecordingService
        self.textInsertionService = textInsertionService
        self.hotkeyService = hotkeyService
        self.modelManager = modelManager
        self.settingsViewModel = settingsViewModel
        self.historyService = historyService
        self.profileService = profileService
        self.translationService = translationService
        self.audioDuckingService = audioDuckingService
        self.mediaPlaybackService = mediaPlaybackService
        self.dictionaryService = dictionaryService
        self.snippetService = snippetService
        self.soundService = soundService
        self.whisperModeEnabled = UserDefaults.standard.bool(forKey: "whisperModeEnabled")
        self.audioDuckingEnabled = UserDefaults.standard.bool(forKey: "audioDuckingEnabled")
        self.audioDuckingLevel = UserDefaults.standard.object(forKey: "audioDuckingLevel") as? Double ?? 0.2
        self.mediaPauseEnabled = UserDefaults.standard.bool(forKey: "mediaPauseEnabled")
        self.soundFeedbackEnabled = UserDefaults.standard.object(forKey: "soundFeedbackEnabled") as? Bool ?? true
        let useSingleKey = UserDefaults.standard.bool(forKey: "hotkeyUseSingleKey")
        self.singleKeyMode = useSingleKey
        let isFn = UserDefaults.standard.bool(forKey: "singleKeyIsFn")
        let code = UInt16(UserDefaults.standard.integer(forKey: "singleKeyCode"))
        self.singleKeyLabel = useSingleKey
            ? HotkeyService.keyName(for: code, isFn: isFn)
            : ""
        self.overlayPosition = UserDefaults.standard.string(forKey: "overlayPosition")
            .flatMap { OverlayPosition(rawValue: $0) } ?? .top

        setupBindings()
    }

    var canDictate: Bool {
        modelManager.activeEngine?.isModelLoaded == true
    }

    var needsMicPermission: Bool {
        !audioRecordingService.hasMicrophonePermission
    }

    var needsAccessibilityPermission: Bool {
        !textInsertionService.isAccessibilityGranted
    }

    private func setupBindings() {
        hotkeyService.onDictationStart = { [weak self] in
            self?.startRecording()
        }

        hotkeyService.onDictationStop = { [weak self] in
            self?.stopDictation()
        }

        audioRecordingService.$audioLevel
            .dropFirst()
            .sink { [weak self] level in
                DispatchQueue.main.async {
                    self?.audioLevel = level
                }
            }
            .store(in: &cancellables)

        hotkeyService.$currentMode
            .dropFirst()
            .sink { [weak self] mode in
                DispatchQueue.main.async {
                    self?.hotkeyMode = mode
                }
            }
            .store(in: &cancellables)
    }

    private func startRecording() {
        guard canDictate else {
            showError("No model loaded. Please download a model first.")
            return
        }

        guard audioRecordingService.hasMicrophonePermission else {
            showError("Microphone permission required.")
            return
        }

        // Match profile based on active app — store for reuse in stopDictation
        let activeApp = textInsertionService.captureActiveApp()
        capturedActiveApp = activeApp
        matchedProfile = profileService.matchProfile(bundleIdentifier: activeApp.bundleId, url: activeApp.url)
        activeProfileName = matchedProfile?.name

        // Apply gain boost: profile override ?? global setting
        let effectiveWhisperMode = matchedProfile?.whisperModeOverride ?? whisperModeEnabled
        audioRecordingService.gainMultiplier = effectiveWhisperMode ? 4.0 : 1.0

        do {
            try audioRecordingService.startRecording()
            if audioDuckingEnabled {
                audioDuckingService.duckAudio(to: Float(audioDuckingLevel))
            }
            if mediaPauseEnabled {
                mediaPlaybackService.pausePlayback()
            }
            state = .recording
            soundService.play(.recordingStarted, enabled: soundFeedbackEnabled)
            partialText = ""
            recordingStartTime = Date()
            startRecordingTimer()
            startStreamingIfSupported()
            startSilenceDetection()
        } catch {
            audioDuckingService.restoreAudio()
            mediaPlaybackService.resumePlayback()
            soundService.play(.error, enabled: soundFeedbackEnabled)
            showError(error.localizedDescription)
            hotkeyService.cancelDictation()
        }
    }

    private var effectiveLanguage: String? {
        if let profileLang = matchedProfile?.inputLanguage {
            return profileLang == "auto" ? nil : profileLang
        }
        return settingsViewModel.selectedLanguage
    }

    private var effectiveTask: TranscriptionTask {
        if let profileTask = matchedProfile?.selectedTask,
           let task = TranscriptionTask(rawValue: profileTask) {
            return task
        }
        return settingsViewModel.selectedTask
    }

    private var effectiveTranslationTarget: String? {
        if let profileTarget = matchedProfile?.translationTargetLanguage {
            return profileTarget
        }
        if settingsViewModel.translationEnabled {
            return settingsViewModel.translationTargetLanguage
        }
        return nil
    }

    private var effectiveEngineOverride: EngineType? {
        guard let raw = matchedProfile?.engineOverride else { return nil }
        return EngineType(rawValue: raw)
    }

    private func stopDictation() {
        guard state == .recording else { return }

        audioDuckingService.restoreAudio()
        mediaPlaybackService.resumePlayback()
        stopStreaming()
        stopSilenceDetection()
        stopRecordingTimer()
        let samples = audioRecordingService.stopRecording()

        guard !samples.isEmpty else {
            state = .idle
            partialText = ""
            matchedProfile = nil
            capturedActiveApp = nil
            activeProfileName = nil
            return
        }

        let audioDuration = Double(samples.count) / 16000.0
        guard audioDuration >= 0.3 else {
            // Too short to transcribe meaningfully
            state = .idle
            partialText = ""
            matchedProfile = nil
            capturedActiveApp = nil
            activeProfileName = nil
            return
        }

        // Reuse the active app captured at recording start — avoids blocking
        // the main thread with a second AppleScript call (up to 2.5s for browsers)
        let activeApp = capturedActiveApp ?? textInsertionService.captureActiveApp()
        let language = effectiveLanguage
        let task = effectiveTask
        let engineOverride = effectiveEngineOverride
        let translationTarget = effectiveTranslationTarget

        state = .processing

        Task {
            do {
                let result = try await modelManager.transcribe(
                    audioSamples: samples,
                    language: language,
                    task: task,
                    engineOverride: engineOverride
                )

                var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    state = .idle
                    partialText = ""
                    matchedProfile = nil
                    capturedActiveApp = nil
                    activeProfileName = nil
                    return
                }

                if let targetCode = translationTarget {
                    let target = Locale.Language(identifier: targetCode)
                    text = try await translationService.translate(text: text, to: target)
                }

                // Post-processing pipeline
                text = snippetService.applySnippets(to: text)
                text = dictionaryService.applyCorrections(to: text)

                partialText = ""
                let insertionResult = try await textInsertionService.insertText(
                    text,
                    forcePaste: matchedProfile?.alwaysPaste == true
                )

                historyService.addRecord(
                    rawText: result.text,
                    finalText: text,
                    appName: activeApp.name,
                    appBundleIdentifier: activeApp.bundleId,
                    appURL: activeApp.url,
                    durationSeconds: audioDuration,
                    language: language,
                    engineUsed: result.engineUsed.rawValue
                )

                soundService.play(.transcriptionSuccess, enabled: soundFeedbackEnabled)

                switch insertionResult {
                case .pasted:
                    state = .inserting
                case .copiedToClipboard:
                    state = .copiedToClipboard
                }

                try? await Task.sleep(for: .seconds(1.5))
                state = .idle
                matchedProfile = nil
                capturedActiveApp = nil
                activeProfileName = nil
            } catch {
                soundService.play(.error, enabled: soundFeedbackEnabled)
                showError(error.localizedDescription)
                matchedProfile = nil
                capturedActiveApp = nil
                activeProfileName = nil
            }
        }
    }

    func requestMicPermission() {
        Task {
            _ = await audioRecordingService.requestMicrophonePermission()
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
            pollPermissionStatus()
        }
    }

    func requestAccessibilityPermission() {
        textInsertionService.requestAccessibilityPermission()
        pollPermissionStatus()
    }

    func setSingleKey(code: UInt16, isFn: Bool) {
        let label = HotkeyService.keyName(for: code, isFn: isFn)
        singleKeyLabel = label
        singleKeyMode = true
        hotkeyService.updateSingleKey(code: code, isFn: isFn)
    }

    func disableSingleKey() {
        singleKeyMode = false
        singleKeyLabel = ""
        hotkeyService.disableSingleKey()
    }

    private var permissionPollTask: Task<Void, Never>?

    /// Polls permission status periodically until granted or timeout.
    private func pollPermissionStatus() {
        permissionPollTask?.cancel()
        permissionPollTask = Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
                if !needsMicPermission, !needsAccessibilityPermission { return }
            }
        }
    }

    private func showError(_ message: String) {
        state = .error(message)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .error = state {
                state = .idle
            }
        }
    }

    // MARK: - Streaming

    /// Text confirmed from previous streaming passes — never changes once set.
    private var confirmedStreamingText = ""
    private var streamingWindowActive = false

    private func startStreamingIfSupported() {
        let resolvedEngine = modelManager.resolveEngine(override: effectiveEngineOverride)
        guard let engine = resolvedEngine, engine.supportsStreaming else { return }

        isStreaming = true
        confirmedStreamingText = ""
        streamingWindowActive = false
        let streamLanguage = effectiveLanguage
        let streamTask = effectiveTask
        let streamEngineOverride = effectiveEngineOverride
        streamingTask = Task { [weak self] in
            guard let self else { return }
            // Initial delay before first streaming attempt
            try? await Task.sleep(for: .seconds(1.5))

            while !Task.isCancelled, self.state == .recording {
                let maxStreamSeconds: TimeInterval = 28
                let buffer = self.audioRecordingService.getRecentBuffer(maxDuration: maxStreamSeconds)
                let bufferDuration = Double(buffer.count) / 16000.0

                // When buffer exceeds window, reset confirmed text so stabilization
                // works against the windowed transcript instead of the full one.
                let totalDuration = self.audioRecordingService.totalBufferDuration
                if totalDuration > maxStreamSeconds, !self.streamingWindowActive {
                    self.streamingWindowActive = true
                    self.confirmedStreamingText = ""
                }

                if bufferDuration > 0.5 {
                    do {
                        let confirmed = self.confirmedStreamingText
                        let result = try await self.modelManager.transcribe(
                            audioSamples: buffer,
                            language: streamLanguage,
                            task: streamTask,
                            engineOverride: streamEngineOverride,
                            onProgress: { [weak self] text in
                                guard let self, !Task.isCancelled else { return false }
                                let stable = Self.stabilizeText(confirmed: confirmed, new: text)
                                DispatchQueue.main.async {
                                    if self.partialText != stable {
                                        self.partialText = stable
                                    }
                                }
                                return true
                            }
                        )
                        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            let stable = Self.stabilizeText(confirmed: confirmed, new: text)
                            if self.partialText != stable {
                                self.partialText = stable
                            }
                            self.confirmedStreamingText = stable
                        }
                    } catch {
                        // Streaming errors are non-fatal; final transcription will still run
                    }
                }

                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func stopStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        confirmedStreamingText = ""
        streamingWindowActive = false
    }

    /// Keeps confirmed text stable and only appends new content.
    nonisolated private static func stabilizeText(confirmed: String, new: String) -> String {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !confirmed.isEmpty else { return new }
        guard !new.isEmpty else { return confirmed }

        // Best case: new text starts with confirmed text
        if new.hasPrefix(confirmed) { return new }

        // Find how far the texts match from the start
        let confirmedChars = Array(confirmed.unicodeScalars)
        let newChars = Array(new.unicodeScalars)
        var matchEnd = 0
        for i in 0..<min(confirmedChars.count, newChars.count) {
            if confirmedChars[i] == newChars[i] {
                matchEnd = i + 1
            } else {
                break
            }
        }

        // If more than half matches, keep confirmed and append the new tail
        if matchEnd > confirmed.count / 2 {
            let newContent = String(new.unicodeScalars.dropFirst(matchEnd))
            return confirmed + newContent
        }

        // Suffix-prefix overlap: new text starts with a suffix of confirmed
        // (happens when the streaming window has shifted forward)
        let minOverlap = min(20, confirmedChars.count / 4)
        let maxShift = min(confirmedChars.count - minOverlap, 150)
        if maxShift > 0 {
            for dropCount in 1...maxShift {
                let suffix = String(confirmed.unicodeScalars.dropFirst(dropCount))
                if new.hasPrefix(suffix) {
                    let newTail = String(new.unicodeScalars.dropFirst(confirmed.unicodeScalars.count - dropCount))
                    return newTail.isEmpty ? confirmed : confirmed + newTail
                }
            }
        }

        // Very different result — accept the new text to avoid freezing the preview
        return new
    }

    // MARK: - Silence Detection

    private func startSilenceDetection() {
        // Only auto-stop in toggle mode, not push-to-talk
        guard hotkeyMode == .toggle else { return }

        silenceCancellable = audioRecordingService.$silenceDuration
            .dropFirst()
            .sink { [weak self] duration in
                DispatchQueue.main.async {
                    guard let self, self.state == .recording else { return }
                    if duration >= self.audioRecordingService.silenceAutoStopDuration {
                        self.audioRecordingService.didAutoStop = true
                        self.stopDictation()
                        self.hotkeyService.cancelDictation()
                    }
                }
            }
    }

    private func stopSilenceDetection() {
        silenceCancellable?.cancel()
        silenceCancellable = nil
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }
}
