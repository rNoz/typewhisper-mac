import AppKit
import SwiftUI
import Translation

/// Dedicated off-screen window hosting the `.translationTask` modifier.
///
/// The overlay panel uses `orderOut(nil)` which can pause SwiftUI updates,
/// preventing `.translationTask` from firing. This 1×1 window is always
/// ordered-in (off-screen) so the modifier reliably triggers.
@MainActor
final class TranslationHostWindow: NSWindow {

    init(translationService: TranslationService) {
        super.init(
            contentRect: NSRect(x: -9999, y: -9999, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        level = .init(rawValue: Int(CGWindowLevelForKey(.minimumWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        contentView = NSHostingView(
            rootView: TranslationHostView(translationService: translationService)
        )

        orderFrontRegardless()
    }
}

/// Minimal SwiftUI view that observes TranslationService and hosts `.translationTask`.
/// Using `@ObservedObject` ensures the view re-renders when `configuration` changes,
/// which is required for `.translationTask` to fire.
private struct TranslationHostView: View {
    @ObservedObject var translationService: TranslationService

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(translationService.configuration) { session in
                await translationService.handleSession(session)
            }
    }
}
