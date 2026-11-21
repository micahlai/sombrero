import AppKit
import AVKit
import UniformTypeIdentifiers
import PetCore

/// The wire format contains plain text and these three styles only. Native text
/// attachments, links, font names, and pasted object archives never leave the app.
enum MessageRichText {
    static func body(from value: NSAttributedString) -> RichMessageBody {
        var runs: [RichTextRun] = []
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            let text = (value.string as NSString).substring(with: range).replacingOccurrences(of: "\u{fffc}", with: "")
            guard !text.isEmpty else { return }
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
            let traits = NSFontManager.shared.traits(of: font)
            let run = RichTextRun(text: text, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask),
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
            var font = NSFont.systemFont(ofSize: 14)
            if run.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if run.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }
}

/// A regular key-capable window: editing never changes the duck panel's focus policy.
final class MessageComposerWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    let cameraPreviewHost = NSView()
    var onSend: ((NSAttributedString, URL?) -> Void)?
    var onCamera: (() -> Void)?
    var onCapture: (() -> Void)?
    var onCameraDeviceSelected: ((String) -> Void)?
    var onStopCamera: (() -> Void)?
    var onClose: (() -> Void)?
    var onDraftChanged: ((NSAttributedString, URL?) -> Void)?

    private let editor = NSTextView()
    private let media = MessageMediaView()
    private let attachmentName = NSTextField(labelWithString: "No attachment")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)
    private let cameraButton = NSButton(title: "Take Photo", target: nil, action: nil)
    private let captureButton = NSButton(title: "Capture", target: nil, action: nil)
    private let devicePicker = NSPopUpButton()
    private let cameraControls = NSStackView()
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
        window.title = "Send a message"
        window.minSize = NSSize(width: 480, height: 660)
        window.isReleasedWhenClosed = false; window.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.spacing = 10; root.alignment = .leading
        install(root, in: window.contentView!, inset: 20)
        let heading = NSTextField(labelWithString: "A little something for your person")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        root.addArrangedSubview(heading)

        media.translatesAutoresizingMaskIntoConstraints = false
        media.onDrop = { [weak self] url in self?.chooseAttachment(url) }
        root.addArrangedSubview(media)
        let preferredMediaHeight = media.heightAnchor.constraint(equalToConstant: 240)
        preferredMediaHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([media.widthAnchor.constraint(equalTo: root.widthAnchor), media.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
                                     media.heightAnchor.constraint(lessThanOrEqualToConstant: 270), preferredMediaHeight])
        cameraPreviewHost.translatesAutoresizingMaskIntoConstraints = false
        media.addSubview(cameraPreviewHost)
        NSLayoutConstraint.activate([cameraPreviewHost.leadingAnchor.constraint(equalTo: media.leadingAnchor), cameraPreviewHost.trailingAnchor.constraint(equalTo: media.trailingAnchor),
                                     cameraPreviewHost.topAnchor.constraint(equalTo: media.topAnchor), cameraPreviewHost.bottomAnchor.constraint(equalTo: media.bottomAnchor)])
        cameraPreviewHost.isHidden = true

        let attachmentRow = NSStackView(views: [attachmentName, removeButton]); attachmentRow.spacing = 8
        attachmentName.lineBreakMode = .byTruncatingMiddle; attachmentName.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeButton.target = self; removeButton.action = #selector(removeAttachment)
        root.addArrangedSubview(attachmentRow)
        attachmentRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        devicePicker.target = self; devicePicker.action = #selector(changeCameraDevice)
        devicePicker.setAccessibilityLabel("Camera")
        captureButton.target = self; captureButton.action = #selector(capturePhoto)
        let stop = NSButton(title: "Cancel camera", target: self, action: #selector(stopCamera))
        cameraControls.orientation = .horizontal; cameraControls.spacing = 8
        [devicePicker, captureButton, stop].forEach { cameraControls.addArrangedSubview($0) }
        root.addArrangedSubview(cameraControls); cameraControls.isHidden = true

        let formatRow = NSStackView(); formatRow.spacing = 6
        for (title, selector) in [("Bold", #selector(toggleBold)), ("Italic", #selector(toggleItalic)), ("Underline", #selector(toggleUnderline))] {
            let button = NSButton(title: title, target: self, action: selector)
            button.bezelStyle = .rounded; formatRow.addArrangedSubview(button)
        }
        root.addArrangedSubview(formatRow)
        editor.isRichText = true; editor.importsGraphics = false; editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 14); editor.textColor = .labelColor; editor.delegate = self
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.setAccessibilityLabel("Message text")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = editor
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        root.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let attach = NSButton(title: "Attach Photo or Video…", target: self, action: #selector(pickAttachment))
        cameraButton.target = self; cameraButton.action = #selector(requestCamera)
        sendButton.target = self; sendButton.action = #selector(send)
        sendButton.bezelStyle = .rounded; sendButton.keyEquivalent = "\r"; sendButton.keyEquivalentModifierMask = [.command]
        let actions = NSStackView(views: [attach, cameraButton, sendButton]); actions.spacing = 8
        root.addArrangedSubview(actions)
        updateAvailability()
    }

    func show() {
        if !hasShown { window.center(); hasShown = true }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
    }

    func setDraft(text: NSAttributedString, attachmentURL: URL?) {
        editor.textStorage?.setAttributedString(MessageRichText.attributed(from: MessageRichText.body(from: text)))
        setAttachment(attachmentURL); updateAvailability()
    }

    func setAttachment(_ url: URL?) {
        attachmentURL = url
        let wasUsingCamera = cameraActive
        setCameraPreviewActive(false, ready: false)
        if wasUsingCamera { onStopCamera?() }
        attachmentName.stringValue = url?.lastPathComponent ?? "No attachment"
        if let url {
            media.load(url: url) { [weak self] error in
                if let error { self?.status.stringValue = error.localizedDescription }
            }
        } else { media.clear(message: "Choose a photo or video, or drop one here.") }
        updateAvailability(); notifyDraftChanged()
    }

    func setStatus(_ value: String, isBusy: Bool = false) {
        status.stringValue = value; busy = isBusy
        editor.isEditable = !isBusy; updateAvailability()
    }

    /// Call only after the service has durably accepted the user's explicit Send.
    func resetAfterSend() {
        editor.string = ""; setAttachment(nil)
        setStatus("Message queued. It will send when connected.")
        notifyDraftChanged()
    }

    func setCameraDevices(_ devices: [(id: String, name: String)], selectedID: String?) {
        devicePicker.removeAllItems()
        for device in devices {
            devicePicker.addItem(withTitle: device.name)
            devicePicker.lastItem?.representedObject = device.id
            if device.id == selectedID { devicePicker.select(devicePicker.lastItem) }
        }
        devicePicker.isEnabled = devices.count > 1
    }

    func setCameraPreviewActive(_ active: Bool, ready: Bool = false) {
        cameraActive = active; cameraReady = ready
        cameraPreviewHost.isHidden = !active; cameraControls.isHidden = !active
        if active { media.pause() }
        updateAvailability()
    }

    func windowWillClose(_ notification: Notification) {
        media.pause(); onStopCamera?(); notifyDraftChanged(); onClose?()
    }
    func textDidChange(_ notification: Notification) { updateAvailability(); notifyDraftChanged() }
    private func notifyDraftChanged() { onDraftChanged?(draftText, attachmentURL) }
    private func updateAvailability() {
        sendButton.isEnabled = hasDraft && !busy && !cameraActive
        removeButton.isEnabled = attachmentURL != nil && !busy
        cameraButton.isEnabled = !busy && !cameraActive
        captureButton.isEnabled = cameraActive && cameraReady && !busy
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
    @objc private func requestCamera() { guard !busy else { return }; onCamera?() }
    @objc private func capturePhoto() { guard captureButton.isEnabled else { return }; onCapture?() }
    @objc private func stopCamera() { onStopCamera?(); setCameraPreviewActive(false) }
    @objc private func changeCameraDevice() {
        if let id = devicePicker.selectedItem?.representedObject as? String { onCameraDeviceSelected?(id) }
    }
    @objc private func toggleBold() { toggleStyle(.boldFontMask) }
    @objc private func toggleItalic() { toggleStyle(.italicFontMask) }
    private func toggleStyle(_ trait: NSFontTraitMask) {
        let range = editor.selectedRange()
        if range.length == 0 {
            var attributes = editor.typingAttributes
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 14)
            attributes[.font] = NSFontManager.shared.traits(of: font).contains(trait)
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
            editor.typingAttributes = attributes
        } else if let storage = editor.textStorage {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
                let replacement = NSFontManager.shared.traits(of: font).contains(trait)
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: replacement, range: subrange)
            }
            storage.endEditing(); notifyDraftChanged()
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
            let old = (storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            storage.addAttribute(.underlineStyle, value: old == 0 ? NSUnderlineStyle.single.rawValue : 0, range: range)
            notifyDraftChanged()
        }
        window.makeFirstResponder(editor)
    }
}

/// Read receipts are emitted only after the selected message's optional media is
/// loaded and this window is visible. Failed/stale downloads never mark it read.
final class MessageInboxWindow: NSObject, NSWindowDelegate {
    private(set) var lastMediaError: Error?
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 610),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    var onAttachmentNeeded: ((ChatMessage) -> Void)?
    var onPresented: ((ChatMessage) -> Void)?
    var onClose: (() -> Void)?
    private let currentDeviceID: String
    private let media = MessageMediaView()
    private let text = NSTextView()
    private let heading = NSTextField(labelWithString: "Messages")
    private let count = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let previous = NSButton(title: "Previous", target: nil, action: nil)
    private let next = NSButton(title: "Next", target: nil, action: nil)
    private let retry = NSButton(title: "Try Again", target: nil, action: nil)
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
        window.title = "Messages"; window.minSize = NSSize(width: 440, height: 500)
        window.isReleasedWhenClosed = false; window.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        install(root, in: window.contentView!, inset: 20)
        heading.font = .systemFont(ofSize: 17, weight: .semibold); root.addArrangedSubview(heading)
        root.addArrangedSubview(media)
        let preferredMediaHeight = media.heightAnchor.constraint(equalToConstant: 270)
        preferredMediaHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([media.widthAnchor.constraint(equalTo: root.widthAnchor), media.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
                                     media.heightAnchor.constraint(lessThanOrEqualToConstant: 300), preferredMediaHeight])
        text.isEditable = false; text.isSelectable = true; text.isRichText = true; text.importsGraphics = false
        text.font = .systemFont(ofSize: 14); text.textContainerInset = NSSize(width: 8, height: 8)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true; text.setAccessibilityLabel("Message")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = text; scroll.drawsBackground = false
        root.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: root.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 110)])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(status); status.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        previous.target = self; previous.action = #selector(previousMessage)
        next.target = self; next.action = #selector(nextMessage)
        retry.target = self; retry.action = #selector(retryAttachment); retry.isHidden = true
        let navigation = NSStackView(views: [previous, count, next, retry]); navigation.spacing = 14
        root.addArrangedSubview(navigation)
        updateNavigation()
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
    func setStatus(_ value: String) { status.stringValue = value }
    func setAttachment(_ url: URL, for messageID: String) {
        guard active, selectedMessage?.id == messageID else { return }
        lastMediaError=nil
        selectedAttachmentURL = url; let token = generation
        media.load(url: url, mediaType: selectedMessage?.attachment?.mediaType) { [weak self] error in
            guard let self, self.active, self.generation == token, self.selectedMessage?.id == messageID else { return }
            if let error { self.lastMediaError=error; self.showAttachmentError(error.localizedDescription, for: messageID) }
            else { self.loaded = true; self.status.stringValue = ""; self.retry.isHidden = true; self.notifyPresentedIfReady() }
        }
    }
    func showAttachmentError(_ message: String, for messageID: String) {
        guard active, selectedMessage?.id == messageID else { return }
        loaded = false; selectedAttachmentURL = nil
        media.clear(message: "Attachment unavailable")
        status.stringValue = message; retry.isHidden = false
    }
    func windowWillClose(_ notification: Notification) {
        active = false; generation += 1; loaded = false; media.clear(message: ""); onClose?()
    }
    func windowDidBecomeKey(_ notification: Notification) { notifyPresentedIfReady() }
    private var selectedMessage: ChatMessage? { messages.indices.contains(selection) ? messages[selection] : nil }
    private func updateHeading() {
        guard let message = selectedMessage else { heading.stringValue = "No messages yet"; return }
        let sender = message.senderID == currentDeviceID ? "You" : "Your person"
        let receipt=message.senderID == currentDeviceID ? (message.readAt == nil ? " · Sent" : " · Read") : ""
        heading.stringValue = "\(sender) · \(DateFormatter.localizedString(from: message.createdAt, dateStyle: .medium, timeStyle: .short))\(receipt)"
    }
    private func updateNavigation() {
        previous.isEnabled = selection > 0
        next.isEnabled = selection+1 < messages.count
        let unread = messages.filter { $0.recipientID == currentDeviceID && $0.readAt == nil }.count
        count.stringValue = messages.isEmpty ? "" : "\(selection+1) of \(messages.count) · \(unread) unread"
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
            media.clear(message: ""); loaded = true; notifyPresentedIfReady()
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
    @objc private func retryAttachment() {
        guard let message = selectedMessage, message.attachment != nil else { return }
        retry.isHidden = true; media.clear(message: "Loading attachment…"); onAttachmentNeeded?(message)
    }
}

private func install(_ stack: NSStackView, in view: NSView, inset: CGFloat) {
    stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
                                 stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
                                 stack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset),
                                 stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -inset)])
}

private final class MessageMediaView: NSView {
    var onDrop: ((URL) -> Void)?
    private let image = NSImageView()
    private let video = AVPlayerView()
    private let label = NSTextField(wrappingLabelWithString: "Choose a photo or video, or drop one here.")
    private var observation: NSKeyValueObservation?
    private var generation = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true; layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; layer?.cornerRadius = 8
        image.imageScaling = .scaleProportionallyUpOrDown
        video.controlsStyle = .inline
        label.alignment = .center; label.textColor = .secondaryLabelColor
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
