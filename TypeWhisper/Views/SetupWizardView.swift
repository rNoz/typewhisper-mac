import SwiftUI

struct SetupWizardView: View {
    @ObservedObject private var dictation = DictationViewModel.shared
    @ObservedObject private var modelManager = ModelManagerViewModel.shared
    @ObservedObject private var audioDevice = ServiceContainer.shared.audioDeviceService
    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            navigation
        }
        .frame(minHeight: 350)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(String(localized: "Setup"))
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Text(String(localized: "Step \(currentStep + 1) of \(totalSteps)"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding()
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            switch currentStep {
            case 0: permissionsStep
            case 1: engineModelStep
            case 2: cloudProviderStep
            case 3: hotkeyStep
            default: EmptyView()
            }
        }
        .padding()
    }

    // MARK: - Step 1: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Microphone access is required for dictation."))
                .font(.callout)
                .foregroundStyle(.secondary)

            permissionRow(
                label: String(localized: "Microphone"),
                iconGranted: "mic.fill",
                iconMissing: "mic.slash",
                isGranted: !dictation.needsMicPermission
            ) {
                dictation.requestMicPermission()
            }

            Text(String(localized: "Accessibility access is required to paste text into other apps."))
                .font(.callout)
                .foregroundStyle(.secondary)

            permissionRow(
                label: String(localized: "Accessibility"),
                iconGranted: "lock.shield.fill",
                iconMissing: "lock.shield",
                isGranted: !dictation.needsAccessibilityPermission
            ) {
                dictation.requestAccessibilityPermission()
            }

            if !dictation.needsMicPermission {
                Divider()

                Text(String(localized: "Select your preferred microphone:"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "Microphone"), selection: $audioDevice.selectedDeviceUID) {
                    Text(String(localized: "System Default")).tag(nil as String?)
                    Divider()
                    ForEach(audioDevice.inputDevices) { device in
                        Text(device.name).tag(device.uid as String?)
                    }
                }

                if audioDevice.isPreviewActive {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.quaternary)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.green.gradient)
                                    .frame(width: max(0, geo.size.width * CGFloat(audioDevice.previewAudioLevel)))
                                    .animation(.easeOut(duration: 0.08), value: audioDevice.previewAudioLevel)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 4)
                }

                Button(audioDevice.isPreviewActive
                    ? String(localized: "Stop Preview")
                    : String(localized: "Test Microphone")
                ) {
                    if audioDevice.isPreviewActive {
                        audioDevice.stopPreview()
                    } else {
                        audioDevice.startPreview()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func permissionRow(
        label: String,
        iconGranted: String,
        iconMissing: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(label, systemImage: isGranted ? iconGranted : iconMissing)
                .foregroundStyle(isGranted ? .green : .orange)

            Spacer()

            if isGranted {
                Text(String(localized: "Granted"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(String(localized: "Grant Access")) {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    // MARK: - Step 2: Engine & Model

    private var engineModelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Select an engine and download a model to get started."))
                .font(.callout)
                .foregroundStyle(.secondary)

            // Engine picker
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Engine"))
                    .font(.headline)

                Picker(String(localized: "Engine"), selection: Binding(
                    get: { modelManager.selectedEngine },
                    set: { modelManager.selectEngine($0) }
                )) {
                    ForEach(EngineType.availableCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                engineDescription
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Model list — recommended first
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Models"))
                    .font(.headline)

                let sorted = modelManager.models.sorted { $0.isRecommended && !$1.isRecommended }
                ForEach(sorted) { model in
                    ModelRow(model: model, status: modelManager.status(for: model)) {
                        modelManager.downloadModel(model)
                    } onDelete: {
                        modelManager.deleteModel(model)
                    }
                }
            }
        }
    }

    private var engineDescription: Text {
        switch modelManager.selectedEngine {
        case .speechAnalyzer:
            Text(String(localized: "Apple Speech — on-device, no download required. Recommended for most users."))
        case .parakeet:
            Text(String(localized: "Parakeet — extremely fast on Apple Silicon, 25 European languages."))
        case .whisper:
            Text(String(localized: "WhisperKit — 99+ languages, supports streaming and translation to English."))
        case .groq, .openai:
            Text(String(localized: "Cloud — requires an API key. Fast transcription via cloud API."))
        }
    }

    // MARK: - Step 3: Cloud Provider (Optional)

    private var cloudProviderStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Optionally configure a cloud provider for faster transcription via API."))
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(EngineType.cloudCases) { provider in
                CloudProviderSection(provider: provider, viewModel: modelManager)
            }

            Text(String(localized: "API keys are stored securely in the Keychain"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(String(localized: "You can skip this step and configure cloud providers later in Settings."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 4: Hotkey

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Choose how to trigger dictation."))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HotkeyRecorderView(
                    label: dictation.hybridHotkeyLabel,
                    title: String(localized: "Hybrid"),
                    onRecord: { hotkey in
                        if let conflict = dictation.isHotkeyAssigned(hotkey, excluding: .hybrid) {
                            dictation.clearHotkey(for: conflict)
                        }
                        dictation.setHotkey(hotkey, for: .hybrid)
                    },
                    onClear: { dictation.clearHotkey(for: .hybrid) }
                )
                Text(String(localized: "Short press to toggle, hold to push-to-talk."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HotkeyRecorderView(
                    label: dictation.pttHotkeyLabel,
                    title: String(localized: "Push-to-Talk"),
                    onRecord: { hotkey in
                        if let conflict = dictation.isHotkeyAssigned(hotkey, excluding: .pushToTalk) {
                            dictation.clearHotkey(for: conflict)
                        }
                        dictation.setHotkey(hotkey, for: .pushToTalk)
                    },
                    onClear: { dictation.clearHotkey(for: .pushToTalk) }
                )
                Text(String(localized: "Hold to record, release to stop."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HotkeyRecorderView(
                    label: dictation.toggleHotkeyLabel,
                    title: String(localized: "Toggle"),
                    onRecord: { hotkey in
                        if let conflict = dictation.isHotkeyAssigned(hotkey, excluding: .toggle) {
                            dictation.clearHotkey(for: conflict)
                        }
                        dictation.setHotkey(hotkey, for: .toggle)
                    },
                    onClear: { dictation.clearHotkey(for: .toggle) }
                )
                Text(String(localized: "Press to start, press again to stop."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        }
    }

    // MARK: - Navigation

    private var navigation: some View {
        HStack {
            if currentStep > 0 {
                Button(String(localized: "Back")) {
                    withAnimation { currentStep -= 1 }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button(String(localized: "Next")) {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == 1 && !hasAnyModelReady)
            } else {
                Button(String(localized: "Finish")) {
                    HomeViewModel.shared.completeSetupWizard()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var hasAnyModelReady: Bool {
        ModelInfo.allModels.contains { model in
            if case .ready = modelManager.status(for: model) {
                return true
            }
            return false
        }
    }
}
