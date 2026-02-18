import SwiftUI

/// Compact pill overlay showing dictation state (recording, processing, done, error).
struct DictationOverlayView: View {
    @ObservedObject private var viewModel = DictationViewModel.shared
    /// Latches to true once first partial text arrives; prevents height toggling.
    @State private var textAreaExpanded = false

    private var isTop: Bool {
        viewModel.overlayPosition == .top
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status pill
            HStack(spacing: 8) {
                statusIcon
                statusText
                if let profileName = viewModel.activeProfileName, viewModel.state == .recording {
                    Text(profileName)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2), in: Capsule())
                        .foregroundStyle(.blue)
                }
                if case .recording = viewModel.state {
                    AudioWaveformView(
                        audioLevel: viewModel.audioLevel,
                        isSetup: viewModel.recordingDuration < 0.5 && viewModel.audioLevel < 0.05
                    )
                    .frame(width: 40)
                    durationText
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Partial transcription text
            if viewModel.state == .recording {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(viewModel.partialText)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .contentTransition(.identity)
                            .animation(nil, value: viewModel.partialText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .id("partialTextBottom")
                    }
                    .frame(height: textAreaExpanded ? 200 : 0)
                    .clipped()
                    .scrollContentBackground(.hidden)
                    .onChange(of: viewModel.partialText) {
                        if !viewModel.partialText.isEmpty, !textAreaExpanded {
                            withAnimation(.easeOut(duration: 0.2)) {
                                textAreaExpanded = true
                            }
                        }
                        proxy.scrollTo("partialTextBottom", anchor: .bottom)
                    }
                }
                .transaction { $0.disablesAnimations = true }
            }
        }
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: textAreaExpanded ? 16 : 26))
        .overlay(RoundedRectangle(cornerRadius: textAreaExpanded ? 16 : 26).strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isTop ? .top : .bottom)
        .animation(.easeInOut(duration: 0.2), value: viewModel.state)
        .onChange(of: viewModel.state) {
            if viewModel.state != .recording {
                textAreaExpanded = false
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .fill(.red.opacity(0.4))
                        .frame(width: 16, height: 16)
                        .opacity(viewModel.audioLevel > 0.1 ? 1 : 0)
                )

        case .processing:
            ProgressView()
                .controlSize(.small)

        case .inserting:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))

        case .promptSelection:
            Image(systemName: "text.bubble.fill")
                .foregroundStyle(.blue)
                .font(.system(size: 14))

        case .promptProcessing:
            ProgressView()
                .controlSize(.small)

        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 4) {
                Text(String(localized: "Recording"))
                    .font(.system(size: 12, weight: .medium))
                if let mode = viewModel.hotkeyMode {
                    Text(mode == .pushToTalk ? "PTT" : "TOG")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }

        case .processing:
            Text(String(localized: "Transcribing..."))
                .font(.system(size: 12, weight: .medium))

        case .inserting:
            Text(String(localized: "Done"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)

        case .promptSelection:
            Text(String(localized: "Select prompt..."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.blue)

        case .promptProcessing(let name):
            Text(name)
                .font(.system(size: 12, weight: .medium))

        case .error(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(1)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var durationText: some View {
        Text(formatDuration(viewModel.recordingDuration))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
