import Foundation

// MARK: - Cloud Provider Config

/// Configuration for OpenAI-compatible cloud providers.
/// To add a new provider: add a case to LLMProviderType, add its cloudConfig entry, done.
struct CloudProviderConfig: Sendable {
    let baseURL: String
    let defaultModel: String
    let keychainId: String
    let knownModels: [String]
}

// MARK: - Provider Type

enum LLMProviderType: String, CaseIterable, Identifiable {
    case appleIntelligence
    case groq
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .groq: "Groq"
        case .openai: "OpenAI"
        }
    }

    var isCloudProvider: Bool { cloudConfig != nil }

    /// Cloud provider configuration. Returns nil for non-cloud providers (Apple Intelligence).
    var cloudConfig: CloudProviderConfig? {
        switch self {
        case .appleIntelligence:
            nil
        case .groq:
            CloudProviderConfig(
                baseURL: "https://api.groq.com/openai",
                defaultModel: "llama-3.3-70b-versatile",
                keychainId: "groq",
                knownModels: [
                    "llama-3.3-70b-versatile",
                    "llama-3.1-8b-instant",
                    "openai/gpt-oss-120b",
                    "openai/gpt-oss-20b",
                ]
            )
        case .openai:
            CloudProviderConfig(
                baseURL: "https://api.openai.com",
                defaultModel: "gpt-4.1-nano",
                keychainId: "openai",
                knownModels: [
                    "gpt-5",
                    "gpt-5-mini",
                    "gpt-5-nano",
                    "gpt-4.1",
                    "gpt-4.1-mini",
                    "gpt-4.1-nano",
                    "o4-mini",
                ]
            )
        }
    }
}

// MARK: - Provider Protocol

protocol LLMProvider: Sendable {
    func process(systemPrompt: String, userText: String) async throws -> String
    var isAvailable: Bool { get }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case notAvailable
    case providerError(String)
    case inputTooLong
    case noProviderConfigured
    case noApiKey

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "LLM provider is not available on this device."
        case .providerError(let message):
            "LLM error: \(message)"
        case .inputTooLong:
            "Input text is too long for the selected provider."
        case .noProviderConfigured:
            "No LLM provider configured. Please select a provider in Settings > Prompts."
        case .noApiKey:
            "API key not configured. Please add your API key in Settings > Models."
        }
    }
}
