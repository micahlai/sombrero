import AppKit
import ApplicationServices
import PetCore

/// Reads only the focused window's geometry. Missing permission or unsupported
/// accessibility attributes conservatively disable the window-entry branch.
final class FocusedWindowTracker {
    var hasPermission: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    func peekOrigin(viewportSize: Double) -> NSPoint? {
        guard hasPermission, let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primary = NSScreen.screens.first else { return nil }
        let app = AXUIElementCreateApplication(frontmost.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let focused = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let window = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(window, 0.15)
        guard (attribute(window, kAXMinimizedAttribute) as? Bool) != true,
              let rawPosition = attribute(window, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = attribute(window, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
        // Accessibility has a top-left origin on the primary display; AppKit is bottom-left.
        let rect = CGRect(x: position.x, y: primary.frame.maxY - position.y - size.height, width: size.width, height: size.height)
        let topCenter = CGPoint(x: rect.midX, y: rect.maxY - 1)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(topCenter) }) else { return nil }
        let area = screen.visibleFrame
        guard let point = WindowPeekPlacement.origin(
            window: PetRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
            workArea: PetRect(x: area.minX, y: area.minY, width: area.width, height: area.height),
            viewportSize: viewportSize, isFullScreen: (attribute(window, "AXFullScreen") as? Bool) == true) else { return nil }
        return NSPoint(x: point.x, y: point.y)
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
