import AppKit
import PetAssets
import PetCore

final class SpeechBubble {
    enum Mode { case menu, away, photo, camera, bible }
    enum Action { case close, goAway, away(Int?), back, seePhoto, sendPhoto, readBible, done, capture }
    static let size = NSSize(width: PetConstants.Speech.width, height: PetConstants.Speech.height)
    let panel = PetPanel(size: SpeechBubble.size.width)
    private let view = BubbleView(frame: NSRect(x: 0, y: 0, width: SpeechBubble.size.width, height: SpeechBubble.size.height))
    private var playback = SpeechBubblePlayback()
    private var mode: Mode = .menu
    var onAction: ((Action) -> Void)?
    var isVisible: Bool { playback.isVisible }
    var wantsOpen: Bool { playback.wantsOpen }
    var containsPointer: Bool {
        let point = NSEvent.mouseLocation
        return isVisible && view.containsPaintedPoint(NSPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY))
    }

    init(images: [CGImage]) {
        view.images = images
        view.controls.isHidden = true
        panel.title = "Duck speech bubble"
        panel.setContentSize(view.frame.size)
        panel.contentView = view
        panel.setAccessibilityLabel("Duck speech menu")
        view.action = { [weak self] action in self?.onAction?(action) }
        setMode(.menu)
    }
    func show(mode: Mode = .menu) {
        setMode(mode)
        if !playback.wantsOpen { playback.open() }
        updateView(); panel.orderFrontRegardless()
    }
    func close(immediately: Bool = false) {
        if immediately { playback = SpeechBubblePlayback(); panel.orderOut(nil) }
        else { playback.close() }
        updateView()
    }
    func advance(by delta: Double) {
        playback.advance(by: delta); updateView()
        if !playback.isVisible { panel.orderOut(nil) }
    }
    private func updateView() {
        view.frameIndex = playback.frameIndex
        view.controls.isHidden = !playback.isExpanded
        panel.ignoresMouseEvents = !containsPointer
        view.needsDisplay = true
    }
    func setMode(_ mode: Mode) {
        self.mode = mode
        view.configure(mode: mode)
    }
    func anchor(to duck: NSRect, workArea: NSRect) {
        let width = min(Self.size.width, workArea.width)
        let height = min(Self.size.height, workArea.height)
        panel.setContentSize(NSSize(width: width, height: height))
        let gap = PetConstants.Speech.gap
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, workArea.minX), workArea.maxX-width) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, workArea.minY), workArea.maxY-height) }
        let flip = duck.midX + width * (1-PetConstants.Speech.tailFraction) > workArea.maxX
        let x = clampX(duck.midX - width * (flip ? 1-PetConstants.Speech.tailFraction : PetConstants.Speech.tailFraction))
        let candidates: [(NSRect, Bool)] = [
            (NSRect(x: x, y: duck.maxY+gap, width: width, height: height), flip),
            (NSRect(x: duck.maxX+gap, y: clampY(duck.maxY-height*PetConstants.Speech.sideAlignment), width: width, height: height), false),
            (NSRect(x: duck.minX-width-gap, y: clampY(duck.maxY-height*PetConstants.Speech.sideAlignment), width: width, height: height), true),
            (NSRect(x: x, y: duck.minY-height-gap, width: width, height: height), flip)
        ]
        // Prefer above, then either side, then below. Never place tail dots over the duck.
        let placement = candidates.first { workArea.contains($0.0) && !$0.0.intersects(duck) } ?? candidates[0]
        view.flippedArtwork = placement.1
        panel.setFrameOrigin(placement.0.origin)
    }
}

private final class BubbleView: NSView {
    var images: [CGImage] = [] {
        didSet {
            masks = images.map { image in
                let n = PetConstants.Assets.maskSize, channels = PetConstants.Assets.rgbaChannels
                let crop = PetConstants.Speech.crop
                var pixels = [UInt8](repeating: 0, count: n * n * channels)
                pixels.withUnsafeMutableBytes { bytes in
                    guard let context = CGContext(data: bytes.baseAddress, width: n, height: n,
                        bitsPerComponent: PetConstants.Assets.bitsPerChannel, bytesPerRow: n*channels, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                    context.draw(image, in: CGRect(x: -crop.x/crop.width*Double(n), y: -crop.y/crop.height*Double(n),
                                                  width: PetConstants.Speech.sourceWidth/crop.width*Double(n), height: PetConstants.Speech.sourceHeight/crop.height*Double(n)))
                }
                return stride(from: channels-1, to: pixels.count, by: channels).map { pixels[$0] }
            }
        }
    }
    private var masks: [[UInt8]] = []
    var frameIndex = 0
    var flippedArtwork = false
    var action: ((SpeechBubble.Action) -> Void)?
    let controls = NSStackView()
    private var handlers: [BubbleButton] = []
    private var fallbackRect: NSRect {
        let rect = PetConstants.Speech.fallback
        return NSRect(x: bounds.width*rect.x, y: bounds.height*rect.y, width: bounds.width*rect.width, height: bounds.height*rect.height)
    }
    override var isOpaque: Bool { false }
    func containsPaintedPoint(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        guard masks.indices.contains(frameIndex) else { return fallbackRect.contains(point) }
        let n = PetConstants.Assets.maskSize
        let x = min(n-1, Int(point.x / bounds.width * Double(n)))
        let y = min(n-1, Int(point.y / bounds.height * Double(n)))
        return masks[frameIndex][(n-1-y)*n + (flippedArtwork ? n-1-x : x)] > PetConstants.Assets.alphaThreshold
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        containsPaintedPoint(point) ? super.hitTest(point) : nil
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = PetConstants.Speech.controlSpacing
        addSubview(controls)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        // Same registration across all five source drawings; only the final body holds controls.
        let rect = PetConstants.Speech.controls
        controls.frame = NSRect(x: bounds.width*rect.x, y: bounds.height*rect.y, width: bounds.width*rect.width, height: bounds.height*rect.height)
        for child in controls.arrangedSubviews {
            if let label = child as? NSTextField { label.preferredMaxLayoutWidth = controls.frame.width }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .high
        if flippedArtwork { context.translateBy(x: bounds.width, y: 0); context.scaleBy(x: -1, y: 1) }
        if images.indices.contains(frameIndex) {
            let crop = PetConstants.Speech.crop
            let sx = bounds.width/crop.width, sy = bounds.height/crop.height
            context.draw(images[frameIndex], in: NSRect(x: -crop.x*sx, y: -crop.y*sy, width: PetConstants.Speech.sourceWidth*sx, height: PetConstants.Speech.sourceHeight*sy))
        } else {
            let paper = PetConstants.Speech.paper
            NSColor(calibratedRed: paper.red, green: paper.green, blue: paper.blue, alpha: 1).setFill()
            NSBezierPath(roundedRect: fallbackRect, xRadius: bounds.width * PetConstants.Speech.fallbackCorner.x, yRadius: bounds.height * PetConstants.Speech.fallbackCorner.y).fill()
        }
        context.restoreGState()
    }
    func configure(mode: SpeechBubble.Mode) {
        for child in controls.arrangedSubviews { controls.removeArrangedSubview(child); child.removeFromSuperview() }
        handlers.removeAll()
        switch mode {
        case .menu:
            button("Go away…", .goAway)
            button("See message", .seePhoto)
            button("Send message", .sendPhoto)
            button("Read Bible verse", .readBible)
            button("Close", .close)
        case .away:
            button("Until I call you", .away(nil))
            for minutes in PetConstants.Interaction.awayMinuteOptions { button("In \(minutes) minutes", .away(minutes)) }
            button("Back", .back)
        case .photo:
            label("Message / photo", size: PetConstants.Speech.headingFontSize)
            label("No messages yet.\nLocal preview.")
            button("Done", .done)
        case .camera:
            label("Send message", size: PetConstants.Speech.headingFontSize)
            label("Camera preview.\nNot connected yet.")
            button("Preview capture", .capture)
            button("Cancel", .done)
        case .bible:
            label("Bible verse", size: PetConstants.Speech.headingFontSize)
            label("Reader preview.\nVerse content coming soon.")
            button("Done", .done)
        }
        needsLayout = true
    }
    private static let ink = NSColor(srgbRed: PetConstants.Speech.ink.red, green: PetConstants.Speech.ink.green, blue: PetConstants.Speech.ink.blue, alpha: 1)
    private func label(_ text: String, size: CGFloat = PetConstants.Speech.bodyFontSize) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = AppTypography.font(size: size)
        label.textColor = Self.ink
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        controls.addArrangedSubview(label)
    }
    private func button(_ title: String, _ value: SpeechBubble.Action) {
        let button = BubbleButton(title: title, target: nil, action: nil)
        button.font = AppTypography.font(size: PetConstants.Speech.bodyFontSize)
        button.controlSize = .mini
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: AppTypography.font(size: PetConstants.Speech.bodyFontSize), .foregroundColor: Self.ink])
        button.contentTintColor = Self.ink
        button.heightAnchor.constraint(equalToConstant: PetConstants.Speech.buttonHeight).isActive = true
        button.isBordered = false; button.alignment = .left
        button.setAccessibilityLabel(title)
        button.target = button; button.action = #selector(BubbleButton.invoke)
        button.handler = { [weak self] in self?.action?(value) }
        controls.addArrangedSubview(button); handlers.append(button)
    }
}

private final class BubbleButton: NSButton {
    var handler: (() -> Void)?
    @objc func invoke() { handler?() }
}
