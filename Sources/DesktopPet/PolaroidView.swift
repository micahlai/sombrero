import AppKit
import PetAssets

enum PolaroidStyle {
    static let ink = NSColor(srgbRed: 0.33, green: 0.23, blue: 0.14, alpha: 1)
    static let mutedInk = ink.withAlphaComponent(0.65)
    static let size = NSSize(width: 500, height: 500 * 1384 / 1140)

    static func label(_ value: String = "", size: CGFloat = 12) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = AppTypography.font(size: size); field.textColor = mutedInk
        field.lineBreakMode = .byTruncatingTail
        return field
    }
    static func scroll(for text: NSTextView) -> NSScrollView {
        text.drawsBackground = false; text.backgroundColor = .clear
        text.font = AppTypography.font(size: 18); text.textColor = ink
        text.insertionPointColor = ink; text.textContainerInset = NSSize(width: 1, height: 3)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = text; scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        return scroll
    }
}

/// A key-capable paper window, independent of the duck's nonactivating panel.
final class PolaroidWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    init(title: String) {
        super.init(contentRect: NSRect(origin: .zero, size: PolaroidStyle.size),
                   styleMask: [.borderless, .closable, .resizable], backing: .buffered, defer: false)
        self.title = title; isOpaque = false; backgroundColor = .clear
        hasShadow = false; isMovableByWindowBackground = true; isReleasedWhenClosed = false
        contentAspectRatio = PolaroidStyle.size
        contentMinSize = NSSize(width: 420, height: 420 * 1384 / 1140)
        setAccessibilityLabel(title)
    }
    override func cancelOperation(_ sender: Any?) { close() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" { close(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// Coordinates are measured against the supplied 1140 × 1384 artwork. Media is
/// inset inside the painted aperture; all writing stays on the bottom paper lip.
final class PolaroidCanvas: NSView {
    var onLayout: (() -> Void)?
    private let resizeHandle = PolaroidResizeHandle()
    override init(frame frameRect: NSRect) { super.init(frame:frameRect); addSubview(resizeHandle) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }
    var mediaRect: NSRect { rect(x: 0.096, y: 0.085, width: 0.806, height: 0.599) }
    var controlsRect: NSRect { rect(x: 0.09, y: 0.039, width: 0.817, height: 0.035) }
    var writingRect: NSRect { rect(x: 0.115, y: 0.722, width: 0.774, height: 0.151) }
    var footerRect: NSRect { rect(x: 0.115, y: 0.908, width: 0.774, height: 0.044) }
    var statusRect: NSRect { rect(x: 0.119, y: 0.876, width: 0.766, height: 0.028) }
    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(x: bounds.width*x, y: bounds.height*y, width: bounds.width*width, height: bounds.height*height)
    }
    override func draw(_ dirtyRect: NSRect) {
        MessageArtwork.polaroid?.draw(in: bounds, from: .zero, operation: .sourceOver,
                                     fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    override func layout() {
        super.layout()
        resizeHandle.frame=rect(x:0.91,y:0.938,width:0.03,height:0.025)
        onLayout?()
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

private final class PolaroidResizeHandle: NSView {
    private var startPoint = NSPoint.zero
    private var startFrame = NSRect.zero
    override var mouseDownCanMoveWindow: Bool { false }
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect); toolTip="Drag to resize the Polaroid"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        PolaroidStyle.mutedInk.setStroke()
        let p=NSBezierPath(); p.lineWidth=1.2; p.lineCapStyle = .round
        for inset in stride(from:CGFloat(2),through:8,by:3) {
            p.move(to:NSPoint(x:bounds.width-inset-5,y:2)); p.line(to:NSPoint(x:bounds.width-2,y:inset+5))
        }
        p.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        startPoint=NSEvent.mouseLocation; startFrame=window?.frame ?? .zero
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point=NSEvent.mouseLocation, ratio=PolaroidStyle.size.height/PolaroidStyle.size.width
        let dx = point.x-startPoint.x, dy = -(point.y-startPoint.y)/ratio
        let delta=abs(dx)>abs(dy) ? dx : dy
        let limit=window.screen?.visibleFrame.size ?? NSSize(width:2000,height:2000)
        let width=max(window.contentMinSize.width,min(startFrame.width+delta,min(limit.width,limit.height/ratio)))
        let height=width*ratio
        window.setFrame(NSRect(x:startFrame.minX,y:startFrame.maxY-height,width:width,height:height),display:true)
    }
}

/// Native button semantics and keyboard focus, with ink drawn to match the paper.
/// Small vector controls avoid introducing another set of mismatched image assets.
final class PolaroidButton: NSButton {
    enum Drawing { case text, close, shutter, attachment, remove, previous, next, send }
    let drawing: Drawing
    init(_ title: String, drawing: Drawing = .text, target: AnyObject?, action: Selector?) {
        self.drawing = drawing
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false; setButtonType(.momentaryPushIn)
        font = AppTypography.font(size: 14)
        setAccessibilityLabel(title); toolTip = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        let ink = PolaroidStyle.ink.withAlphaComponent(isEnabled ? 1 : 0.32)
        let r = bounds.insetBy(dx: 3, dy: 3)
        if isHighlighted || drawing == .send {
            ink.withAlphaComponent(isHighlighted ? 0.17 : 0.07).setFill()
            NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 6).fill()
        }
        ink.setStroke()
        let path = NSBezierPath(); path.lineWidth = 1.6; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let c = NSPoint(x: r.midX, y: r.midY)
        switch drawing {
        case .close, .remove:
            let d: CGFloat = drawing == .close ? 4 : 3.5
            path.move(to: NSPoint(x: c.x-d, y: c.y-d)); path.line(to: NSPoint(x: c.x+d, y: c.y+d))
            path.move(to: NSPoint(x: c.x-d, y: c.y+d)); path.line(to: NSPoint(x: c.x+d, y: c.y-d))
            if drawing == .remove { path.appendOval(in: NSRect(x:c.x-8,y:c.y-8,width:16,height:16)) }
        case .shutter:
            path.appendOval(in: NSRect(x: c.x-10, y: c.y-9, width: 20, height: 19))
            path.appendOval(in: NSRect(x: c.x-6, y: c.y-5.5, width: 12, height: 11))
        case .attachment:
            path.move(to: NSPoint(x:c.x+4,y:c.y+6))
            path.curve(to:NSPoint(x:c.x-5,y:c.y-5),controlPoint1:NSPoint(x:c.x-5,y:c.y+15),controlPoint2:NSPoint(x:c.x-13,y:c.y-1))
            path.curve(to:NSPoint(x:c.x+6,y:c.y-2),controlPoint1:NSPoint(x:c.x+1,y:c.y-11),controlPoint2:NSPoint(x:c.x+10,y:c.y-7))
            path.line(to:NSPoint(x:c.x-1,y:c.y+5))
            path.curve(to:NSPoint(x:c.x-4,y:c.y+2),controlPoint1:NSPoint(x:c.x-5,y:c.y+9),controlPoint2:NSPoint(x:c.x-8,y:c.y+6))
            path.line(to:NSPoint(x:c.x+1,y:c.y-3))
        case .previous, .next:
            let sign: CGFloat = drawing == .next ? 1 : -1
            path.move(to:NSPoint(x:c.x-3*sign,y:c.y-5)); path.line(to:NSPoint(x:c.x+3*sign,y:c.y))
            path.line(to:NSPoint(x:c.x-3*sign,y:c.y+5))
        case .text, .send:
            var attributes: [NSAttributedString.Key:Any] = [.font:font ?? AppTypography.font(size:14),.foregroundColor:ink]
            if title == "B" { attributes[.strokeWidth] = -3 }
            if title == "I" { attributes[.obliqueness] = 0.2 }
            if title == "U" { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            let text = title as NSString, size = text.size(withAttributes:attributes)
            text.draw(at:NSPoint(x:bounds.midX-size.width/2,y:bounds.midY-size.height/2),withAttributes:attributes)
        }
        path.stroke()
        if window?.firstResponder === self {
            ink.withAlphaComponent(0.5).setStroke()
            let focus=NSBezierPath(roundedRect:r,xRadius:6,yRadius:6); focus.lineWidth=1
            focus.setLineDash([2,3],count:2,phase:0); focus.stroke()
        }
    }
}

final class PolaroidCameraPicker: NSPopUpButton {
    override func draw(_ dirtyRect: NSRect) {
        let ink=PolaroidStyle.ink.withAlphaComponent(isEnabled ? 1 : 0.6)
        let paragraph=NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key:Any] = [.font:AppTypography.font(size:12),.foregroundColor:ink,.paragraphStyle:paragraph]
        let text=(selectedItem?.title ?? "Camera") as NSString
        let height=text.size(withAttributes:attributes).height
        text.draw(in:NSRect(x:4,y:(bounds.height-height)/2,width:bounds.width-20,height:height),withAttributes:attributes)
        ink.setStroke(); let p=NSBezierPath(); p.lineWidth=1.3; p.lineCapStyle = .round
        p.move(to:NSPoint(x:bounds.width-13,y:bounds.midY-2)); p.line(to:NSPoint(x:bounds.width-10,y:bounds.midY+1))
        p.line(to:NSPoint(x:bounds.width-7,y:bounds.midY-2)); p.stroke()
    }
}

final class PolaroidTextView: NSTextView {
    var placeholder = "Write a little note…"
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at:NSPoint(x:textContainerInset.width+5,y:textContainerInset.height),
                withAttributes:[.font:AppTypography.font(size:18),.foregroundColor:PolaroidStyle.ink.withAlphaComponent(0.42)])
        }
    }
}
