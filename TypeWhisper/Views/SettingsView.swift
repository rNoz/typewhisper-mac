import SwiftUI
import KeyboardShortcuts

enum SettingsTab: Hashable {
    case home, general, models, dictation
    case fileTranscription, history, dictionary, snippets, profiles, advanced
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .home
    @ObservedObject private var fileTranscription = FileTranscriptionViewModel.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsMainTabs()
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 700, idealWidth: 750, minHeight: 550, idealHeight: 600)
        .onAppear { navigateToFileTranscriptionIfNeeded() }
        .onChange(of: fileTranscription.showFilePickerFromMenu) { _, _ in
            navigateToFileTranscriptionIfNeeded()
        }
    }

    private func navigateToFileTranscriptionIfNeeded() {
        if fileTranscription.showFilePickerFromMenu {
            selectedTab = .fileTranscription
        }
    }
}

private struct SettingsMainTabs: TabContent {
    var body: some TabContent<SettingsTab> {
        Tab(String(localized: "Home"), systemImage: "house", value: SettingsTab.home) {
            HomeSettingsView()
        }
        Tab(String(localized: "General"), systemImage: "gear", value: SettingsTab.general) {
            GeneralSettingsView()
        }
        Tab(String(localized: "Models"), systemImage: "cpu", value: SettingsTab.models) {
            ModelManagerView()
        }
        Tab(String(localized: "Dictation"), systemImage: "mic.fill", value: SettingsTab.dictation) {
            DictationSettingsView()
        }
        Tab(String(localized: "File Transcription"), systemImage: "doc.text", value: SettingsTab.fileTranscription) {
            FileTranscriptionView()
        }
        Tab(String(localized: "History"), systemImage: "clock.arrow.circlepath", value: SettingsTab.history) {
            HistoryView()
        }
        SettingsExtraTabs()
    }
}

private struct SettingsExtraTabs: TabContent {
    var body: some TabContent<SettingsTab> {
        Tab(String(localized: "Dictionary"), systemImage: "book.closed", value: SettingsTab.dictionary) {
            DictionarySettingsView()
        }
        Tab(String(localized: "Snippets"), systemImage: "text.badge.plus", value: SettingsTab.snippets) {
            SnippetsSettingsView()
        }
        Tab(String(localized: "Profiles"), systemImage: "person.crop.rectangle.stack", value: SettingsTab.profiles) {
            ProfilesSettingsView()
        }
        Tab(String(localized: "Advanced"), systemImage: "gearshape.2", value: SettingsTab.advanced) {
            AdvancedSettingsView()
        }
    }
}

struct DictationSettingsView: View {
    @ObservedObject private var dictation = DictationViewModel.shared

    var body: some View {
        Form {
            Section(String(localized: "Hotkey")) {
                Picker(String(localized: "Mode"), selection: Binding(
                    get: { dictation.singleKeyMode },
                    set: { newValue in
                        if !newValue {
                            dictation.disableSingleKey()
                        } else {
                            dictation.singleKeyMode = true
                        }
                    }
                )) {
                    Text(String(localized: "Key Combination")).tag(false)
                    Text(String(localized: "Single Key")).tag(true)
                }
                .pickerStyle(.segmented)

                if dictation.singleKeyMode {
                    SingleKeyRecorderView(
                        label: dictation.singleKeyLabel,
                        onRecord: { code, isFn in
                            dictation.setSingleKey(code: code, isFn: isFn)
                        }
                    )
                } else {
                    KeyboardShortcuts.Recorder(String(localized: "Dictation shortcut"), name: .toggleDictation)
                }

                Text(String(localized: "Quick press: toggle mode (press again to stop). Hold 1+ seconds: push-to-talk (release to stop)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Permissions")) {
                HStack {
                    Label(
                        String(localized: "Microphone"),
                        systemImage: dictation.needsMicPermission ? "mic.slash" : "mic.fill"
                    )
                    .foregroundStyle(dictation.needsMicPermission ? .orange : .green)

                    Spacer()

                    if dictation.needsMicPermission {
                        Button(String(localized: "Grant Access")) {
                            dictation.requestMicPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text(String(localized: "Granted"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label(
                        String(localized: "Accessibility"),
                        systemImage: dictation.needsAccessibilityPermission ? "lock.shield" : "lock.shield.fill"
                    )
                    .foregroundStyle(dictation.needsAccessibilityPermission ? .orange : .green)

                    Spacer()

                    if dictation.needsAccessibilityPermission {
                        Button(String(localized: "Grant Access")) {
                            dictation.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text(String(localized: "Granted"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String(localized: "Behavior")) {
                Toggle(String(localized: "Whisper Mode"), isOn: $dictation.whisperModeEnabled)

                Text(String(localized: "Boosts microphone gain for quiet speech. Useful when you can't speak loudly."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "Transcribed text is automatically pasted into the active application using the clipboard. The previous clipboard content is restored after pasting."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, minHeight: 300)
    }
}

// MARK: - Single Key Recorder

struct SingleKeyRecorderView: View {
    let label: String
    let onRecord: (UInt16, Bool) -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(String(localized: "Dictation key"))
            Spacer()
            Button {
                startRecording()
            } label: {
                if isRecording {
                    Text(String(localized: "Press a key…"))
                        .foregroundStyle(.orange)
                } else if label.isEmpty {
                    Text(String(localized: "Record Key"))
                } else {
                    HStack(spacing: 4) {
                        Text(label)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .onTapGesture {
                                onRecord(0, false)
                            }
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                if event.modifierFlags.contains(.function) {
                    finishRecording(code: 0, isFn: true)
                    return nil
                }
                // Capture modifier-only keys (Command, Shift, Option, Control)
                let modifierKeyCodes: Set<UInt16> = [0x37, 0x36, 0x38, 0x3C, 0x3A, 0x3D, 0x3B, 0x3E]
                if modifierKeyCodes.contains(event.keyCode) {
                    finishRecording(code: event.keyCode, isFn: false)
                    return nil
                }
            }
            if event.type == .keyDown {
                finishRecording(code: event.keyCode, isFn: false)
                return nil
            }
            return event
        }
    }

    private func finishRecording(code: UInt16, isFn: Bool) {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        onRecord(code, isFn)
    }
}
