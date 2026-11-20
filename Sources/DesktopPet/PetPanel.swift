import AppKit
import PetCore
import PetAssets

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(size: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "sombrero"
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isFloatingPanel = true; becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false; isMovableByWindowBackground = false
        animationBehavior = .none
        setAccessibilityLabel("sombrero companion")
    }
}

final class SpriteView: NSView {
    weak var coordinator: PetCoordinator?
    var sprite: SpriteLibrary.Frame?
    var state: DuckState = .look
    private var pointerOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var didDrag = false
    var interactiveRect: NSRect {
        NSRect(x: bounds.width * 0.4, y: bounds.height * 0.26, width: bounds.width * 0.2, height: bounds.height * 0.2)
    }
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        if let sprite { return sprite.contains(x: point.x / bounds.width, y: point.y / bounds.height) }
        return interactiveRect.contains(point)
    }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let sprite, let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
            let rect = sprite.placement
            context.draw(sprite.image, in: NSRect(x: rect.minX * bounds.width, y: rect.minY * bounds.height,
                width: rect.width * bounds.width, height: rect.height * bounds.height))
        } else {
            NSColor.systemPink.setFill()
            NSBezierPath(rect: interactiveRect).fill()
            let text = state.rawValue.uppercased() as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: interactiveRect.midX - size.width / 2, y: interactiveRect.midY - size.height / 2), withAttributes: attributes)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { containsInteractivePoint(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        pointerOrigin = NSEvent.mouseLocation; windowOrigin = window?.frame.origin; didDrag = false
        coordinator?.beginPointerGesture()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = pointerOrigin, let origin = windowOrigin else { return }
        let point = NSEvent.mouseLocation
        let dx = point.x - start.x, dy = point.y - start.y
        if hypot(dx, dy) > 5 { didDrag = true }
        if didDrag { coordinator?.drag(to: NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        pointerOrigin = nil; windowOrigin = nil
        coordinator?.endPointerGesture()
        if !didDrag { coordinator?.toggleBubble() }
    }
    override func rightMouseDown(with event: NSEvent) { coordinator?.showContextMenu(event: event, view: self) }
}
