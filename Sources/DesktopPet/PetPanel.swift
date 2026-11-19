import AppKit
import PetCore
import PetAssets

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(size: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Watercolor Duck"
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; isFloatingPanel = true; becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false; isMovableByWindowBackground = false
        animationBehavior = .none
        setAccessibilityLabel("Watercolor Duck companion")
    }
}

final class SpriteView: NSView {
    weak var coordinator: PetCoordinator?
    var sprite: SpriteLibrary.Frame?
    private var pointerOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var didDrag = false
    var interactiveRect: NSRect { bounds.insetBy(dx: 12, dy: 12) }
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        if let sprite { return sprite.contains(x: point.x / bounds.width, y: 1 - point.y / bounds.height) }
        return interactiveRect.contains(point)
    }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let sprite, let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
            context.draw(sprite.image, in: bounds)
        } else {
            NSColor.systemYellow.setFill()
            NSBezierPath(rect: interactiveRect).fill()
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
    }
    override func rightMouseDown(with event: NSEvent) { coordinator?.showContextMenu(event: event, view: self) }
}
