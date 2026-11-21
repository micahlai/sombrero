import AppKit
import UniformTypeIdentifiers

@MainActor
final class MessageSettingsWindow: NSObject, NSWindowDelegate {
    var onSave: ((String, String) -> Void)?
    var onDisconnect: (() -> Void)?
    let window: NSWindow
    private let address = NSTextField(string: "https://sombrero.micahlai.com")
    private let token = NSSecureTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Connect", target: nil, action: nil)
    private let disconnect = NSButton(title: "Disconnect", target: nil, action: nil)

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 310),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Connect your messages"
        window.isReleasedWhenClosed = false; window.delegate = self
        let root = window.contentView!
        let description = NSTextField(wrappingLabelWithString:
            "Connect both computers to your sombrero server. Each computer has its own device token from the server setup.")
        description.frame = NSRect(x: 24, y: 234, width: 432, height: 52); root.addSubview(description)
        for (title, field, y) in [("Server address", address, 184.0), ("Device token", token, 124.0)] {
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 24, y: y+27, width: 432, height: 18); root.addSubview(label)
            field.frame = NSRect(x: 24, y: y, width: 432, height: 25)
            field.setAccessibilityLabel(title); root.addSubview(field)
        }
        status.frame = NSRect(x: 24, y: 77, width: 432, height: 40); root.addSubview(status)
        let importFile=NSButton(title:"Import Device File…",target:self,action:#selector(importDeviceFile))
        importFile.bezelStyle = .rounded; importFile.frame=NSRect(x:24,y:43,width:180,height:30)
        root.addSubview(importFile)
        save.frame = NSRect(x: 336, y: 10, width: 120, height: 30)
        save.bezelStyle = .rounded; save.target = self; save.action = #selector(connect)
        save.keyEquivalent = "\r"; root.addSubview(save)
        disconnect.frame = NSRect(x: 24, y: 10, width: 120, height: 30)
        disconnect.bezelStyle = .rounded; disconnect.target = self; disconnect.action = #selector(disconnectServer)
        root.addSubview(disconnect)
    }
    func show(serverURL: URL?, connected: Bool) {
        address.stringValue = serverURL?.absoluteString ?? "https://sombrero.micahlai.com"
        token.stringValue = ""; disconnect.isEnabled = connected
        setStatus(connected ? "Connected. Use the control panel to open your messages." : "Enter this computer's device token to connect.", busy: false)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func setStatus(_ text: String, busy: Bool) {
        status.stringValue = text; save.isEnabled = !busy; address.isEnabled = !busy; token.isEnabled = !busy
    }
    func connected() { token.stringValue = ""; window.orderOut(nil) }
    func close() { token.stringValue = ""; window.orderOut(nil) }
    @objc private func connect() {
        guard !token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setStatus("Enter this computer's device token.", busy: false); return
        }
        onSave?(address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    @objc private func disconnectServer() { onDisconnect?() }
    @objc private func importDeviceFile() {
        let picker=NSOpenPanel(); picker.allowedContentTypes=[.json]; picker.allowsMultipleSelection=false
        picker.beginSheetModal(for:window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .OK, let url=picker.url else { return }
                do {
                    let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                    guard size>0, size<=65_536 else { throw MessageServiceError.invalidConfiguration }
                    let data=try Data(contentsOf:url)
                    guard let file=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                          let address=file["baseURL"] as? String, let server=URL(string:address), MessageService.validServerURL(server),
                          let token=file["token"] as? String, !token.isEmpty else { throw MessageServiceError.invalidConfiguration }
                    self.address.stringValue=address; self.token.stringValue=token
                    self.setStatus("Device file loaded. Press Connect to verify the server and save this token in Keychain.",busy:false)
                } catch { self.setStatus("Could not import the device file: \(error.localizedDescription)",busy:false) }
            }
        }
    }
    func windowWillClose(_ notification: Notification) { token.stringValue = "" }
}
