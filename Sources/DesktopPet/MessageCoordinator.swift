import AppKit
import PetCore
import PetAssets

/// Native message windows and network sync stay independent of the duck's clock.
@MainActor
final class MessageCoordinator {
    let service: MessageService
    var onRoutineRequested: ((DuckRequest) -> Void)?
    var onRoutineEnded: ((DuckRequest) -> Void)?
    var onMessageSent: (() -> Void)?
    var onUnreadChanged: ((Int) -> Void)?
    var onWindowsChanged: (() -> Void)?
    private let composer: MessageComposerWindow
    private let settings = MessageSettingsWindow()
    private let outbox = MessageOutboxWindow()
    private let camera = CameraService()
    private var drafts: MessageDraftStore?
    private var draftAccount: String?
    private var inbox: MessageInboxWindow?
    private var keptInboxes: [MessageInboxWindow] = []
    private var inboxDeviceID: String?
    private var pendingComposer = false
    private var pendingInbox = false
    private var pendingCamera = false
    private var cameraStarting = false
    private var cameraDeviceID: String?
    private var cameraRequestToken=UUID()
    private var downloads: [String: Task<Void, Never>] = [:]
    private var applyingDraft = false
    private var composerSendID: String?
    private var closingSentComposer = false
    private var testPhoto: ChatMessage?
    private var testPhotoUnread = false
    private let testPairID = UUID().uuidString
    private let draftDirectory: URL?

    var unreadCount: Int { service.unreadIncomingCount + (testPhotoUnread ? 1 : 0) }
    var hasMessages: Bool {
        if testPhoto != nil { return true }
        guard let deviceID=service.configuration?.deviceID else { return false }
        return service.messages.contains { $0.recipientID == deviceID }
    }
    var isInteracting: Bool {
        pendingComposer || pendingInbox || composer.window.isVisible || inbox?.window.isVisible == true || settings.window.isVisible || outbox.window.isVisible
    }

    init(service: MessageService? = nil, composer: MessageComposerWindow? = nil, draftDirectory: URL? = nil) {
        self.service = service ?? MessageService()
        self.composer = composer ?? MessageComposerWindow()
        self.draftDirectory = draftDirectory
        let composer = self.composer
        draftAccount=Self.draftProfile(self.service.configuration)
        drafts=draftAccount.map { MessageDraftStore(profile:$0,directory:draftDirectory) }
        self.service.onChange = { [weak self] in self?.update() }
        outbox.onRetry = { [weak self] in Task { await self?.service.refresh() } }
        outbox.onConnection = { [weak self] in self?.showSettings() }
        outbox.onRemove = { [weak self] id in
            guard let self else { return }
            do { try self.service.discardOutgoing(id:id) }
            catch { self.outbox.update(entries:self.service.outbox,status:error.localizedDescription) }
        }
        settings.onSave = { [weak self] address, token in
            guard let self else { return }
            guard let url = URL(string: address) else { self.settings.setStatus("Enter a valid server address.", busy:false); return }
            self.settings.setStatus("Connecting…", busy:true)
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.service.configure(serverURL:url,token:token)
                    self.service.start(); self.settings.connected()
                    self.onWindowsChanged?()
                } catch { self.settings.setStatus(error.localizedDescription, busy:false) }
            }
        }
        settings.onDisconnect = { [weak self] in
            guard let self else { return }
            do {
                self.closeWindows(includeKept:true); try self.service.removeConfiguration()
                self.settings.show(serverURL:nil,connected:false)
            } catch { self.settings.setStatus(error.localizedDescription,busy:false) }
        }
        composer.onSend = { [weak self] attributed, attachment in
            guard let self else { return }
            do {
                let body=MessageRichText.body(from:attributed)
                try self.drafts?.save(body:body,attachment:attachment)
                let staged=try self.drafts?.load()?.attachment ?? attachment
                self.composerSendID = try self.service.enqueue(body:body,attachment:staged)
                self.drafts?.clear(); self.applyingDraft = true
                self.composer.resetAfterSend(); self.applyingDraft = false
                self.stopCamera()
                self.composer.setStatus("Sending…",isBusy:true)
            } catch { self.composer.setStatus(error.localizedDescription,isBusy:false) }
        }
        composer.onDraftChanged = { [weak self] attributed, attachment in
            guard let self, !self.applyingDraft else { return }
            do { try self.drafts?.save(body:MessageRichText.body(from:attributed),attachment:attachment) }
            catch { self.composer.setStatus("Could not save the draft: \(error.localizedDescription)",isBusy:false) }
        }
        composer.onClose = { [weak self] in
            guard let self else { return }
            self.composerSendID=nil
            self.pendingComposer=false; self.stopCamera()
            if !self.closingSentComposer { self.onRoutineEnded?(.photoTake) }
            self.onWindowsChanged?()
        }
        composer.onCamera = { [weak self] in self?.startCamera() }
        composer.onCapture = { [weak self] in self?.camera.capture() }
        composer.onCameraDeviceSelected = { [weak self] id in self?.startCamera(deviceID:id) }
        composer.onStopCamera = { [weak self] in self?.stopCamera() }
        camera.onPhoto = { [weak self] url in
            guard let self else { return }
            self.composer.setAttachment(url)
        }
        camera.onError = { [weak self] message in self?.composer.setStatus(message,isBusy:false) }
        camera.onStateChanged = { [weak self] in
            guard let self else { return }
            self.composer.setCameraPreviewActive(self.cameraStarting || self.pendingCamera || self.camera.isRunning,ready:self.camera.isRunning && !self.camera.isCapturing)
        }
    }

    func start() { service.start(); update() }
    func stop() {
        closeWindows(includeKept:true); settings.window.orderOut(nil); outbox.window.orderOut(nil); service.stop()
        downloads.values.forEach { $0.cancel() }; downloads.removeAll()
    }
    func showSettings() {
        settings.show(serverURL:service.configuration?.serverURL,connected:service.configuration != nil)
        onWindowsChanged?()
    }
    func showComposer() {
        guard service.configuration != nil else { showSettings(); return }
        if composer.window.isVisible { composer.show(); return }
        if pendingInbox || inbox?.window.isVisible == true { closeWindows() }
        do {
            if let draft=try drafts?.load() {
                applyingDraft=true
                composer.setDraft(text:MessageRichText.attributed(from:draft.body),attachmentURL:draft.attachment)
                applyingDraft=false
            }
        } catch { composer.setStatus("Could not restore the saved draft: \(error.localizedDescription)",isBusy:false) }
        // Resume an unsent photo for review. A new/text-only draft starts with
        // live preview, after 6a reaches its camera-holding pose in didEnter.
        if composer.draftAttachmentURL == nil {
            pendingCamera=true; cameraStarting=true; cameraDeviceID=nil; cameraRequestToken=UUID()
            composer.setCameraPreviewActive(true,ready:false)
        }
        pendingComposer=true; onRoutineRequested?(.photoTake); onWindowsChanged?()
    }
    func showInbox() {
        guard service.configuration != nil || testPhoto != nil else { showSettings(); return }
        if inbox?.window.isVisible == true { inbox?.show(messages:service.messages,selectedID:nil); return }
        if pendingComposer || composer.window.isVisible { closeWindows() }
        pendingInbox=true; onRoutineRequested?(.photoShow); onWindowsChanged?()
    }
    /// A local receive fixture, never uploaded or mixed into the server replica.
    func receiveTestPhoto() {
        guard let url=MessageArtwork.testPhotoURL, let data=try? Data(contentsOf:url) else { return }
        let receiver=service.configuration?.deviceID ?? UUID().uuidString
        let attachment=ChatAttachment(id:UUID().uuidString,mediaType:"image/png",byteCount:data.count,
            sha256:MessageStore.digest(data),createdAt:Date())
        testPhoto=ChatMessage(id:UUID().uuidString,pairID:testPairID,senderID:UUID().uuidString,recipientID:receiver,
            clientRequestID:UUID().uuidString,body:RichMessageBody(runs:[
                RichTextRun(text:"A little hello from your person!\n",bold:true),
                RichTextRun(text:"Your test photo arrived. Keep me on your screen 💛")]),attachment:attachment,createdAt:Date(),senderName:"Your person")
        testPhotoUnread=true; update()
    }
    func showOutbox() { update(); outbox.show(); onWindowsChanged?() }
    func didEnter(_ state: DuckState) {
        if pendingComposer, state == .cameraIdle {
            pendingComposer=false; composer.show()
            composer.setStatus(service.connectionStatus,isBusy:false); onWindowsChanged?()
        }
        if pendingCamera, state == .cameraIdle {
            pendingCamera=false
            let deviceID=cameraDeviceID
            let token=cameraRequestToken
            Task { [weak self] in
                guard let self, self.cameraRequestToken == token, self.composer.window.isVisible else { return }
                await self.camera.startPreview(in:self.composer.cameraPreviewHost,deviceID:deviceID)
                guard self.cameraRequestToken == token, self.composer.window.isVisible else { return }
                self.cameraStarting=false
                self.composer.setCameraPreviewActive(self.camera.isRunning,ready:self.camera.isRunning && !self.camera.isCapturing)
                self.composer.setCameraDevices(self.camera.availableDevices.map { ($0.id,$0.name) },selectedID:self.camera.selectedDeviceID)
            }
        }
        if pendingInbox, state == .showingPhoto, let deviceID=service.configuration?.deviceID ?? testPhoto?.recipientID {
            pendingInbox=false
            if inbox == nil || inboxDeviceID != deviceID {
                inbox?.window.orderOut(nil)
                let viewer=MessageInboxWindow(currentDeviceID:deviceID)
                viewer.onAttachmentNeeded = { [weak self, weak viewer] message in
                    guard let viewer else { return }; self?.loadAttachment(message,in:viewer)
                }
                viewer.onPresented = { [weak self, weak viewer] message in
                    guard let self else { return }
                    if message.pairID == self.testPairID {
                        if message.id == self.testPhoto?.id {
                            self.testPhotoUnread=false; self.testPhoto?.readAt=Date(); self.update()
                        }
                        return
                    }
                    do { try self.service.markRead(message) }
                    catch { viewer?.setStatus("Could not save the read receipt. Reopen this message to retry.") }
                }
                viewer.onKeep = { [weak self, weak viewer] in
                    guard let self, let viewer else { return }
                    self.keptInboxes.append(viewer)
                    if self.inbox === viewer { self.inbox=nil; self.inboxDeviceID=nil }
                    self.onRoutineEnded?(.photoShow); self.onWindowsChanged?()
                }
                viewer.onClose = { [weak self, weak viewer] in
                    guard let self, let viewer else { return }
                    self.keptInboxes.removeAll { $0 === viewer }
                    if !viewer.isKept { self.onRoutineEnded?(.photoShow) }
                    self.onWindowsChanged?()
                }
                inbox=viewer; inboxDeviceID=deviceID
            }
            let messages=inboxMessages
            inbox?.show(messages:messages,selectedID:testPhotoUnread ? testPhoto?.id : messages.first { $0.recipientID == deviceID && $0.readAt == nil }?.id)
            onWindowsChanged?()
        }
    }
    func closeWindows(includeKept: Bool = false) {
        let composing=pendingComposer || composer.window.isVisible
        let viewing=pendingInbox || inbox?.window.isVisible == true
        pendingComposer=false; pendingInbox=false; stopCamera()
        if composer.window.isVisible { composer.window.close() }
        else if composing { onRoutineEnded?(.photoTake) }
        if inbox?.window.isVisible == true { inbox?.window.close() }
        else if viewing { onRoutineEnded?(.photoShow) }
        if includeKept {
            let kept=keptInboxes; keptInboxes.removeAll()
            kept.forEach { $0.window.close() }
        }
        onWindowsChanged?()
    }
    func suspend() { closeWindows() }
    func resume() { Task { [weak self] in await self?.service.refresh() } }
    private func update() {
        let account=Self.draftProfile(service.configuration)
        if account != draftAccount {
            closeWindows(includeKept:true)
            testPhoto=nil; testPhotoUnread=false
            downloads.values.forEach { $0.cancel() }; downloads.removeAll()
            inbox=nil; inboxDeviceID=nil
            draftAccount=account; drafts=account.map { MessageDraftStore(profile:$0,directory:draftDirectory) }
            applyingDraft=true; composer.resetAfterSend(); applyingDraft=false
        }
        onUnreadChanged?(unreadCount)
        outbox.update(entries:service.outbox,status:service.lastError ?? service.connectionStatus)
        if inbox?.window.isVisible == true { inbox?.setMessages(inboxMessages,selectedID:nil) }
        if composer.window.isVisible {
            if let requestID=composerSendID {
                if service.messages.contains(where:{ $0.clientRequestID == requestID && $0.senderID == service.configuration?.deviceID }) {
                    // Only this open send owns the close. An acknowledgement for
                    // a manually closed composer cannot dismiss a later draft.
                    closingSentComposer=true; composerSendID=nil
                    onMessageSent?()
                    composer.window.close(); closingSentComposer=false
                } else {
                    composer.setStatus(service.lastError ?? "Sending…",isBusy:true)
                }
            } else { composer.setStatus(service.connectionStatus,isBusy:false) }
        }
    }
    private var inboxMessages: [ChatMessage] { service.messages + (testPhoto.map { [$0] } ?? []) }
    private func startCamera(deviceID: String? = nil) {
        pendingCamera=true; cameraStarting=true; cameraDeviceID=deviceID; cameraRequestToken=UUID()
        composer.setCameraPreviewActive(true,ready:false)
        composer.setCameraDevices(camera.availableDevices.map { ($0.id,$0.name) },selectedID:deviceID ?? camera.selectedDeviceID)
        onRoutineRequested?(.photoTake)
    }
    private func stopCamera() {
        pendingCamera=false; cameraStarting=false; cameraRequestToken=UUID(); camera.stop()
    }
    private func loadAttachment(_ message: ChatMessage, in viewer: MessageInboxWindow) {
        if message.id == testPhoto?.id, let url=MessageArtwork.testPhotoURL {
            viewer.setAttachment(url,for:message.id); return
        }
        let key=viewer.identifier+":"+message.id
        guard downloads[key] == nil else { return }
        downloads[key]=Task { [weak self, weak viewer] in
            guard let self else { return }
            defer { self.downloads.removeValue(forKey:key) }
            do {
                if let url=try await self.service.attachmentURL(for:message), !Task.isCancelled {
                    viewer?.setAttachment(url,for:message.id)
                }
            } catch {
                if !Task.isCancelled { viewer?.showAttachmentError(error.localizedDescription,for:message.id) }
            }
        }
    }
    private static func draftProfile(_ configuration: MessageConfiguration?) -> String? {
        guard let configuration else { return nil }
        let parts=[configuration.serverURL.absoluteString,configuration.pairID,configuration.deviceID]
        return String(data:try! JSONEncoder().encode(parts),encoding:.utf8)
    }
}
