import AppKit
import AVKit
import UniformTypeIdentifiers
import PetCore
import PetAssets

/// The wire format contains plain text and these three styles only. Native text
/// attachments, links, font names, and pasted object archives never leave the app.
enum MessageRichText {
    static func body(from value: NSAttributedString) -> RichMessageBody {
        var runs: [RichTextRun] = []
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            let text = (value.string as NSString).substring(with: range).replacingOccurrences(of: "\u{fffc}", with: "")
            guard !text.isEmpty else { return }
            let font = attributes[.font] as? NSFont ?? AppTypography.font(size: 18)
            let traits = NSFontManager.shared.traits(of: font)
            let run = RichTextRun(text: text,
                                  bold: traits.contains(.boldFontMask) || ((attributes[.strokeWidth] as? NSNumber)?.doubleValue ?? 0) < 0,
                                  italic: traits.contains(.italicFontMask) || ((attributes[.obliqueness] as? NSNumber)?.doubleValue ?? 0) != 0,
                                  underline: ((attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0)
            if let previous = runs.last, previous.bold == run.bold, previous.italic == run.italic, previous.underline == run.underline {
                runs[runs.count-1] = RichTextRun(text: previous.text+run.text, bold: run.bold, italic: run.italic, underline: run.underline)
            } else { runs.append(run) }
        }
        return RichMessageBody(runs: runs)
    }

    static func attributed(from body: RichMessageBody) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in body.runs {
            var attributes: [NSAttributedString.Key: Any] = [.font: AppTypography.font(size: 18), .foregroundColor: PolaroidStyle.ink]
            // Matcha Style has one face. AppKit's synthetic stroke and slant keep
            // its lettering while preserving the wire format's explicit styles.
            if run.bold { attributes[.strokeWidth] = -2.5 }
            if run.italic { attributes[.obliqueness] = 0.18 }
            if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }
}

/// A regular key-capable window: editing never changes the duck panel's focus policy.
final class MessageComposerWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    let window = PolaroidWindow(title: "Send a photo")
    let cameraPreviewHost = NSView()
    var onSend: ((NSAttributedString, URL?) -> Void)?
    var onCamera: (() -> Void)?
    var onCapture: (() -> Void)?
    var onCameraDeviceSelected: ((String) -> Void)?
    var onStopCamera: (() -> Void)?
    var onClose: (() -> Void)?
    var onDraftChanged: ((NSAttributedString, URL?) -> Void)?

    private let editor = PolaroidTextView()
    private let media = MessageMediaView()
    private let paper = PolaroidCanvas()
    private let status = PolaroidStyle.label(size: 11)
    private let date = PolaroidStyle.label(size: 12)
    private let sendButton = PolaroidButton("Send", drawing: .send, target: nil, action: nil)
    private let removeButton = PolaroidButton("Remove attachment", drawing: .remove, target: nil, action: nil)
    private let cameraButton = PolaroidButton("Camera", target: nil, action: nil)
    private let captureButton = PolaroidButton("Capture", drawing: .shutter, target: nil, action: nil)
    private let devicePicker = PolaroidCameraPicker()
    private let cameraControls = NSView()
    private let topControls = NSView()
    private let attachButton = PolaroidButton("Attach photo or video", drawing: .attachment, target: nil, action: nil)
    private let closeButton = PolaroidButton("Close", drawing: .close, target: nil, action: nil)
    private var formatButtons: [PolaroidButton] = []
    private var scroll: NSScrollView!
    private var attachmentURL: URL?
    private var cameraActive = false
    private var cameraReady = false
    private var busy = false
    private var hasShown = false

    var draftText: NSAttributedString { NSAttributedString(attributedString: editor.attributedString()) }
    var draftAttachmentURL: URL? { attachmentURL }
    var hasDraft: Bool { !MessageRichText.body(from: editor.attributedString()).plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachmentURL != nil }

    override init() {
        super.init()
        window.delegate = self
        paper.frame = window.contentView!.bounds; paper.autoresizingMask = [.width, .height]
        window.contentView = paper
        media.translatesAutoresizingMaskIntoConstraints = true
        media.onDrop = { [weak self] url in self?.chooseAttachment(url) }
        paper.addSubview(media)
        cameraPreviewHost.autoresizingMask = [.width, .height]; media.addSubview(cameraPreviewHost)
        cameraPreviewHost.isHidden = true
        paper.addSubview(topControls)
        [closeButton, cameraButton, attachButton, removeButton, cameraControls].forEach { topControls.addSubview($0) }
        closeButton.target = self; closeButton.action = #selector(closeWindow)
        attachButton.target = self; attachButton.action = #selector(pickAttachment)
        removeButton.target = self; removeButton.action = #selector(removeAttachment)
        devicePicker.target = self; devicePicker.action = #selector(changeCameraDevice)
        devicePicker.isBordered = false; devicePicker.font = AppTypography.font(size: 12)
        devicePicker.menu?.font = AppTypography.font(size: 13)
        devicePicker.setAccessibilityLabel("Choose camera")
        captureButton.target = self; captureButton.action = #selector(capturePhoto)
        [devicePicker, captureButton].forEach { cameraControls.addSubview($0) }
        for (title, label, selector) in [("B", "Bold", #selector(toggleBold)), ("I", "Italic", #selector(toggleItalic)), ("U", "Underline", #selector(toggleUnderline))] {
            let button = PolaroidButton(title, target: self, action: selector)
            button.setAccessibilityLabel(label); button.toolTip = label
            button.keyEquivalent=title.lowercased(); button.keyEquivalentModifierMask = [.command]
            formatButtons.append(button); paper.addSubview(button)
        }
        editor.isRichText = true; editor.importsGraphics = false; editor.allowsUndo = true
        editor.delegate = self
        editor.setAccessibilityLabel("Message text")
        scroll = PolaroidStyle.scroll(for: editor); paper.addSubview(scroll)
        paper.addSubview(status); paper.addSubview(date)
        cameraButton.target = self; cameraButton.action = #selector(requestCamera)
        sendButton.target = self; sendButton.action = #selector(send)
        sendButton.keyEquivalent = "\r"; sendButton.keyEquivalentModifierMask = [.command]
        paper.addSubview(sendButton)
        paper.onLayout = { [weak self] in self?.layoutPaper() }
        media.clear(message: "Camera preview")
        layoutPaper()
        updateAvailability()
    }

    private func layoutPaper() {
        media.frame = paper.mediaRect; cameraPreviewHost.frame = media.bounds
        topControls.frame = paper.controlsRect
        let height = topControls.bounds.height
        closeButton.frame = NSRect(x: 0, y: 0, width: 22, height: height)
        cameraButton.frame = NSRect(x: 29, y: 0, width: 57, height: height)
        attachButton.frame = NSRect(x: 92, y: 0, width: 27, height: height)
        removeButton.frame = NSRect(x: 121, y: 0, width: 25, height: height)
        let cameraX: CGFloat = attachmentURL == nil ? 128 : 152
        cameraControls.frame = NSRect(x: cameraX, y: 0, width: topControls.bounds.width-cameraX, height: height)
        devicePicker.frame = NSRect(x: 0, y: 0, width: max(50,cameraControls.bounds.width-37), height: height)
        captureButton.frame = NSRect(x: cameraControls.bounds.width-31, y: -3, width: 31, height: height+6)
        scroll.frame = paper.writingRect
        editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height,editor.frame.height)))
        let footer = paper.footerRect
        date.frame = NSRect(x: footer.minX, y: footer.minY+5, width: footer.width*0.44, height: 18)
        for (index,button) in formatButtons.enumerated() {
            button.frame = NSRect(x: footer.minX+footer.width*0.48+CGFloat(index)*24, y: footer.minY, width: 23, height: footer.height)
        }
        sendButton.frame = NSRect(x: footer.maxX-62, y: footer.minY-1, width: 64, height: footer.height+2)
        status.frame = paper.statusRect
    }

    func show() {
        if !hasShown { window.center(); hasShown = true }
        date.stringValue = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
    }

    func setDraft(text: NSAttributedString, attachmentURL: URL?) {
        editor.textStorage?.setAttributedString(MessageRichText.attributed(from: MessageRichText.body(from: text)))
        if text.length == 0 {
            editor.typingAttributes = [.font: AppTypography.font(size:18), .foregroundColor: PolaroidStyle.ink]
        }
        setAttachment(attachmentURL); updateAvailability()
    }

    func setAttachment(_ url: URL?) {
        attachmentURL = url
        let wasUsingCamera = cameraActive
        setCameraPreviewActive(false, ready: false)
        if wasUsingCamera { onStopCamera?() }
        removeButton.isHidden = url == nil
        if let url {
            media.load(url: url) { [weak self] error in
                if let error { self?.status.stringValue = error.localizedDescription }
            }
        } else { media.clear(message: "Camera preview") }
        layoutPaper(); updateAvailability(); notifyDraftChanged()
    }

    func setStatus(_ value: String, isBusy: Bool = false) {
        // Routine connection chatter does not belong on the handwritten card.
        let routine = ["Connected", "Connected.", "Ready", "Not connected", "Not connected."]
        status.stringValue = routine.contains(value) ? "" : value
        status.toolTip = value; busy = isBusy
        editor.isEditable = !isBusy; updateAvailability()
    }

    /// Call only after the service has durably accepted the user's explicit Send.
    func resetAfterSend() {
        editor.string = ""; setAttachment(nil)
        editor.typingAttributes = [.font: AppTypography.font(size:18), .foregroundColor: PolaroidStyle.ink]
        setStatus("Saved to outbox")
        notifyDraftChanged()
    }

    func setCameraDevices(_ devices: [(id: String, name: String)], selectedID: String?) {
        devicePicker.removeAllItems()
        for device in devices {
            devicePicker.addItem(withTitle: device.name)
            devicePicker.lastItem?.representedObject = device.id
            if device.id == selectedID { devicePicker.select(devicePicker.lastItem) }
        }
        updateAvailability()
    }

    func setCameraPreviewActive(_ active: Bool, ready: Bool = false) {
        cameraActive = active; cameraReady = ready
        cameraPreviewHost.isHidden = !active
        cameraButton.title = active ? "Stop" : (attachmentURL == nil ? "Camera" : "Retake")
        cameraButton.setAccessibilityLabel(active ? "Stop camera" : "Start camera")
        if active { media.pause() }
        updateAvailability()
    }

    func windowWillClose(_ notification: Notification) {
        media.pause(); onStopCamera?(); notifyDraftChanged(); onClose?()
    }
    func textDidChange(_ notification: Notification) {
        // Rich paste may bring another font or color; retain its three supported
        // styles while keeping all visible writing in the project face.
        var needsNormalization = false
        let font=AppTypography.font(size:18)
        editor.attributedString().enumerateAttributes(in:NSRange(location:0,length:editor.string.utf16.count)) { attributes,_,_ in
            let supplied=attributes[.font] as? NSFont
            if supplied?.fontName != font.fontName || supplied?.pointSize != font.pointSize ||
                (attributes[.foregroundColor] as? NSColor) != PolaroidStyle.ink || attributes[.link] != nil {
                needsNormalization = true
            }
        }
        if needsNormalization {
            let selection=editor.selectedRange()
            editor.textStorage?.setAttributedString(MessageRichText.attributed(from:MessageRichText.body(from:editor.attributedString())))
            editor.setSelectedRange(selection)
        }
        editor.needsDisplay=true; updateAvailability(); notifyDraftChanged()
    }
    private func notifyDraftChanged() { onDraftChanged?(draftText, attachmentURL) }
    private func updateAvailability() {
        sendButton.isEnabled = hasDraft && !busy && !cameraActive
        removeButton.isEnabled = attachmentURL != nil && !busy
        cameraButton.isEnabled = !busy
        captureButton.isEnabled = cameraActive && cameraReady && !busy
        attachButton.isEnabled = !busy
        devicePicker.isEnabled = cameraActive && cameraReady && !busy && devicePicker.numberOfItems > 1
        formatButtons.forEach { $0.isEnabled = !busy }
    }
    @objc private func send() {
        guard sendButton.isEnabled else { return }
        onSend?(draftText, attachmentURL)
    }
    @objc private func pickAttachment() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.chooseAttachment(url) }
        }
    }
    private func chooseAttachment(_ url: URL) {
        guard !busy, url.isFileURL else { return }
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]), values.isRegularFile == true,
              let type = values.contentType ?? UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) || type.conforms(to: .movie) else {
            setStatus("Choose a supported photo or video file."); return
        }
        onStopCamera?(); setAttachment(url); setStatus("")
    }
    @objc private func removeAttachment() { setAttachment(nil) }
    @objc private func requestCamera() {
        guard !busy else { return }
        if cameraActive { stopCamera() } else { onCamera?() }
    }
    @objc private func closeWindow() { window.close() }
    @objc private func capturePhoto() { guard captureButton.isEnabled else { return }; onCapture?() }
    @objc private func stopCamera() { onStopCamera?(); setCameraPreviewActive(false) }
    @objc private func changeCameraDevice() {
        if let id = devicePicker.selectedItem?.representedObject as? String { onCameraDeviceSelected?(id) }
    }
    @objc private func toggleBold() { toggleStyle(.boldFontMask) }
    @objc private func toggleItalic() { toggleStyle(.italicFontMask) }
    private func toggleStyle(_ trait: NSFontTraitMask) {
        let key: NSAttributedString.Key = trait == .boldFontMask ? .strokeWidth : .obliqueness
        let enabledValue: Double = trait == .boldFontMask ? -2.5 : 0.18
        let range = editor.selectedRange()
        if range.length == 0 {
            var attributes = editor.typingAttributes
            attributes[.font] = AppTypography.font(size:18)
            attributes[key] = ((attributes[key] as? NSNumber)?.doubleValue ?? 0) == 0 ? enabledValue : 0
            editor.typingAttributes = attributes
        } else if let storage = editor.textStorage {
            guard editor.shouldChangeText(in:range,replacementString:nil) else { return }
            let active = ((storage.attribute(key,at:range.location,effectiveRange:nil) as? NSNumber)?.doubleValue ?? 0) != 0
            storage.beginEditing(); storage.addAttribute(key,value:active ? 0 : enabledValue,range:range)
            storage.addAttribute(.font,value:AppTypography.font(size:18),range:range)
            storage.endEditing(); editor.didChangeText()
        }
        window.makeFirstResponder(editor)
    }
    @objc private func toggleUnderline() {
        let range = editor.selectedRange()
        if range.length == 0 {
            var attributes = editor.typingAttributes
            let old = (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0
            attributes[.underlineStyle] = old == 0 ? NSUnderlineStyle.single.rawValue : 0
            editor.typingAttributes = attributes
        } else if let storage = editor.textStorage {
            guard editor.shouldChangeText(in:range,replacementString:nil) else { return }
            let old = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            storage.addAttribute(.underlineStyle, value: old == 0 ? NSUnderlineStyle.single.rawValue : 0, range: range)
            editor.didChangeText()
        }
        window.makeFirstResponder(editor)
    }
}

/// Read receipts are emitted only after the selected message's optional media is
/// loaded and this window is visible. Failed/stale downloads never mark it read.
final class MessageInboxWindow: NSObject, NSWindowDelegate {
    private(set) var lastMediaError: Error?
    let identifier = UUID().uuidString
    private(set) var isKept = false
    let window = PolaroidWindow(title: "A photo for you")
    var onAttachmentNeeded: ((ChatMessage) -> Void)?
    var onPresented: ((ChatMessage) -> Void)?
    var onClose: (() -> Void)?
    var onKeep: (() -> Void)?
    private let currentDeviceID: String
    private let media = MessageMediaView()
    private let text = NSTextView()
    private let paper = PolaroidCanvas()
    private let heading = PolaroidStyle.label(size: 11)
    private let count = PolaroidStyle.label(size: 12)
    private let status = PolaroidStyle.label(size: 11)
    private let previous = PolaroidButton("Previous", drawing: .previous, target: nil, action: nil)
    private let next = PolaroidButton("Next", drawing: .next, target: nil, action: nil)
    private let retry = PolaroidButton("Retry", target: nil, action: nil)
    private let keep = PolaroidButton("Keep", drawing: .send, target: nil, action: nil)
    private let close = PolaroidButton("Close", target: nil, action: nil)
    private let topClose = PolaroidButton("Close", drawing: .close, target: nil, action: nil)
    private var scroll: NSScrollView!
    private var messages: [ChatMessage] = []
    private var selection = 0
    private var active = false
    private var loaded = false
    private var presented: Set<String> = []
    private var selectedAttachmentURL: URL?
    private var generation = 0
    private var hasShown = false

    init(currentDeviceID: String) {
        self.currentDeviceID = currentDeviceID
        super.init()
        window.delegate = self
        let minimum=PolaroidStyle.minimumViewingWidth
        window.contentMinSize=NSSize(width:minimum,height:minimum*1384/1140)
        paper.frame = window.contentView!.bounds; paper.autoresizingMask = [.width, .height]
        window.contentView = paper
        media.translatesAutoresizingMaskIntoConstraints = true; paper.addSubview(media)
        text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.importsGraphics = false
        text.setAccessibilityLabel("Message")
        scroll = PolaroidStyle.scroll(for: text); paper.addSubview(scroll)
        [heading,count,status,previous,next,retry,keep,close,topClose].forEach { paper.addSubview($0) }
        count.alignment = .center
        previous.target = self; previous.action = #selector(previousMessage)
        next.target = self; next.action = #selector(nextMessage)
        retry.target = self; retry.action = #selector(retryAttachment); retry.isHidden = true
        keep.target = self; keep.action = #selector(keepPhoto)
        keep.toolTip = "Keep this Polaroid on screen and let the duck put its photo away"
        [close,topClose].forEach { $0.target = self; $0.action = #selector(closeWindow) }
        paper.onLayout = { [weak self] in self?.layoutPaper() }
        layoutPaper()
        updateNavigation()
    }

    private func layoutPaper() {
        media.frame = paper.mediaRect; scroll.frame = paper.writingRect
        text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height,text.frame.height)))
        let top = paper.controlsRect
        topClose.frame = NSRect(x:top.minX,y:top.minY,width:22,height:top.height)
        previous.frame = NSRect(x:top.midX-75,y:top.minY,width:24,height:top.height)
        count.frame = NSRect(x:top.midX-45,y:top.minY+4,width:90,height:top.height)
        next.frame = NSRect(x:top.midX+51,y:top.minY,width:24,height:top.height)
        retry.frame = NSRect(x:top.maxX-50,y:top.minY,width:50,height:top.height)
        let footer=paper.footerRect
        heading.frame = NSRect(x:footer.minX,y:footer.minY+5,width:footer.width-130,height:18)
        close.frame = NSRect(x:footer.maxX-62,y:footer.minY,width:64,height:footer.height)
        keep.frame = NSRect(x:footer.maxX-125,y:footer.minY,width:60,height:footer.height)
        status.frame=paper.statusRect
    }

    func show(messages: [ChatMessage], selectedID: String? = nil) {
        active = true; presented.removeAll()
        if !hasShown { window.center(); hasShown = true }
        let oldID = selectedMessage?.id
        setMessages(messages, selectedID: selectedID)
        if oldID == selectedMessage?.id { renderSelection() }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        notifyPresentedIfReady()
    }
    func setMessages(_ messages: [ChatMessage], selectedID: String? = nil) {
        let oldID = selectedMessage?.id
        self.messages = messages.sorted { $0.createdAt < $1.createdAt }
        let preferredID = selectedID ?? oldID
        if let preferredID, let index = self.messages.firstIndex(where: { $0.id == preferredID }) { selection = index }
        else { selection = self.messages.firstIndex(where: { $0.recipientID == currentDeviceID && $0.readAt == nil }) ?? max(0, self.messages.count-1) }
        if oldID == selectedMessage?.id, oldID != nil {
            updateHeading(); updateNavigation(); return
        }
        renderSelection()
    }
    func setStatus(_ value: String) { status.stringValue = value; status.toolTip=value }
    func setAttachment(_ url: URL, for messageID: String) {
        guard active, selectedMessage?.id == messageID else { return }
        lastMediaError=nil
        selectedAttachmentURL = url; let token = generation
        media.load(url: url, mediaType: selectedMessage?.attachment?.mediaType) { [weak self] error in
            guard let self, self.active, self.generation == token, self.selectedMessage?.id == messageID else { return }
            if let error { self.lastMediaError=error; self.showAttachmentError(error.localizedDescription, for: messageID) }
            else { self.loaded = true; self.status.stringValue = ""; self.retry.isHidden = true; self.updateNavigation(); self.notifyPresentedIfReady() }
        }
    }
    func showAttachmentError(_ message: String, for messageID: String) {
        guard active, selectedMessage?.id == messageID else { return }
        loaded = false; selectedAttachmentURL = nil
        media.clear(message: "Attachment unavailable")
        setStatus(message); retry.isHidden = false; updateNavigation()
    }
    func windowWillClose(_ notification: Notification) {
        active = false; generation += 1; loaded = false; media.clear(message: ""); onClose?()
    }
    func windowDidBecomeKey(_ notification: Notification) { notifyPresentedIfReady() }
    private var selectedMessage: ChatMessage? { messages.indices.contains(selection) ? messages[selection] : nil }
    private func updateHeading() {
        guard let message = selectedMessage else { heading.stringValue = ""; return }
        let receipt=message.senderID == currentDeviceID ? (message.readAt == nil ? " · Sent" : " · Read") : ""
        heading.stringValue = DateFormatter.localizedString(from:message.createdAt,dateStyle:.medium,timeStyle:.none)+receipt
        heading.toolTip = "\(message.senderID == currentDeviceID ? "You" : "Your person") · \(DateFormatter.localizedString(from:message.createdAt,dateStyle:.medium,timeStyle:.short))\(receipt)"
    }
    private func updateNavigation() {
        previous.isEnabled = selection > 0
        next.isEnabled = selection+1 < messages.count
        count.stringValue = messages.isEmpty ? "" : "\(selection+1) / \(messages.count)"
        [previous,count,next].forEach { $0.isHidden = isKept || messages.count < 2 }
        keep.isEnabled = loaded && selectedMessage != nil; keep.isHidden = isKept
    }
    private func renderSelection() {
        lastMediaError=nil
        generation += 1; loaded = false; selectedAttachmentURL = nil
        media.pause(); retry.isHidden = true; status.stringValue = ""
        updateHeading(); updateNavigation()
        guard let message = selectedMessage else {
            text.string = ""; media.clear(message: "A message will appear here when it arrives."); return
        }
        text.textStorage?.setAttributedString(MessageRichText.attributed(from: message.body))
        if message.attachment != nil {
            media.clear(message: "Loading attachment…"); onAttachmentNeeded?(message)
        } else {
            media.clear(message: ""); loaded = true; updateNavigation(); notifyPresentedIfReady()
        }
    }
    private func notifyPresentedIfReady() {
        guard active, loaded, window.isVisible, !window.isMiniaturized, let message = selectedMessage,
              message.recipientID == currentDeviceID, !presented.contains(message.id) else { return }
        // Deliver after the current layout/display cycle; closing or selecting
        // another message before then invalidates the pending receipt.
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, self.loaded, self.window.isVisible, !self.window.isMiniaturized,
                  self.generation == token, self.selectedMessage?.id == message.id,
                  self.presented.insert(message.id).inserted else { return }
            self.onPresented?(message)
        }
    }
    @objc private func previousMessage() { guard selection > 0 else { return }; selection -= 1; renderSelection() }
    @objc private func nextMessage() { guard selection+1 < messages.count else { return }; selection += 1; renderSelection() }
    @objc private func closeWindow() { window.close() }
    @objc private func keepPhoto() {
        guard active, loaded, !isKept, selectedMessage != nil else { return }
        isKept=true; window.level = .floating; window.hidesOnDeactivate=false
        updateNavigation(); onKeep?()
    }
    @objc private func retryAttachment() {
        guard let message = selectedMessage, message.attachment != nil else { return }
        retry.isHidden = true; media.clear(message: "Loading attachment…"); onAttachmentNeeded?(message)
    }
}

/// Center-crop photos to fill the paper aperture without changing their aspect ratio.
private final class PolaroidImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let destination = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                 width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class MessageMediaView: NSView {
    var onDrop: ((URL) -> Void)?
    private let image = PolaroidImageView()
    private let video = AVPlayerView()
    private let label = NSTextField(wrappingLabelWithString: "Choose a photo or video, or drop one here.")
    private var observation: NSKeyValueObservation?
    private var generation = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 3; layer?.masksToBounds = true
        video.controlsStyle = .inline
        label.alignment = .center; label.textColor = PolaroidStyle.mutedInk; label.font = AppTypography.font(size:16)
        for view in [image, video, label] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo: leadingAnchor), image.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     image.topAnchor.constraint(equalTo: topAnchor), image.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     video.leadingAnchor.constraint(equalTo: leadingAnchor), video.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     video.topAnchor.constraint(equalTo: topAnchor), video.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
                                     label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32)])
        image.isHidden = true; video.isHidden = true
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func clear(message: String) {
        generation += 1; observation = nil; pause(); video.player = nil; image.image = nil
        image.isHidden = true; video.isHidden = true; label.isHidden = false; label.stringValue = message
    }
    func pause() { video.player?.pause() }
    func load(url: URL, mediaType: String? = nil, completion: @escaping (Error?) -> Void) {
        clear(message: "Loading attachment…")
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { completion(CocoaError(.fileNoSuchFile)); return }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        if mediaType?.hasPrefix("video/") == true || type?.conforms(to: .movie) == true {
            let item = AVPlayerItem(url: url.absoluteURL); video.player = AVPlayer(playerItem: item)
            video.isHidden = false; label.isHidden = true; let token = generation
            observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if item.status == .readyToPlay { self.observation = nil; completion(nil) }
                    else if item.status == .failed {
                        self.observation = nil; completion(item.error ?? CocoaError(.fileReadCorruptFile))
                    }
                }
            }
        } else if let loaded = NSImage(contentsOf: url), loaded.isValid {
            image.image = loaded; image.isHidden = false; label.isHidden = true; completion(nil)
        } else { completion(CocoaError(.fileReadCorruptFile)) }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { onDrop != nil && draggedURL(sender) != nil ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let onDrop, let url = draggedURL(sender) else { return false }; onDrop(url); return true
    }
    private func draggedURL(_ sender: NSDraggingInfo) -> URL? {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
}
