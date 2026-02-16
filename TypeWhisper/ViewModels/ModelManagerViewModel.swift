import Foundation
import Combine

@MainActor
final class ModelManagerViewModel: ObservableObject {
    nonisolated(unsafe) static var _shared: ModelManagerViewModel?
    static var shared: ModelManagerViewModel {
        guard let instance = _shared else {
            fatalError("ModelManagerViewModel not initialized")
        }
        return instance
    }

    @Published var selectedEngine: EngineType
    @Published var models: [ModelInfo] = []
    @Published var modelStatuses: [String: ModelStatus] = [:]
    @Published var selectedModelId: String?

    private let modelManager: ModelManagerService
    private var cancellables = Set<AnyCancellable>()

    init(modelManager: ModelManagerService) {
        self.modelManager = modelManager
        self.selectedModelId = modelManager.selectedModelId
        if modelManager.selectedEngine.isCloud {
            let fallback = EngineType.availableCases.first ?? .whisper
            self.selectedEngine = fallback
            self.models = ModelInfo.models(for: fallback)
        } else {
            self.selectedEngine = modelManager.selectedEngine
            self.models = ModelInfo.models(for: modelManager.selectedEngine)
        }

        modelManager.$selectedEngine
            .dropFirst()
            .sink { [weak self] engine in
                if engine.isCloud { return }
                DispatchQueue.main.async {
                    self?.selectedEngine = engine
                    self?.models = ModelInfo.models(for: engine)
                }
            }
            .store(in: &cancellables)

        modelManager.$modelStatuses
            .dropFirst()
            .sink { [weak self] statuses in
                DispatchQueue.main.async {
                    self?.modelStatuses = statuses
                }
            }
            .store(in: &cancellables)

        modelManager.$selectedModelId
            .dropFirst()
            .sink { [weak self] modelId in
                DispatchQueue.main.async {
                    self?.selectedModelId = modelId
                }
            }
            .store(in: &cancellables)
    }

    func selectEngine(_ engine: EngineType) {
        modelManager.selectEngine(engine)
        models = ModelInfo.models(for: engine)
    }

    func downloadModel(_ model: ModelInfo) {
        Task {
            await modelManager.downloadAndLoadModel(model)
        }
    }

    func deleteModel(_ model: ModelInfo) {
        modelManager.deleteModel(model)
    }

    func status(for model: ModelInfo) -> ModelStatus {
        modelStatuses[model.id] ?? .notDownloaded
    }

    var isModelReady: Bool {
        modelManager.activeEngine?.isModelLoaded ?? false
    }

    var readyModels: [ModelInfo] {
        ModelInfo.allModels.filter { modelStatuses[$0.id]?.isReady == true }
    }

    func selectDefaultModel(_ modelId: String) {
        modelManager.selectModel(modelId)
    }

    var activeModelName: String? {
        guard let modelId = selectedModelId else { return nil }
        return ModelInfo.allModels.first { $0.id == modelId }?.displayName
    }

    var activeEngineName: String? {
        guard let modelId = selectedModelId,
              let model = ModelInfo.allModels.first(where: { $0.id == modelId }) else { return nil }
        return model.engineType.displayName
    }

    // MARK: - Cloud Provider

    func setApiKey(_ key: String, for provider: EngineType) {
        modelManager.configureCloudProvider(provider, apiKey: key)
    }

    func removeApiKey(for provider: EngineType) {
        modelManager.removeCloudProvider(provider)
    }

    func isCloudProviderConfigured(_ provider: EngineType) -> Bool {
        modelManager.cloudEngines.first { $0.engineType == provider }?.isConfigured ?? false
    }

    func apiKeyForProvider(_ provider: EngineType) -> String? {
        modelManager.cloudEngines.first { $0.engineType == provider }?.apiKey
    }

    func selectCloudModel(_ modelId: String, provider: EngineType) {
        let fullId = CloudProvider.fullId(provider: provider.rawValue, model: modelId)
        modelManager.selectEngine(provider)
        modelManager.selectModel(fullId)
    }

    func selectedCloudModelId(for provider: EngineType) -> String? {
        // First check if this provider is the globally active one
        if let selectedId = modelManager.selectedModelId,
           CloudProvider.isCloudModel(selectedId) {
            let (providerStr, model) = CloudProvider.parse(selectedId)
            if providerStr == provider.rawValue {
                return model
            }
        }
        // Fallback: check the engine's own selected model
        if let cloudEngine = modelManager.cloudEngines.first(where: { $0.engineType == provider }),
           let selected = cloudEngine.selectedModel {
            return selected.id
        }
        return nil
    }

    func validateApiKey(_ key: String, for provider: EngineType) async -> Bool {
        guard let cloudEngine = modelManager.cloudEngines.first(where: { $0.engineType == provider }) else {
            return false
        }
        return await cloudEngine.validateApiKey(key)
    }

    func cloudModels(for provider: EngineType) -> [CloudModelInfo] {
        modelManager.cloudEngines.first { $0.engineType == provider }?.transcriptionModels ?? []
    }
}
