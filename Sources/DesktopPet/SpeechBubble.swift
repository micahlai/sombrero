import AppKit
import PetAssets
import PetCore

final class SpeechBubble {
    enum Mode { case menu, away, bible }
    enum Action { case close, goAway, away(Int?), back, seePhoto, sendPhoto, readBible, done, previousBiblePage, nextBiblePage }
    static let size = NSSize(width: PetConstants.Speech.width, height: PetConstants.Speech.height)
    let panel = PetPanel(size: SpeechBubble.size.width)
    private let view = BubbleView(frame: NSRect(x: 0, y: 0, width: SpeechBubble.size.width, height: SpeechBubble.size.height))
    private var playback = SpeechBubblePlayback()
    private var mode: Mode = .menu
    var onAction: ((Action) -> Void)?
    var isVisible: Bool { playback.isVisible }
    var wantsOpen: Bool { playback.wantsOpen }
    var isExpanded: Bool { playback.isExpanded }
    var isBibleMode: Bool { mode == .bible }
    var biblePageTexts: [String] { view.biblePages }
    var biblePageIndex: Int { view.biblePage }
    var bibleVerseID: String? { view.bibleVerse?.id }
    var isOnLastBiblePage: Bool { !view.biblePages.isEmpty && view.biblePage == view.biblePages.count-1 }
    var presentedBibleVerseID: String? {
        isBibleMode && isVisible && wantsOpen && isExpanded && panel.isVisible ? bibleVerseID : nil
    }
    func changeBiblePage(by delta: Int) { view.changeBiblePage(by:delta) }
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
        panel.setContentSize(view.preferredSize)
    }
    func setBible(verse: BibleVerse?, status: String? = nil) {
        if view.bibleVerse?.id != verse?.id { view.biblePage=0 }
        view.bibleVerse=verse; view.bibleStatus=status ?? ""
        if mode == .bible { setMode(.bible) }
    }
    func setBibleAvailable(_ available: Bool) {
        guard view.bibleAvailable != available else { return }
        view.bibleAvailable=available
        if mode == .menu { setMode(.menu) }
    }
    func setMessageStatus(unreadCount: Int) {
        let count=max(0,unreadCount)
        guard view.unreadMessageCount != count else { return }
        view.unreadMessageCount=count
        if mode == .menu { setMode(.menu) }
    }
    func anchor(to duck: NSRect, workArea: NSRect) {
        let preferred=view.preferredSize
        let width = min(preferred.width, workArea.width)
        let height = min(preferred.height, workArea.height)
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
        panel.setFrameOrigin(NSPoint(x:clampX(placement.0.minX),y:clampY(placement.0.minY)))
    }
}

private final class BubbleView: NSView {
    var images: [CGImage] = [] {
        didSet {
            masks=images.map { image in
                let n=PetConstants.Assets.maskSize, channels=PetConstants.Assets.rgbaChannels, crop=PetConstants.Speech.crop
                var pixels=[UInt8](repeating:0,count:n*n*channels)
                pixels.withUnsafeMutableBytes { bytes in
                    guard let context=CGContext(data:bytes.baseAddress,width:n,height:n,bitsPerComponent:8,bytesPerRow:n*channels,
                        space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                    context.draw(image,in:CGRect(x:-crop.x/crop.width*Double(n),y:-crop.y/crop.height*Double(n),
                        width:PetConstants.Speech.sourceWidth/crop.width*Double(n),height:PetConstants.Speech.sourceHeight/crop.height*Double(n)))
                }
                return stride(from:channels-1,to:pixels.count,by:channels).map { pixels[$0] }
            }
        }
    }
    private var masks: [[UInt8]] = []
    var frameIndex=0
    var flippedArtwork=false
    var bibleVerse: BibleVerse?
    var bibleStatus=""
    var bibleAvailable=false
    var unreadMessageCount=0
    var biblePage=0
    private(set) var biblePages: [String] = []
    var action: ((SpeechBubble.Action)->Void)?
    let controls=NSView()
    private var rows: [NSView] = []
    private var reader=false
    private static let ink=NSColor(srgbRed:PetConstants.Speech.ink.red,green:PetConstants.Speech.ink.green,blue:PetConstants.Speech.ink.blue,alpha:1)
    private var fallbackRect: NSRect {
        let r=PetConstants.Speech.fallback
        return NSRect(x:bounds.width*r.x,y:bounds.height*r.y,width:bounds.width*r.width,height:bounds.height*r.height)
    }
    override var isOpaque: Bool { false }
    func containsPaintedPoint(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        guard masks.indices.contains(frameIndex) else { return fallbackRect.contains(point) }
        let n=PetConstants.Assets.maskSize
        let x=min(n-1,Int(point.x/bounds.width*Double(n))), y=min(n-1,Int(point.y/bounds.height*Double(n)))
        return masks[frameIndex][(n-1-y)*n+(flippedArtwork ? n-1-x : x)] > PetConstants.Assets.alphaThreshold
    }
    override func hitTest(_ point: NSPoint) -> NSView? { containsPaintedPoint(point) ? super.hitTest(point) : nil }
    override init(frame: NSRect) {
        super.init(frame:frame); autoresizingMask=[.width,.height]; addSubview(controls)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func textHeight(_ value: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(value.boundingRect(with:NSSize(width:max(1,width),height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)
    }
    private func rowHeight(_ row: NSView, width: CGFloat) -> CGFloat {
        let padding=PetConstants.Speech.verticalTextPadding
        if let button=row as? BubbleButton { return max(PetConstants.Speech.buttonHeight,button.preferredHeight) }
        if let navigation=row as? BubbleNavigation { return navigation.preferredHeight }
        if let label=row as? NSTextField { return textHeight(label.attributedStringValue,width:width-2*PetConstants.Speech.horizontalTextPadding)+2*padding }
        if let scroll=row as? NSScrollView, let text=scroll.documentView as? NSTextView {
            return min(PetConstants.Speech.readerMaximumTextHeight,max(PetConstants.Speech.readerMinimumTextHeight,textHeight(text.attributedString(),width:width-16)))
        }
        return 0
    }
    var preferredSize: NSSize {
        let region=PetConstants.Speech.controls
        let widest=rows.compactMap { row -> Double? in
            guard let button=row as? BubbleButton else { return nil }
            return ceil(button.attributedTitle.size().width)+2*PetConstants.Speech.horizontalTextPadding+(button.reservesNotificationSpace ? 20 : 0)
        }.max() ?? 0
        let width=reader ? PetConstants.Speech.readerWidth : max(PetConstants.Speech.width,ceil(widest/region.width))
        let contentHeight=rows.reduce(0) { $0+rowHeight($1,width:width*region.width) }+Double(max(0,rows.count-1))*PetConstants.Speech.controlSpacing
        let height=max(reader ? PetConstants.Speech.readerMinimumHeight : PetConstants.Speech.height,ceil(contentHeight/region.height))
        return NSSize(width:width,height:reader ? min(PetConstants.Speech.readerMaximumHeight,height) : height)
    }
    override func layout() {
        super.layout()
        let r=PetConstants.Speech.controls
        controls.frame=NSRect(x:bounds.width*r.x,y:bounds.height*r.y,width:bounds.width*r.width,height:bounds.height*r.height)
        let sizes=rows.map { rowHeight($0,width:controls.bounds.width) }
        let total=sizes.reduce(0,+)+Double(max(0,rows.count-1))*PetConstants.Speech.controlSpacing
        let overflow=max(0,total-controls.bounds.height)
        var y=controls.bounds.height
        for (index,row) in rows.enumerated() {
            var height=sizes[index]
            if row is NSScrollView { height=max(20,height-overflow) }
            y-=height
            row.frame=NSRect(x:0,y:y,width:controls.bounds.width,height:height)
            if let label=row as? NSTextField { label.preferredMaxLayoutWidth=row.bounds.width }
            if let scroll=row as? NSScrollView, let text=scroll.documentView as? NSTextView {
                let width=scroll.contentSize.width
                text.setFrameSize(NSSize(width:width,height:height))
                if let container=text.textContainer, let manager=text.layoutManager {
                    container.containerSize=NSSize(width:max(1,width-2*text.textContainerInset.width),height:100000)
                    manager.ensureLayout(for:container)
                    let required=ceil(manager.usedRect(for:container).height)+2*text.textContainerInset.height
                    text.setFrameSize(NSSize(width:width,height:max(height,required)))
                }
            }
            y-=PetConstants.Speech.controlSpacing
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context=NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); context.interpolationQuality = .high
        if flippedArtwork { context.translateBy(x:bounds.width,y:0); context.scaleBy(x:-1,y:1) }
        if images.indices.contains(frameIndex) {
            let crop=PetConstants.Speech.crop, sx=bounds.width/crop.width, sy=bounds.height/crop.height
            context.draw(images[frameIndex],in:NSRect(x:-crop.x*sx,y:-crop.y*sy,width:PetConstants.Speech.sourceWidth*sx,height:PetConstants.Speech.sourceHeight*sy))
        } else {
            let paper=PetConstants.Speech.paper
            NSColor(calibratedRed:paper.red,green:paper.green,blue:paper.blue,alpha:1).setFill()
            NSBezierPath(roundedRect:fallbackRect,xRadius:bounds.width*PetConstants.Speech.fallbackCorner.x,yRadius:bounds.height*PetConstants.Speech.fallbackCorner.y).fill()
        }
        context.restoreGState()
    }
    private func add(_ row: NSView) { rows.append(row); controls.addSubview(row) }
    func configure(mode: SpeechBubble.Mode) {
        for row in rows { row.removeFromSuperview() }; rows.removeAll(); reader=mode == .bible
        switch mode {
        case .menu:
            button("Go away…",.goAway)
            let messages=makeButton("Show message",.seePhoto)
            messages.reservesNotificationSpace=true; messages.hasNewMessage=unreadMessageCount>0
            messages.setAccessibilityLabel("Show message\(unreadMessageCount>0 ? ", \(unreadMessageCount) new" : "")")
            add(messages)
            button("Send message",.sendPhoto)
            if bibleAvailable { button("Read Bible verse",.readBible) }
        case .away:
            button("Until I call you",.away(nil))
            for minutes in PetConstants.Interaction.awayMinuteOptions {
                let duration = minutes < 60 ? "\(minutes) minutes" : "\(minutes / 60) hour\(minutes == 60 ? "" : "s")"
                button("In \(duration)",.away(minutes))
            }
            button("Back",.back)
        case .bible:
            if let verse=bibleVerse {
                label(verse.reference,size:PetConstants.Speech.headingFontSize)
                let width=PetConstants.Speech.readerWidth*PetConstants.Speech.controls.width-32
                biblePages=BiblePagination.pages(verse.text) { text in
                    self.textHeight(self.verseAttributed(text.trimmingCharacters(in:.whitespacesAndNewlines)),width:width) <= PetConstants.Speech.readerMaximumTextHeight-2*PetConstants.Speech.verticalTextPadding
                }
                biblePage=min(max(0,biblePage),biblePages.count-1)
                verseText(biblePages[biblePage].trimmingCharacters(in:.whitespacesAndNewlines))
                if biblePages.count>1 {
                    let previous=makeButton("Previous",.previousBiblePage,enabled:biblePage>0)
                    previous.setAccessibilityLabel("Previous page")
                    let next=makeButton("Next",.nextBiblePage,enabled:biblePage<biblePages.count-1)
                    next.setAccessibilityLabel("Next page")
                    add(BubbleNavigation(previous:previous,next:next,page:biblePage+1,count:biblePages.count))
                }
            } else {
                biblePages=[]; label("Today's Bible verse",size:PetConstants.Speech.headingFontSize)
                label(bibleStatus,size:PetConstants.Speech.readerFontSize); button("Back",.back)
            }
        }
        needsLayout=true
    }
    private func label(_ value: String, size: CGFloat = PetConstants.Speech.bodyFontSize) {
        let label=BubbleLabel(wrappingLabelWithString:value)
        label.font=AppTypography.font(size:size); label.textColor=Self.ink
        label.attributedStringValue=NSAttributedString(string:value,attributes:[.font:AppTypography.font(size:size),.foregroundColor:Self.ink])
        add(label)
    }
    func changeBiblePage(by delta: Int) {
        guard !biblePages.isEmpty else { return }
        biblePage=min(biblePages.count-1,max(0,biblePage+delta)); configure(mode:.bible)
    }
    private func verseAttributed(_ value: String) -> NSAttributedString {
        let paragraph=NSMutableParagraphStyle(); paragraph.lineSpacing=2; paragraph.paragraphSpacing=6
        return NSAttributedString(string:value,attributes:[.font:AppTypography.font(size:PetConstants.Speech.readerFontSize),.foregroundColor:Self.ink,.paragraphStyle:paragraph])
    }
    private func verseText(_ value: String) {
        let scroll=NSScrollView(); scroll.drawsBackground=false; scroll.hasVerticalScroller=true; scroll.autohidesScrollers=true
        let text=NSTextView(frame:.zero); text.isEditable=false; text.isSelectable=true; text.drawsBackground=false
        text.isVerticallyResizable=true; text.isHorizontallyResizable=false
        text.textContainerInset=NSSize(width:PetConstants.Speech.horizontalTextPadding,height:PetConstants.Speech.verticalTextPadding)
        text.textContainer?.widthTracksTextView=true; text.textContainer?.heightTracksTextView=false
        text.textStorage?.setAttributedString(verseAttributed(value))
        text.setAccessibilityLabel("Bible verse text"); scroll.documentView=text; add(scroll)
    }
    private func button(_ title: String, _ value: SpeechBubble.Action, enabled: Bool = true) {
        add(makeButton(title,value,enabled:enabled))
    }
    private func makeButton(_ title: String, _ value: SpeechBubble.Action, enabled: Bool = true) -> BubbleButton {
        let button=BubbleButton(title:title,target:nil,action:nil)
        button.font=AppTypography.font(size:PetConstants.Speech.bodyFontSize)
        button.attributedTitle=NSAttributedString(string:title,attributes:[.font:button.font!,.foregroundColor:Self.ink])
        button.isEnabled=enabled
        button.isBordered=false; button.alignment = .left; button.setAccessibilityLabel(title)
        button.target=button; button.action=#selector(BubbleButton.invoke)
        button.handler={ [weak self] in self?.action?(value) }
        return button
    }
}
private final class BubbleNavigation: NSView {
    private let previous: BubbleButton
    private let next: BubbleButton
    private let counter: BubbleLabel
    var preferredHeight: CGFloat {
        ceil(previous.font!.ascender-previous.font!.descender+previous.font!.leading)+2*PetConstants.Speech.verticalTextPadding
    }
    init(previous: BubbleButton, next: BubbleButton, page: Int, count: Int) {
        self.previous=previous; self.next=next
        counter=BubbleLabel(labelWithString:"\(page)/\(count)")
        super.init(frame:.zero)
        counter.attributedStringValue=NSAttributedString(string:counter.stringValue,attributes:[.font:previous.font!,
            .foregroundColor:NSColor(srgbRed:PetConstants.Speech.ink.red,green:PetConstants.Speech.ink.green,blue:PetConstants.Speech.ink.blue,alpha:1)])
        counter.setAccessibilityLabel("Page \(page) of \(count)")
        addSubview(previous); addSubview(counter); addSubview(next)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        let padding=2*PetConstants.Speech.horizontalTextPadding
        let previousWidth=ceil(previous.attributedTitle.size().width)+padding
        let nextWidth=ceil(next.attributedTitle.size().width)+padding
        let counterWidth=ceil(counter.attributedStringValue.size().width)+padding
        previous.frame=NSRect(x:0,y:0,width:previousWidth,height:bounds.height)
        next.frame=NSRect(x:bounds.width-nextWidth,y:0,width:nextWidth,height:bounds.height)
        counter.frame=NSRect(x:(previousWidth+bounds.width-nextWidth-counterWidth)/2,y:0,width:counterWidth,height:bounds.height)
    }
}
private final class BubbleLabel: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        attributedStringValue.draw(in:bounds.insetBy(dx:PetConstants.Speech.horizontalTextPadding,dy:PetConstants.Speech.verticalTextPadding))
    }
}
private final class BubbleButton: NSButton {
    override var isFlipped: Bool { false }
    var handler: (()->Void)?
    var hasNewMessage=false
    var reservesNotificationSpace=false
    private var titleHeight: CGFloat { ceil(font!.ascender-font!.descender+font!.leading) }
    var preferredHeight: CGFloat { titleHeight+2*PetConstants.Speech.verticalTextPadding }
    override func draw(_ dirtyRect: NSRect) {
        // Native mini-button cells crop Matcha's tall glyphs. Draw the accessible
        // button's title in an explicitly padded row using the actual font metrics.
        let ink=NSColor(srgbRed:PetConstants.Speech.ink.red,green:PetConstants.Speech.ink.green,blue:PetConstants.Speech.ink.blue,alpha:isEnabled ? 1 : 0.45)
        let content=bounds.insetBy(dx:PetConstants.Speech.horizontalTextPadding,dy:PetConstants.Speech.verticalTextPadding)
        let textRect=NSRect(x:content.minX,y:content.maxY-titleHeight,width:content.width-(reservesNotificationSpace ? 20 : 0),height:titleHeight)
        (isEnabled ? attributedTitle : NSAttributedString(string:title,attributes:[.font:font!,.foregroundColor:ink])).draw(in:textRect)
        if hasNewMessage, let image=NotificationArtwork.frames.first, let context=NSGraphicsContext.current?.cgContext {
            context.draw(image,in:NSRect(x:content.maxX-18,y:textRect.midY-9,width:18,height:18))
        }
    }
    @objc func invoke() { handler?() }
}
