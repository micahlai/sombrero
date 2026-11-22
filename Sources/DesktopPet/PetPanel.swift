import AppKit
import PetCore
import PetAssets

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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
    var flipsHorizontally = false
    var hasUnreadVerse = false { didSet { notificationsChanged() } }
    var hasUnreadMessages = false { didSet { notificationsChanged() } }
    private var hasNotifications: Bool { hasUnreadVerse || hasUnreadMessages }
    var badgeBounds: CGRect?
    private var notificationElapsed = 0.0
    private(set) var notificationFrameIndex = 0
    private func notificationsChanged() {
        if !hasNotifications { notificationElapsed=0; notificationFrameIndex=0 }
        needsDisplay=true
    }
    func advanceNotification(by delta: Double) {
        guard hasNotifications, delta.isFinite, delta>0, !NotificationArtwork.frames.isEmpty else { return }
        let period=Double(NotificationArtwork.frames.count)/Double(PetConstants.Animation.drawingFPS)
        notificationElapsed=(notificationElapsed+delta).truncatingRemainder(dividingBy:period)
        let frame=min(NotificationArtwork.frames.count-1,Int(notificationElapsed*Double(PetConstants.Animation.drawingFPS)+PetConstants.Animation.timeEpsilon))
        if frame != notificationFrameIndex { notificationFrameIndex=frame; needsDisplay=true }
    }
    private var pointerOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var didDrag = false
    var interactiveRect: NSRect {
        let rect = PetConstants.Geometry.placeholderBounds
        return NSRect(x: bounds.width * rect.x, y: bounds.height * rect.y, width: bounds.width * rect.width, height: bounds.height * rect.height)
    }
    func containsInteractivePoint(_ point: NSPoint) -> Bool {
        if hasNotifications && badgeRect.contains(point) { return true }
        if let sprite {
            let x = point.x / bounds.width
            return sprite.contains(x: flipsHorizontally ? 1-x : x, y: point.y / bounds.height)
        }
        return interactiveRect.contains(point)
    }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }
    private var badgeRect: NSRect {
        let fallback=PetConstants.Geometry.placeholderBounds
        let painted=badgeBounds ?? sprite?.occupiedBounds ?? CGRect(x:fallback.x,y:fallback.y,width:fallback.width,height:fallback.height)
        let size=PetConstants.Appearance.badgeSize
        let x=flipsHorizontally ? 1-painted.midX : painted.midX
        // Keep the marker directly above the duck; screen edges may clip it.
        return NSRect(x:x*bounds.width-size/2,y:painted.maxY*bounds.height+4,width:size,height:size)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let sprite, let context = NSGraphicsContext.current?.cgContext {
            context.interpolationQuality = .high
            context.saveGState()
            if flipsHorizontally { context.translateBy(x: bounds.width, y: 0); context.scaleBy(x: -1, y: 1) }
            let rect = sprite.placement
            context.draw(sprite.image, in: NSRect(x: rect.minX * bounds.width, y: rect.minY * bounds.height,
                width: rect.width * bounds.width, height: rect.height * bounds.height))
            context.restoreGState()
        } else {
            NSColor.systemPink.setFill()
            NSBezierPath(rect: interactiveRect).fill()
            let text = state.rawValue.uppercased() as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: PetConstants.Appearance.placeholderLabelSize, weight: .semibold), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: interactiveRect.midX - size.width / 2, y: interactiveRect.midY - size.height / 2), withAttributes: attributes)
        }
        if hasNotifications {
            if NotificationArtwork.frames.indices.contains(notificationFrameIndex), let context=NSGraphicsContext.current?.cgContext {
                context.saveGState(); context.interpolationQuality = .high
                context.draw(NotificationArtwork.frames[notificationFrameIndex],in:badgeRect)
                context.restoreGState()
            } else {
                let mark="!" as NSString
                let attributes: [NSAttributedString.Key:Any]=[.font:AppTypography.font(size:24),.foregroundColor:NSColor(srgbRed:0.43,green:0.73,blue:0.48,alpha:1)]
                let size=mark.size(withAttributes:attributes)
                mark.draw(at:NSPoint(x:badgeRect.midX-size.width/2,y:badgeRect.midY-size.height/2),withAttributes:attributes)
            }
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
        if hypot(dx, dy) > PetConstants.Interaction.dragThreshold { didDrag = true }
        if didDrag { coordinator?.drag(to: NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        pointerOrigin = nil; windowOrigin = nil
        coordinator?.endPointerGesture()
        if !didDrag { coordinator?.toggleBubble() }
    }
    override func rightMouseDown(with event: NSEvent) { coordinator?.showContextMenu(event: event, view: self) }
}
