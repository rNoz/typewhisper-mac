import Foundation
import Combine

@MainActor
final class ModelManagerService: ObservableObject {
    @Published private(set) var modelStatuses: [String: ModelStatus] = [:]
    @Published private(set) var selectedEngine: EngineType
    @Published private(set) var selectedModelId: String?
    @Published private(set) var activeEngine: (any TranscriptionEngine)?

    private let whisperEngine = WhisperEngine()
    private let parakeetEngine = ParakeetEngine()
    private let _speechAnalyzerEngine: (any TranscriptionEngine)?
    let groqEngine = GroqEngine()
    let openAiEngine = OpenAIEngine()

    var cloudEngines: [CloudTranscriptionEngine] { [groqEngine, openAiEngine] }

    private let engineKey = UserDefaultsKeys.selectedEngine
    private let modelKey = UserDefaultsKeys.selectedModelId
    private let loadedModelsKey = UserDefaultsKeys.loadedModelIds

    init() {
        if #available(macOS 26, *) {
            _speechAnalyzerEngine = SpeechAnalyzerEngine()
        } else {
            _speechAnalyzerEngine = nil
        }

        let savedEngine = UserDefaults.standard.string(forKey: engineKey)
            .flatMap { EngineType(rawValue: $0) } ?? .whisper
        self.selectedEngine = savedEngine
        self.selectedModelId = UserDefaults.standard.string(forKey: modelKey)

        // Initialize all models as not downloaded
        for model in ModelInfo.allModels {
            modelStatuses[model.id] = .notDownloaded
        }
    }

    var currentEngine: (any TranscriptionEngine)? {
        activeEngine
    }

    var isEngineLoaded: Bool {
        activeEngine != nil
    }

    func engine(for type: EngineType) -> any TranscriptionEngine {
        switch type {
        case .whisper: return whisperEngine
        case .parakeet: return parakeetEngine
        case .speechAnalyzer: return _speechAnalyzerEngine ?? whisperEngine
        case .groq: return groqEngine
        case .openai: return openAiEngine
        }
    }

    func selectEngine(_ engine: EngineType) {
        selectedEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: engineKey)
    }

    func selectModel(_ modelId: String) {
        selectedModelId = modelId
        UserDefaults.standard.set(modelId, forKey: modelKey)

        if CloudProvider.isCloudModel(modelId) {
            let (provider, model) = CloudProvider.parse(modelId)
            guard let cloudEngine = cloudEngines.first(where: { $0.providerId == provider }),
                  let engineType = EngineType(rawValue: provider) else { return }
            cloudEngine.selectTranscriptionModel(model)
            activeEngine = cloudEngine
            selectEngine(engineType)
        } else if let model = ModelInfo.allModels.first(where: { $0.id == modelId }) {
            let eng = engine(for: model.engineType)
            guard eng.isModelLoaded else { return }
            activeEngine = eng
            selectEngine(model.engineType)
        }
    }

    func downloadAndLoadModel(_ model: ModelInfo) async {
        // Cloud models are instantly "ready" when API key is configured
        if model.isCloud {
            let cloudEngine = engine(for: model.engineType) as? CloudTranscriptionEngine
            guard cloudEngine?.isConfigured == true else {
                modelStatuses[model.id] = .error("API key not configured")
                return
            }
            let (_, modelPart) = CloudProvider.parse(model.id)
            cloudEngine?.selectTranscriptionModel(modelPart)
            modelStatuses[model.id] = .ready
            activeEngine = cloudEngine
            selectEngine(model.engineType)
            selectModel(model.id)
            addToLoadedModels(model.id, engineType: model.engineType)
            return
        }

        let engine = engine(for: model.engineType)

        modelStatuses[model.id] = .downloading(progress: 0)

        // Listen for phase changes from WhisperKit (loading → prewarming)
        if let whisperEngine = engine as? WhisperEngine {
            whisperEngine.onPhaseChange = { [weak self] phase in
                Task { @MainActor [weak self] in
                    self?.modelStatuses[model.id] = .loading(phase: phase)
                }
            }
        }

        do {
            try await engine.loadModel(model) { [weak self] progress, speed in
                Task { @MainActor [weak self] in
                    if progress >= 0.80 {
                        self?.modelStatuses[model.id] = .loading()
                    } else {
                        self?.modelStatuses[model.id] = .downloading(progress: progress, bytesPerSecond: speed)
                    }
                }
            }

            modelStatuses[model.id] = .ready
            activeEngine = engine
            selectEngine(model.engineType)
            selectModel(model.id)
            addToLoadedModels(model.id, engineType: model.engineType)
        } catch {
            modelStatuses[model.id] = .error(error.localizedDescription)
        }
    }

    func loadAllSavedModels() async {
        // Load cloud API keys first
        loadCloudApiKeys()

        var modelIds = UserDefaults.standard.stringArray(forKey: loadedModelsKey) ?? []

        // Migration: if loadedModelIds is empty but selectedModelId exists, seed from it
        if modelIds.isEmpty, let selectedId = selectedModelId {
            modelIds = [selectedId]
            UserDefaults.standard.set(modelIds, forKey: loadedModelsKey)
        }

        let modelsToLoad = modelIds.compactMap { id in
            ModelInfo.allModels.first(where: { $0.id == id })
        }.filter { !$0.isCloud } // Cloud models are handled by loadCloudApiKeys

        if !modelsToLoad.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for model in modelsToLoad {
                    group.addTask {
                        await self.loadSingleModel(model)
                    }
                }
            }
        }

        // Set activeEngine to the selected engine
        if let selectedId = selectedModelId,
           let selectedModel = ModelInfo.allModels.first(where: { $0.id == selectedId }) {
            let eng = engine(for: selectedModel.engineType)
            if eng.isModelLoaded {
                activeEngine = eng
            }
        }
    }

    private func loadSingleModel(_ model: ModelInfo) async {
        let engine = engine(for: model.engineType)

        // Already loaded
        if engine.isModelLoaded {
            modelStatuses[model.id] = .ready
            return
        }

        modelStatuses[model.id] = .downloading(progress: 0)

        if let whisperEngine = engine as? WhisperEngine {
            whisperEngine.onPhaseChange = { [weak self] phase in
                Task { @MainActor [weak self] in
                    self?.modelStatuses[model.id] = .loading(phase: phase)
                }
            }
        }

        do {
            try await engine.loadModel(model) { [weak self] progress, speed in
                Task { @MainActor [weak self] in
                    if progress >= 0.80 {
                        self?.modelStatuses[model.id] = .loading()
                    } else {
                        self?.modelStatuses[model.id] = .downloading(progress: progress, bytesPerSecond: speed)
                    }
                }
            }
            modelStatuses[model.id] = .ready
        } catch {
            modelStatuses[model.id] = .error(error.localizedDescription)
            removeFromLoadedModels(model.id)
        }
    }

    func deleteModel(_ model: ModelInfo) {
        let engine = engine(for: model.engineType)
        engine.unloadModel()
        modelStatuses[model.id] = .notDownloaded
        removeFromLoadedModels(model.id)

        if selectedModelId == model.id {
            // Fall back to another loaded engine
            if let fallback = findLoadedFallback(excluding: model.engineType) {
                selectEngine(fallback.engineType)
                selectModel(fallback.id)
                activeEngine = self.engine(for: fallback.engineType)
            } else {
                selectedModelId = nil
                UserDefaults.standard.removeObject(forKey: modelKey)
                activeEngine = nil
            }
        }
    }

    private func findLoadedFallback(excluding: EngineType) -> ModelInfo? {
        let remainingIds = UserDefaults.standard.stringArray(forKey: loadedModelsKey) ?? []
        return remainingIds.compactMap { id in
            ModelInfo.allModels.first(where: { $0.id == id })
        }.first { $0.engineType != excluding && engine(for: $0.engineType).isModelLoaded }
    }

    private func addToLoadedModels(_ modelId: String, engineType: EngineType) {
        var ids = UserDefaults.standard.stringArray(forKey: loadedModelsKey) ?? []
        // Remove any existing model of the same engine type (only 1 per engine)
        let sameEngineIds = ModelInfo.allModels
            .filter { $0.engineType == engineType }
            .map(\.id)
        ids.removeAll { sameEngineIds.contains($0) }
        ids.append(modelId)
        UserDefaults.standard.set(ids, forKey: loadedModelsKey)
    }

    private func removeFromLoadedModels(_ modelId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: loadedModelsKey) ?? []
        ids.removeAll { $0 == modelId }
        UserDefaults.standard.set(ids, forKey: loadedModelsKey)
    }

    // MARK: - Cloud Provider Configuration

    func configureCloudProvider(_ type: EngineType, apiKey: String) {
        guard let cloudEngine = cloudEngines.first(where: { $0.engineType == type }) else { return }
        cloudEngine.configure(apiKey: apiKey)

        // Mark all models for this provider as ready
        let providerModels = ModelInfo.models(for: type)
        for model in providerModels {
            modelStatuses[model.id] = .ready
        }

        // Auto-select first model for this provider
        if let firstModel = providerModels.first {
            let (_, modelPart) = CloudProvider.parse(firstModel.id)
            cloudEngine.selectTranscriptionModel(modelPart)
            activeEngine = cloudEngine
            selectEngine(type)
            selectModel(firstModel.id)
            addToLoadedModels(firstModel.id, engineType: type)
        }
    }

    func removeCloudProvider(_ type: EngineType) {
        guard let cloudEngine = cloudEngines.first(where: { $0.engineType == type }) else { return }
        cloudEngine.removeApiKey()

        // Mark all models for this provider as not downloaded
        for model in ModelInfo.models(for: type) {
            modelStatuses[model.id] = .notDownloaded
            removeFromLoadedModels(model.id)
        }

        // If current engine was this cloud provider, clear it
        if selectedEngine == type {
            if let fallback = findLoadedFallback(excluding: type) {
                selectEngine(fallback.engineType)
                selectModel(fallback.id)
                activeEngine = self.engine(for: fallback.engineType)
            } else {
                selectedModelId = nil
                UserDefaults.standard.removeObject(forKey: modelKey)
                activeEngine = nil
            }
        }
    }

    func loadCloudApiKeys() {
        for cloudEngine in cloudEngines {
            cloudEngine.loadApiKey()
            if cloudEngine.isConfigured {
                for model in ModelInfo.models(for: cloudEngine.engineType) {
                    modelStatuses[model.id] = .ready
                }
            }
        }

        // Restore selected cloud model
        if let selectedId = selectedModelId, CloudProvider.isCloudModel(selectedId) {
            let (provider, model) = CloudProvider.parse(selectedId)
            if let cloudEngine = cloudEngines.first(where: { $0.providerId == provider }),
               cloudEngine.isConfigured {
                cloudEngine.selectTranscriptionModel(model)
                activeEngine = cloudEngine
            }
        }
    }

    func status(for model: ModelInfo) -> ModelStatus {
        modelStatuses[model.id] ?? .notDownloaded
    }

    func resolvedModelDisplayName(engineOverride: EngineType? = nil, cloudModelOverride: String? = nil) -> String? {
        if let override = engineOverride {
            guard let cloudEngine = engine(for: override) as? CloudTranscriptionEngine else {
                return ModelInfo.models(for: override).first(where: { status(for: $0) == .ready })?.displayName
            }
            if let cloudModel = cloudModelOverride,
               let info = cloudEngine.transcriptionModels.first(where: { $0.id == cloudModel }) {
                return info.displayName
            }
            return cloudEngine.selectedModel?.displayName
        }

        guard let selectedId = selectedModelId else { return nil }
        if CloudProvider.isCloudModel(selectedId) {
            let (provider, model) = CloudProvider.parse(selectedId)
            if let cloudEngine = cloudEngines.first(where: { $0.providerId == provider }),
               let info = cloudEngine.transcriptionModels.first(where: { $0.id == model }) {
                return info.displayName
            }
        }
        return ModelInfo.allModels.first(where: { $0.id == selectedId })?.displayName
    }

    func resolveEngine(override: EngineType?, cloudModelOverride: String? = nil) -> (any TranscriptionEngine)? {
        guard let override else { return activeEngine }
        let e = engine(for: override)
        // For cloud engines: select model BEFORE checking isModelLoaded
        if let cloudEngine = e as? CloudTranscriptionEngine {
            if let cloudModel = cloudModelOverride {
                cloudEngine.selectTranscriptionModel(cloudModel)
            } else if cloudEngine.selectedModel == nil,
                      let firstModel = cloudEngine.transcriptionModels.first {
                cloudEngine.selectTranscriptionModel(firstModel.id)
            }
        }
        guard e.isModelLoaded else { return activeEngine }
        return e
    }

    func transcribe(
        audioSamples: [Float],
        language: String?,
        task: TranscriptionTask,
        engineOverride: EngineType? = nil,
        cloudModelOverride: String? = nil,
        prompt: String? = nil
    ) async throws -> TranscriptionResult {
        guard let engine = resolveEngine(override: engineOverride, cloudModelOverride: cloudModelOverride) else {
            throw TranscriptionEngineError.modelNotLoaded
        }
        return try await engine.transcribe(
            audioSamples: audioSamples,
            language: language,
            task: task,
            prompt: prompt
        )
    }

    func transcribe(
        audioSamples: [Float],
        language: String?,
        task: TranscriptionTask,
        engineOverride: EngineType? = nil,
        cloudModelOverride: String? = nil,
        prompt: String? = nil,
        onProgress: @Sendable @escaping (String) -> Bool
    ) async throws -> TranscriptionResult {
        guard let engine = resolveEngine(override: engineOverride, cloudModelOverride: cloudModelOverride) else {
            throw TranscriptionEngineError.modelNotLoaded
        }
        return try await engine.transcribe(
            audioSamples: audioSamples,
            language: language,
            task: task,
            prompt: prompt,
            onProgress: onProgress
        )
    }
}
