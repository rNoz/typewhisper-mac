import AppKit
import SwiftUI
import Combine

/// Observable notch geometry passed from the panel to the SwiftUI view.
@MainActor
final class NotchGeometry: ObservableObject {
    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 38
    @Published var hasNotch: Bool = false

    func update(for screen: NSScreen) {
        hasNotch = screen.safeAreaInsets.top > 0
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - left - right + 4
        } else {
            notchWidth = 0
        }
        notchHeight = hasNotch ? screen.safeAreaInsets.top : 32
    }
}

/// Hosting view that accepts first mouse click without requiring a prior activation click.
private class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Panel that visually extends the MacBook notch, centered over the hardware notch.
/// Only shown on displays with a hardware notch - hidden on non-notch displays regardless of settings.
class NotchIndicatorPanel: NSPanel {
    /// Large enough to accommodate the expanded (open) state. SwiftUI clips the visible area.
    private static let panelWidth: CGFloat = 500
    private static let panelHeight: CGFloat = 500

    private let notchGeometry = NotchGeometry()
    private var cancellables = Set<AnyCancellable>()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        let hostingView = FirstMouseHostingView(rootView: NotchIndicatorView(geometry: notchGeometry))
        contentView = hostingView
    }

    override var canBecomeKey: Bool {
        if case .promptSelection = DictationViewModel.shared.state { return true }
        return false
    }
    override var canBecomeMain: Bool { false }

    func startObserving() {
        let vm = DictationViewModel.shared

        vm.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateVisibility(state: state, vm: vm)
            }
            .store(in: &cancellables)

        vm.$notchIndicatorVisibility
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateVisibility(state: vm.state, vm: vm)
            }
            .store(in: &cancellables)

        vm.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .promptSelection:
                    self.ignoresMouseEvents = false
                    self.orderFrontRegardless()
                    self.installKeyMonitor()
                case .promptProcessing:
                    self.ignoresMouseEvents = false
                    self.installKeyMonitor()
                default:
                    self.ignoresMouseEvents = true
                    self.removeKeyMonitor()
                }
            }
            .store(in: &cancellables)
    }

    private func updateVisibility(state: DictationViewModel.State, vm: DictationViewModel) {
        switch vm.notchIndicatorVisibility {
        case .always:
            show()
        case .duringActivity:
            switch state {
            case .recording, .processing, .inserting, .promptSelection, .promptProcessing, .error:
                show()
            case .idle:
                dismiss()
            }
        case .never:
            dismiss()
        }
    }

    // MARK: - CGEvent tap (intercepts AND consumes keys globally)

    private func installKeyMonitor() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ -> Unmanaged<CGEvent>? in
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let vm = DictationViewModel.shared

                // Esc/Enter dismiss promptProcessing (result view)
                if case .promptProcessing = vm.state {
                    if keyCode == 53 || keyCode == 36 {
                        DispatchQueue.main.async { vm.dismissPromptSelection() }
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Esc dismisses promptSelection
                if keyCode == 53 {
                    DispatchQueue.main.async { vm.dismissPromptSelection() }
                    return nil
                }

                // Other keys only during selection
                guard case .promptSelection = vm.state else {
                    return Unmanaged.passUnretained(event)
                }

                switch keyCode {
                case 36: // Enter/Return
                    DispatchQueue.main.async { vm.confirmPromptSelection() }
                    return nil
                case 126: // Arrow Up
                    DispatchQueue.main.async { vm.movePromptSelection(by: -1) }
                    return nil
                case 125: // Arrow Down
                    DispatchQueue.main.async { vm.movePromptSelection(by: 1) }
                    return nil
                default:
                    // Number keys 1-9 (key codes are non-contiguous)
                    let digitMap: [Int64: Int] = [18:1, 19:2, 20:3, 21:4, 23:5, 22:6, 26:7, 28:8, 25:9]
                    if let digit = digitMap[keyCode] {
                        DispatchQueue.main.async { vm.selectPromptByIndex(digit - 1) }
                        return nil
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    private func removeKeyMonitor() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    // MARK: - Notch geometry

    /// Returns the screen with a hardware notch (built-in display), or nil.
    private static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    func show() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        notchGeometry.update(for: screen)

        let screenFrame = screen.frame
        let x = screenFrame.midX - Self.panelWidth / 2
        let y = screenFrame.origin.y + screenFrame.height - Self.panelHeight

        setFrame(NSRect(x: x, y: y, width: Self.panelWidth, height: Self.panelHeight), display: true)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
