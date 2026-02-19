import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TypeWhisper", category: "PromptProcessingService")

@MainActor
class PromptProcessingService: ObservableObject {
    @Published var selectedProviderType: LLMProviderType {
        didSet { UserDefaults.standard.set(selectedProviderType.rawValue, forKey: "llmProviderType") }
    }
    @Published var selectedCloudModel: String {
        didSet { UserDefaults.standard.set(selectedCloudModel, forKey: "llmCloudModel") }
    }

    private var providers: [LLMProviderType: LLMProvider] = [:]

    var isAppleIntelligenceAvailable: Bool {
        if #available(macOS 26, *) {
            return providers[.appleIntelligence]?.isAvailable ?? false
        }
        return false
    }

    var availableProviders: [LLMProviderType] {
        LLMProviderType.allCases.filter { type in
            if type == .appleIntelligence {
                if #available(macOS 26, *) { return true }
                return false
            }
            return true
        }
    }

    var isCurrentProviderReady: Bool {
        providers[selectedProviderType]?.isAvailable ?? false
    }

    func isProviderReady(_ type: LLMProviderType) -> Bool {
        providers[type]?.isAvailable ?? false
    }

    init() {
        let savedType = UserDefaults.standard.string(forKey: "llmProviderType")
            .flatMap { LLMProviderType(rawValue: $0) }
        let providerType = savedType ?? .appleIntelligence
        self.selectedProviderType = providerType

        // Validate saved model matches current provider's known models
        let savedModel = UserDefaults.standard.string(forKey: "llmCloudModel") ?? ""
        if let config = providerType.cloudConfig {
            self.selectedCloudModel = config.knownModels.contains(savedModel) ? savedModel : config.defaultModel
        } else {
            self.selectedCloudModel = ""
        }

        setupProviders()
    }

    private func setupProviders() {
        for type in LLMProviderType.allCases {
            if type == .appleIntelligence {
                if #available(macOS 26, *) {
                    providers[type] = FoundationModelsProvider()
                }
            } else if let config = type.cloudConfig {
                let model = (selectedProviderType == type && !selectedCloudModel.isEmpty)
                    ? selectedCloudModel
                    : config.defaultModel
                providers[type] = CloudLLMProvider(config: config, model: model)
            }
        }
    }

    func refreshCloudProviders() {
        for type in LLMProviderType.allCases {
            guard let config = type.cloudConfig else { continue }
            let model = (selectedProviderType == type && !selectedCloudModel.isEmpty)
                ? selectedCloudModel
                : config.defaultModel
            providers[type] = CloudLLMProvider(config: config, model: model)
        }
    }

    func process(prompt: String, text: String, providerOverride: LLMProviderType? = nil, cloudModelOverride: String? = nil) async throws -> String {
        let effectiveType = providerOverride ?? selectedProviderType

        let provider: LLMProvider
        if let config = effectiveType.cloudConfig {
            // Always create a fresh cloud provider with the current model selection
            let model = cloudModelOverride ?? selectedCloudModel
            provider = CloudLLMProvider(config: config, model: model.isEmpty ? config.defaultModel : model)
        } else if let existing = providers[effectiveType] {
            provider = existing
        } else {
            throw LLMError.noProviderConfigured
        }

        guard provider.isAvailable else {
            if effectiveType == .appleIntelligence {
                throw LLMError.notAvailable
            } else {
                throw LLMError.noApiKey
            }
        }

        logger.info("Processing prompt with \(effectiveType.rawValue)")
        let result = try await provider.process(systemPrompt: prompt, userText: text)
        logger.info("Prompt processing complete, result length: \(result.count)")
        return result
    }
}
