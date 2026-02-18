import Foundation
import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TypeWhisper", category: "TextInsertionService")

/// Inserts transcribed text into the active application via clipboard + simulated Cmd+V.
@MainActor
final class TextInsertionService {

enum InsertionResult {
        case pasted
    }

    enum TextInsertionError: LocalizedError {
        case accessibilityNotGranted
        case pasteFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                "Accessibility permission not granted. Please enable it in System Settings → Privacy & Security → Accessibility."
            case .pasteFailed(let detail):
                "Failed to paste text: \(detail)"
            }
        }
    }

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        // Try the prompt first
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Also open System Settings directly (prompt alone may not work in sandbox)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func captureActiveApp() -> (name: String?, bundleId: String?, url: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleId = app?.bundleIdentifier
        return (app?.localizedName, bundleId, nil)
    }

    func resolveBrowserURL(bundleId: String) async -> String? {
        #if APPSTORE
        // Apple Events to other apps are blocked in the App Sandbox
        return nil
        #else
        await Task.detached(priority: .utility) {
            Self.getBrowserURL(bundleId: bundleId)
        }.value
        #endif
    }

    // MARK: - Browser URL Detection

    private enum BrowserType: String {
        case safari, arc, chromiumBased, firefox, notABrowser
    }

    nonisolated private static func identifyBrowser(_ bundleId: String) -> BrowserType {
        switch bundleId {
        case "com.apple.Safari":
            return .safari
        case "company.thebrowser.Browser":
            return .arc
        case "com.google.Chrome",
             "com.google.Chrome.canary",
             "com.brave.Browser",
             "com.microsoft.edgemac",
             "com.operasoftware.Opera",
             "com.vivaldi.Vivaldi",
             "org.chromium.Chromium":
            return .chromiumBased
        case "org.mozilla.firefox":
            return .firefox
        default:
            return .notABrowser
        }
    }

    nonisolated private static func getBrowserURL(bundleId: String) -> String? {
        let browserType = identifyBrowser(bundleId)
        guard browserType != .notABrowser else { return nil }

        // Firefox doesn't support AppleScript for URL access
        guard browserType != .firefox else { return nil }

        // Resolve app name for AppleScript (required in sandbox - "tell application id" doesn't work)
        let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleName"] as? String }
            ?? bundleId


        let script: String
        switch browserType {
        case .safari:
            script = """
            tell application "\(appName)"
                if (count of windows) > 0 then
                    return URL of current tab of front window
                end if
            end tell
            return ""
            """
        case .arc, .chromiumBased:
            script = """
            tell application "\(appName)"
                if (count of windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            return ""
            """
        default:
            return nil
        }

        return executeAppleScript(script, timeout: 2.5)
    }

    nonisolated private static func executeAppleScript(_ source: String, timeout: TimeInterval) -> String? {
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let descriptor = script?.executeAndReturnError(&error)
            if let errorDict = error {
                logger.warning("NSAppleScript error: \(errorDict)")
            }
            if let stringValue = descriptor?.stringValue {
                result = stringValue
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            logger.warning("NSAppleScript timed out after \(timeout)s")
            return nil
        }

        guard let result, !result.isEmpty, isValidURL(result) else { return nil }
        return result
    }

    nonisolated private static func isValidURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3, trimmed.count < 2048 else { return false }
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://")
    }

    func insertText(_ text: String) async throws -> InsertionResult {
        guard isAccessibilityGranted else {
            throw TextInsertionError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general
        // Set transcribed text on clipboard and simulate Cmd+V.
        // Text stays on clipboard as fallback if no text field is focused.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simulatePaste()
        return .pasted
    }

    func focusedElementPosition() -> CGPoint? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else {
            return nil
        }

        let axElement = element as! AXUIElement

        // Try to get the caret position from selected text range
        if let rect = caretRect(from: axElement) {
            return CGPoint(x: rect.origin.x + rect.width, y: rect.origin.y + rect.height)
        }

        // Fallback: get position of focused element
        return elementPosition(from: axElement)
    }

    private func caretRect(from element: AXUIElement) -> CGRect? {
        var selectedRangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue
        )
        guard rangeResult == .success, let rangeValue = selectedRangeValue else { return nil }

        var bounds: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &bounds
        )
        guard boundsResult == .success, let boundsValue = bounds else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func elementPosition(from element: AXUIElement) -> CGPoint? {
        var positionValue: AnyObject?
        let posResult = AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionValue
        )
        guard posResult == .success, let posValue = positionValue else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func simulatePaste() {
        // Key code 0x09 = V
        // Use nil source + .cgSessionEventTap for App Sandbox compatibility
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
