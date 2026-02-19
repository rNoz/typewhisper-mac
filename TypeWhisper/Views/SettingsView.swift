import SwiftUI

enum SettingsTab: Hashable {
    case home, general, models, dictation
    case fileTranscription, history, dictionary, snippets, profiles, prompts, advanced
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
        Tab(String(localized: "Prompts"), systemImage: "sparkles", value: SettingsTab.prompts) {
            PromptActionsSettingsView()
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
            Section(String(localized: "Hotkeys")) {
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

            Section(String(localized: "Prompt Palette")) {
                HotkeyRecorderView(
                    label: dictation.promptPaletteHotkeyLabel,
                    title: String(localized: "Palette shortcut"),
                    onRecord: { hotkey in
                        if let conflict = dictation.isHotkeyAssigned(hotkey, excluding: .promptPalette) {
                            dictation.clearHotkey(for: conflict)
                        }
                        dictation.setHotkey(hotkey, for: .promptPalette)
                    },
                    onClear: { dictation.clearHotkey(for: .promptPalette) }
                )

                Text(String(localized: "Select text in any app, press the shortcut, and choose a prompt to process the text."))
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

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: View {
    let label: String
    var title: String = String(localized: "Dictation shortcut")
    let onRecord: (UnifiedHotkey) -> Void
    let onClear: () -> Void

    @State private var isRecording = false
    @State private var pendingModifiers: NSEvent.ModifierFlags = []
    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                startRecording()
            } label: {
                if isRecording {
                    Text(pendingModifierString.isEmpty
                        ? String(localized: "Press a key…")
                        : pendingModifierString)
                        .foregroundStyle(.orange)
                } else if label.isEmpty {
                    Text(String(localized: "Record Shortcut"))
                } else {
                    HStack(spacing: 4) {
                        Text(label)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .onTapGesture {
                                onClear()
                            }
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var pendingModifierString: String {
        var parts: [String] = []
        if pendingModifiers.contains(.control) { parts.append("⌃") }
        if pendingModifiers.contains(.option) { parts.append("⌥") }
        if pendingModifiers.contains(.shift) { parts.append("⇧") }
        if pendingModifiers.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    private func startRecording() {
        isRecording = true
        pendingModifiers = []
        ServiceContainer.shared.hotkeyService.suspendMonitoring()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Fn key
                if event.modifierFlags.contains(.function) {
                    finishRecording(UnifiedHotkey(keyCode: 0, modifierFlags: 0, isFn: true))
                    return nil
                }

                // Track modifier state
                let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                let current = event.modifierFlags.intersection(relevantMask)

                if current.isEmpty, !pendingModifiers.isEmpty {
                    // All modifiers released - record as modifier-only key
                    if HotkeyService.modifierKeyCodes.contains(event.keyCode) {
                        finishRecording(UnifiedHotkey(keyCode: event.keyCode, modifierFlags: 0, isFn: false))
                        return nil
                    }
                }

                pendingModifiers = current
            }

            if event.type == .keyDown {
                // Escape without modifiers cancels recording
                if event.keyCode == 0x35, pendingModifiers.isEmpty {
                    cancelRecording()
                    return nil
                }

                let relevantMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                let modifiers = event.modifierFlags.intersection(relevantMask).rawValue

                finishRecording(UnifiedHotkey(keyCode: event.keyCode, modifierFlags: modifiers, isFn: false))
                return nil
            }

            return event
        }
    }

    private func finishRecording(_ hotkey: UnifiedHotkey) {
        isRecording = false
        pendingModifiers = []
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        ServiceContainer.shared.hotkeyService.resumeMonitoring()
        onRecord(hotkey)
    }

    private func cancelRecording() {
        isRecording = false
        pendingModifiers = []
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        ServiceContainer.shared.hotkeyService.resumeMonitoring()
    }
}
