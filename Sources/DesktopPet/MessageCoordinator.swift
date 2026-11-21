import AppKit
import PetCore

/// Native message windows and network sync stay independent of the duck's clock.
@MainActor
final class MessageCoordinator {
    let service: MessageService
    var onRoutineRequested: ((DuckRequest) -> Void)?
    var onRoutineEnded: ((DuckRequest) -> Void)?
    var onCaptureFinished: (() -> Void)?
    var onUnreadChanged: ((Int) -> Void)?
    var onWindowsChanged: (() -> Void)?
    private let composer = MessageComposerWindow()
    private let settings = MessageSettingsWindow()
    private let outbox = MessageOutboxWindow()
    private let camera = CameraService()
    private var drafts: MessageDraftStore?
    private var draftAccount: String?
    private var inbox: MessageInboxWindow?
    private var inboxDeviceID: String?
    private var pendingComposer = false
    private var pendingInbox = false
    private var pendingCamera = false
    private var cameraStarting = false
    private var cameraDeviceID: String?
    private var cameraRequestToken=UUID()
    private var downloads: [String: Task<Void, Never>] = [:]
    private var applyingDraft = false

    var unreadCount: Int { service.unreadIncomingCount }
    var hasMessages: Bool {
        guard let deviceID=service.configuration?.deviceID else { return false }
        return service.messages.contains { $0.recipientID == deviceID }
    }
    var isInteracting: Bool {
        pendingComposer || pendingInbox || composer.window.isVisible || inbox?.window.isVisible == true || settings.window.isVisible || outbox.window.isVisible
    }

    init(service: MessageService? = nil) {
        self.service = service ?? MessageService()
        draftAccount=Self.draftProfile(self.service.configuration)
        drafts=draftAccount.map { MessageDraftStore(profile:$0) }
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
                self.closeWindows(); try self.service.removeConfiguration()
                self.settings.show(serverURL:nil,connected:false)
            } catch { self.settings.setStatus(error.localizedDescription,busy:false) }
        }
        composer.onSend = { [weak self] attributed, attachment in
            guard let self else { return }
            do {
                let body=MessageRichText.body(from:attributed)
                try self.drafts?.save(body:body,attachment:attachment)
                let staged=try self.drafts?.load()?.attachment ?? attachment
                _ = try self.service.enqueue(body:body,attachment:staged)
                self.drafts?.clear(); self.applyingDraft = true
                self.composer.resetAfterSend(); self.applyingDraft = false
                self.camera.stop(); self.onCaptureFinished?()
                self.composer.setStatus("Saved to the outbox. It will send when the server is reachable.",isBusy:false)
            } catch { self.composer.setStatus(error.localizedDescription,isBusy:false) }
        }
        composer.onDraftChanged = { [weak self] attributed, attachment in
            guard let self, !self.applyingDraft else { return }
            do { try self.drafts?.save(body:MessageRichText.body(from:attributed),attachment:attachment) }
            catch { self.composer.setStatus("Could not save the draft: \(error.localizedDescription)",isBusy:false) }
        }
        composer.onClose = { [weak self] in
            guard let self else { return }
            self.pendingComposer=false; self.stopCamera()
            self.onRoutineEnded?(.photoTake); self.onWindowsChanged?()
        }
        composer.onCamera = { [weak self] in self?.startCamera() }
        composer.onCapture = { [weak self] in self?.camera.capture() }
        composer.onCameraDeviceSelected = { [weak self] id in self?.startCamera(deviceID:id) }
        composer.onStopCamera = { [weak self] in self?.stopCamera() }
        camera.onPhoto = { [weak self] url in
            guard let self else { return }
            self.composer.setAttachment(url); self.onCaptureFinished?()
        }
        camera.onError = { [weak self] message in self?.composer.setStatus(message,isBusy:false) }
        camera.onStateChanged = { [weak self] in
            guard let self else { return }
            self.composer.setCameraPreviewActive(self.cameraStarting || self.pendingCamera || self.camera.isRunning,ready:self.camera.isRunning && !self.camera.isCapturing)
        }
    }

    func start() { service.start(); update() }
    func stop() {
        closeWindows(); settings.window.orderOut(nil); outbox.window.orderOut(nil); service.stop()
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
        pendingComposer=true; onRoutineRequested?(.photoTake); onWindowsChanged?()
    }
    func showInbox() {
        guard service.configuration != nil else { showSettings(); return }
        if inbox?.window.isVisible == true { inbox?.show(messages:service.messages,selectedID:nil); return }
        if pendingComposer || composer.window.isVisible { closeWindows() }
        pendingInbox=true; onRoutineRequested?(.photoShow); onWindowsChanged?()
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
        if pendingInbox, [.showPhoto,.showingPhoto].contains(state), let identity=service.configuration?.identity {
            pendingInbox=false
            if inbox == nil || inboxDeviceID != identity.deviceID {
                inbox?.window.orderOut(nil)
                let viewer=MessageInboxWindow(currentDeviceID:identity.deviceID)
                viewer.onAttachmentNeeded = { [weak self] message in self?.loadAttachment(message) }
                viewer.onPresented = { [weak self] message in
                    guard let self else { return }
                    do { try self.service.markRead(message) }
                    catch { self.inbox?.setStatus("Could not save the read receipt. Reopen this message to retry.") }
                }
                viewer.onClose = { [weak self] in
                    self?.onRoutineEnded?(.photoShow); self?.onWindowsChanged?()
                }
                inbox=viewer; inboxDeviceID=identity.deviceID
            }
            inbox?.show(messages:service.messages,selectedID:service.messages.first { $0.recipientID == identity.deviceID && $0.readAt == nil }?.id)
            onWindowsChanged?()
        }
    }
    func closeWindows() {
        let composing=pendingComposer || composer.window.isVisible
        let viewing=pendingInbox || inbox?.window.isVisible == true
        pendingComposer=false; pendingInbox=false; stopCamera()
        composer.window.close(); inbox?.window.close()
        if composing { onRoutineEnded?(.photoTake) }
        if viewing { onRoutineEnded?(.photoShow) }
        onWindowsChanged?()
    }
    func suspend() { closeWindows() }
    func resume() { Task { [weak self] in await self?.service.refresh() } }
    private func update() {
        let account=Self.draftProfile(service.configuration)
        if account != draftAccount {
            closeWindows()
            downloads.values.forEach { $0.cancel() }; downloads.removeAll()
            inbox=nil; inboxDeviceID=nil
            draftAccount=account; drafts=account.map { MessageDraftStore(profile:$0) }
            applyingDraft=true; composer.resetAfterSend(); applyingDraft=false
        }
        onUnreadChanged?(unreadCount)
        outbox.update(entries:service.outbox,status:service.lastError ?? service.connectionStatus)
        if inbox?.window.isVisible == true { inbox?.setMessages(service.messages,selectedID:nil) }
        if composer.window.isVisible { composer.setStatus(service.connectionStatus,isBusy:false) }
    }
    private func startCamera(deviceID: String? = nil) {
        pendingCamera=true; cameraStarting=true; cameraDeviceID=deviceID; cameraRequestToken=UUID()
        composer.setCameraPreviewActive(true,ready:false)
        composer.setCameraDevices(camera.availableDevices.map { ($0.id,$0.name) },selectedID:deviceID ?? camera.selectedDeviceID)
        onRoutineRequested?(.photoTake)
    }
    private func stopCamera() {
        pendingCamera=false; cameraStarting=false; cameraRequestToken=UUID(); camera.stop()
    }
    private func loadAttachment(_ message: ChatMessage) {
        guard downloads[message.id] == nil else { return }
        downloads[message.id]=Task { [weak self] in
            guard let self else { return }
            defer { self.downloads.removeValue(forKey:message.id) }
            do {
                if let url=try await self.service.attachmentURL(for:message), !Task.isCancelled {
                    self.inbox?.setAttachment(url,for:message.id)
                }
            } catch {
                if !Task.isCancelled { self.inbox?.showAttachmentError(error.localizedDescription,for:message.id) }
            }
        }
    }
    private static func draftProfile(_ configuration: MessageConfiguration?) -> String? {
        guard let configuration else { return nil }
        let parts=[configuration.serverURL.absoluteString,configuration.pairID,configuration.deviceID]
        return String(data:try! JSONEncoder().encode(parts),encoding:.utf8)
    }
}
