import Foundation

enum EngineType: String, CaseIterable, Identifiable, Codable {
    case whisper
    case parakeet
    case speechAnalyzer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whisper: "WhisperKit"
        case .parakeet: "Parakeet (FluidAudio)"
        case .speechAnalyzer: String(localized: "Apple Speech")
        }
    }

    var supportsStreaming: Bool {
        switch self {
        case .whisper: true
        case .parakeet: false
        case .speechAnalyzer: true
        }
    }

    var supportsTranslation: Bool {
        switch self {
        case .whisper: true
        case .parakeet: false
        case .speechAnalyzer: false
        }
    }

    /// Local engine cases shown in the engine picker
    static var availableCases: [EngineType] {
        var cases: [EngineType] = []
        if #available(macOS 26, *) {
            cases.append(.speechAnalyzer)
        }
        cases.append(contentsOf: [.parakeet, .whisper])
        return cases
    }
}

// MARK: - Cloud/Plugin Provider ID Utilities

enum CloudProvider {
    /// Check if a model ID uses the "provider:model" format (plugin engines)
    static func isCloudModel(_ id: String) -> Bool {
        id.contains(":")
    }

    static func parse(_ id: String) -> (provider: String, model: String) {
        let parts = id.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return (id, "") }
        return (String(parts[0]), String(parts[1]))
    }

    static func fullId(provider: String, model: String) -> String {
        "\(provider):\(model)"
    }
}
