import SwiftUI
import TypeWhisperPluginSDK

struct ModelManagerView: View {
    @ObservedObject private var viewModel = ModelManagerViewModel.shared
    @ObservedObject private var pluginManager = PluginManager.shared
    @State private var selectedSection: ModelSection = .localModels

    private enum ModelSection: String, CaseIterable {
        case localModels
        case cloudProvider
    }

    private var hasPluginProviders: Bool {
        !pluginManager.loadedPlugins.isEmpty &&
        pluginManager.loadedPlugins.contains { $0.instance is TranscriptionEnginePlugin }
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasPluginProviders {
                Picker(String(localized: "Section"), selection: $selectedSection) {
                    Text(String(localized: "Local Models")).tag(ModelSection.localModels)
                    Text(String(localized: "Cloud Provider")).tag(ModelSection.cloudProvider)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection {
                    case .localModels:
                        // Engine Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Engine"))
                                .font(.headline)

                            Picker(String(localized: "Engine"), selection: Binding(
                                get: { viewModel.selectedEngine },
                                set: { viewModel.selectEngine($0) }
                            )) {
                                ForEach(EngineType.availableCases) { engine in
                                    Text(engine.displayName).tag(engine)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Text(engineDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        // Local Models
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Models"))
                                .font(.headline)

                            ForEach(viewModel.models) { model in
                                ModelRow(model: model, status: viewModel.status(for: model)) {
                                    viewModel.downloadModel(model)
                                } onDelete: {
                                    viewModel.deleteModel(model)
                                }
                            }
                        }

                    case .cloudProvider:
                        let engines = viewModel.pluginTranscriptionEngines
                        if engines.isEmpty {
                            ContentUnavailableView {
                                Label(String(localized: "No Cloud Providers"), systemImage: "cloud")
                            } description: {
                                Text(String(localized: "Install transcription plugins to add cloud providers like Groq or OpenAI."))
                            }
                        } else {
                            Text(String(localized: "Cloud transcription providers are managed through plugins. Configure API keys in the plugin settings."))
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            ForEach(engines, id: \.providerId) { engine in
                                PluginProviderSection(engine: engine, viewModel: viewModel)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private var engineDescription: String {
        switch viewModel.selectedEngine {
        case .whisper:
            String(localized: "WhisperKit - 99+ languages, streaming support, translation to English")
        case .parakeet:
            String(localized: "Parakeet - 25 European languages, extremely fast on Apple Silicon")
        case .speechAnalyzer:
            String(localized: "Apple Speech - system-managed models, streaming support, ~40 languages")
        }
    }
}

// MARK: - Plugin Provider Section

struct PluginProviderSection: View {
    let engine: TranscriptionEnginePlugin
    @ObservedObject var viewModel: ModelManagerViewModel

    private var isActive: Bool {
        if let selectedId = viewModel.selectedModelId,
           CloudProvider.isCloudModel(selectedId) {
            let (providerId, _) = CloudProvider.parse(selectedId)
            return providerId == engine.providerId
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(engine.providerDisplayName)
                    .font(.body.weight(.medium))

                if isActive {
                    Text(String(localized: "Active"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }

                Spacer()

                if engine.isConfigured {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(String(localized: "Configured"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(String(localized: "Not Configured"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !engine.isConfigured {
                Text(String(localized: "Configure this provider in Settings > Integrations."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Model list
                let models = engine.transcriptionModels
                let selectedModelId = viewModel.selectedPluginModelId(for: engine.providerId)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Available Models"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(models, id: \.id) { model in
                        HStack(spacing: 6) {
                            Text(model.displayName)
                                .font(.callout)

                            Spacer()

                            if model.id == selectedModelId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                            }

                            Button(String(localized: "Select")) {
                                viewModel.selectPluginModel(model.id, providerId: engine.providerId)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }
}

struct ModelRow: View {
    let model: ModelInfo
    let status: ModelStatus
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body.weight(.medium))
                    if model.isRecommended {
                        Text(String(localized: "Recommended"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 8) {
                    Text(model.sizeDescription)
                    Text(String(localized: "\(model.languageCount) languages"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            statusView
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .notDownloaded:
            Button(String(localized: "Download")) {
                onDownload()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(let progress, let bytesPerSecond):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 80)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                if let speed = bytesPerSecond, speed > 0 {
                    Text(Self.formatSpeed(speed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

        case .loading(let phase):
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(Self.phaseText(phase))
                        .font(.caption)
                }
                Text(String(localized: "First launch takes a few minutes. Subsequent launches are fast."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(localized: "Ready"))
                    .font(.caption)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

        case .error(let message):
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(String(localized: "Error"))
                        .font(.caption)
                }
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(String(localized: "Retry")) {
                    onDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    private static func phaseText(_ phase: String?) -> String {
        switch phase {
        case "prewarming":
            String(localized: "Optimizing for Neural Engine...")
        case "loading":
            String(localized: "Loading model...")
        default:
            String(localized: "Loading...")
        }
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let mbps = bytesPerSecond / (1024 * 1024)
        if mbps >= 1 {
            return String(format: "%.1f MB/s", mbps)
        } else {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
    }
}
