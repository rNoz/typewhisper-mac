import SwiftUI
import IOKit.ps

/// Notch-extending indicator that visually expands the MacBook notch area.
/// Three-zone layout: left ear | center (notch spacer) | right ear.
/// Both sides are configurable (indicator, timer, waveform, clock, battery).
/// Expands wider and downward to show streaming partial text.
/// Blue glow emanates from the notch shape, reacting to audio level.
struct NotchIndicatorView: View {
    @ObservedObject private var viewModel = DictationViewModel.shared
    @ObservedObject var geometry: NotchGeometry
    @State private var textExpanded = false
    @State private var dotPulse = false

    private let extensionWidth: CGFloat = 60

    private var closedWidth: CGFloat {
        geometry.hasNotch ? geometry.notchWidth + 2 * extensionWidth : 200
    }

    private var isExpanded: Bool {
        if textExpanded { return true }
        switch viewModel.state {
        case .promptSelection, .promptProcessing:
            return true
        default:
            return false
        }
    }

    private var currentWidth: CGFloat {
        switch viewModel.state {
        case .promptSelection, .promptProcessing:
            return max(closedWidth, 420)
        default:
            return textExpanded ? max(closedWidth, 400) : closedWidth
        }
    }

    // MARK: - Audio-reactive glow

    private var glowColor: Color {
        if case .promptProcessing = viewModel.state {
            return Color(red: 0.6, green: 0.3, blue: 1.0) // purple
        }
        return Color(red: 0.3, green: 0.5, blue: 1.0) // blue
    }

    private var glowOpacity: Double {
        switch viewModel.state {
        case .recording:
            return max(0.25, min(Double(viewModel.audioLevel) * 2.5, 0.9))
        case .promptProcessing:
            return 0.5
        default:
            return 0
        }
    }

    private var glowRadius: CGFloat {
        switch viewModel.state {
        case .recording:
            return max(6, CGFloat(viewModel.audioLevel) * 25 + 4)
        case .promptProcessing:
            return 12
        default:
            return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Three-zone status bar
            statusBar
                .frame(height: geometry.notchHeight)

            // Expandable partial text area
            if viewModel.state == .recording {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(viewModel.partialText)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 34)
                            .padding(.top, 14)
                            .padding(.bottom, 16)
                            .id("bottom")
                    }
                    .frame(height: textExpanded ? 80 : 0)
                    .clipped()
                    .onChange(of: viewModel.partialText) {
                        if !viewModel.partialText.isEmpty, !textExpanded {
                            withAnimation(.easeOut(duration: 0.25)) {
                                textExpanded = true
                            }
                        }
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .transaction { $0.disablesAnimations = true }
            }

            // Prompt selection list
            if case .promptSelection(let text) = viewModel.state {
                promptSelectionView(text: text)
            }

            // Prompt processing status
            if case .promptProcessing(let promptName) = viewModel.state {
                promptProcessingView(promptName: promptName)
            }
        }
        .frame(width: currentWidth)
        .background(.black)
        .clipShape(NotchShape(
            topCornerRadius: isExpanded ? 19 : 6,
            bottomCornerRadius: isExpanded ? 24 : 14
        ))
        // Blue glow that reacts to audio level
        .shadow(color: glowColor.opacity(glowOpacity), radius: glowRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: textExpanded)
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        .animation(.easeOut(duration: 0.08), value: viewModel.audioLevel)
        .onChange(of: viewModel.state) {
            if viewModel.state == .recording {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    dotPulse = true
                }
            } else {
                dotPulse = false
                switch viewModel.state {
                case .promptSelection, .promptProcessing:
                    break // keep expanded
                default:
                    textExpanded = false
                }
            }
        }
    }

    // MARK: - Status bar (three-zone layout)

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 0) {
            contentView(for: viewModel.notchIndicatorLeftContent, side: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 34)

            // Center: notch spacer (invisible black, matches hardware notch)
            if geometry.hasNotch {
                Color.clear
                    .frame(width: geometry.notchWidth)
            }

            contentView(for: viewModel.notchIndicatorRightContent, side: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 34)
        }
    }

    // MARK: - Configurable content

    private enum Side {
        case leading, trailing
    }

    @ViewBuilder
    private func contentView(for content: DictationViewModel.NotchIndicatorContent, side: Side) -> some View {
        switch viewModel.state {
        case .idle:
            Color.clear
        case .recording:
            recordingContent(for: content)
        case .processing:
            if side == .leading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            } else {
                Color.clear
            }
        case .inserting:
            if side == .leading {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 11))
            } else {
                Color.clear
            }
        case .promptSelection:
            Color.clear
        case .promptProcessing:
            if side == .leading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
            } else {
                Color.clear
            }
        case .error:
            if side == .leading {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 11))
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func recordingContent(for content: DictationViewModel.NotchIndicatorContent) -> some View {
        switch content {
        case .indicator:
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .scaleEffect(1.0 + CGFloat(viewModel.audioLevel) * 0.8)
                .shadow(color: .yellow.opacity(dotPulse ? 0.8 : 0.2), radius: dotPulse ? 6 : 2)
        case .timer:
            Text(formatDuration(viewModel.recordingDuration))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        case .waveform:
            AudioWaveformView(
                audioLevel: viewModel.audioLevel,
                isSetup: viewModel.recordingDuration < 0.5 && viewModel.audioLevel < 0.05,
                compact: true
            )
        case .clock:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .battery:
            batteryView
        case .none:
            Color.clear
        }
    }

    // MARK: - Battery

    @ViewBuilder
    private var batteryView: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            if let level = Self.readBatteryLevel() {
                HStack(spacing: 3) {
                    Image(systemName: Self.batteryIconName(level: level))
                        .font(.system(size: 10))
                    Text("\(level)%")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    nonisolated private static func readBatteryLevel() -> Int? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        for source in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
               let capacity = info[kIOPSCurrentCapacityKey] as? Int {
                return capacity
            }
        }
        return nil
    }

    nonisolated private static func batteryIconName(level: Int) -> String {
        switch level {
        case 0..<13: return "battery.0percent"
        case 13..<38: return "battery.25percent"
        case 38..<63: return "battery.50percent"
        case 63..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    // MARK: - Prompt Selection

    @ViewBuilder
    private func promptSelectionView(text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text preview
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(3)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            // Action list: clipboard option + prompt actions
            VStack(spacing: 2) {
                // "Copy to Clipboard" as first option (index 0)
                clipboardRow

                ForEach(Array(viewModel.availablePromptActions.enumerated()), id: \.element.id) { index, action in
                    promptActionRow(action: action, index: index + 1) // offset by 1
                }
            }
            .padding(.vertical, 8)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            // Dismiss hint
            Text("esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.25))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var clipboardRow: some View {
        let isSelected = viewModel.selectedPromptIndex == 0

        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13))
                .frame(width: 18)

            Text(String(localized: "Copy to Clipboard"))
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

            Spacer()

            Text("1")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.25))
        }
        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.65))
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { viewModel.selectedPromptIndex = 0 }
        }
        .onTapGesture {
            viewModel.selectedPromptIndex = 0
            viewModel.confirmPromptSelection()
        }
    }

    @ViewBuilder
    private func promptActionRow(action: PromptAction, index: Int) -> some View {
        let isSelected = index == viewModel.selectedPromptIndex

        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 13))
                .frame(width: 18)

            Text(action.name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

            Spacer()

            if index < 9 {  // index already includes clipboard offset
                Text("\(index + 1)")  // clipboard=1, first action=2, etc.
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.65))
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                .padding(.horizontal, 8)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                viewModel.selectedPromptIndex = index
            }
        }
        .onTapGesture {
            viewModel.selectPromptAction(action)
        }
    }

    // MARK: - Prompt Processing

    @ViewBuilder
    private func promptProcessingView(promptName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.promptResultText.isEmpty {
                // Processing spinner
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                    Text(promptName + "...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)
            } else {
                // Result display
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                    Text(promptName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text("esc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)

                ScrollView(.vertical, showsIndicators: true) {
                    Text(viewModel.promptResultText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
