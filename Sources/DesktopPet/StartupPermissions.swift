import AppKit

/// Each implemented feature supplies its actual authorization check and request.
/// A successful request callback is never treated as proof of authorization.
struct StartupPermission {
    let name: String
    let reason: String
    let isGranted: () -> Bool
    let request: (@escaping () -> Void) -> Void
}

final class StartupPermissions: NSObject {
    /// Real still-photo capture needs Camera access. Mouse-only monitoring,
    /// geometry-only window inventory, app-owned storage, and offline reading
    /// need no further privacy grants. Authorization never starts a camera.
    /// Optional 4b screenshot landing requests Screen Recording separately;
    /// declining it preserves geometry-based entries and never blocks startup.
    /// Video attachments are files; the app never requests microphone access.
    static let required: [StartupPermission] = [CameraService.startupPermission]

    private let requirements: [StartupPermission]
    private let showsWindow: Bool
    private var onReady: (() -> Void)?
    private var timer: Timer?
    private var window: NSWindow?
    private var status: NSTextField?
    private var requesting = false
    private(set) var isFinished = false

    init(requirements: [StartupPermission] = StartupPermissions.required, showsWindow: Bool = true) {
        self.requirements = requirements
        self.showsWindow = showsWindow
    }

    var missing: [StartupPermission] { requirements.filter { !$0.isGranted() } }

    func begin(onReady: @escaping () -> Void) {
        guard self.onReady == nil, !isFinished else { return }
        self.onReady = onReady
        recheck()
        guard !isFinished else { return }
        if showsWindow {
            showWindow()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.recheck() }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
        requestMissing()
    }

    @objc func recheck() {
        guard !isFinished, onReady != nil else { return }
        let pending = missing
        if pending.isEmpty {
            isFinished = true
            timer?.invalidate(); timer = nil
            window?.orderOut(nil)
            let callback = onReady; onReady = nil
            callback?()
        } else {
            status?.stringValue = requirements.map {
                "\($0.isGranted() ? "✓" : "○") \($0.name)\n\($0.reason)"
            }.joined(separator: "\n\n")
        }
    }

    @objc private func requestMissing() {
        guard !requesting, !isFinished else { return }
        requesting = true
        requestNext(ArraySlice(missing))
    }

    private func requestNext(_ remaining: ArraySlice<StartupPermission>) {
        guard !isFinished else { requesting = false; return }
        guard let permission = remaining.first else {
            requesting = false; recheck(); return
        }
        guard !permission.isGranted() else { requestNext(remaining.dropFirst()); return }
        permission.request { [weak self] in
            // Native request callbacks may arrive on a background queue.
            if Thread.isMainThread { self?.requestNext(remaining.dropFirst()) }
            else { DispatchQueue.main.async { self?.requestNext(remaining.dropFirst()) } }
        }
    }

    private func showWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 350),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Set up sombrero"
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let title = NSTextField(labelWithString: "Allow sombrero to start")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.frame = NSRect(x: 24, y: 304, width: 382, height: 26)
        content.addSubview(title)
        let explanation = NSTextField(wrappingLabelWithString:
            "Grant each permission below. Your duck will appear once all are allowed. If access was denied, enable it in System Settings → Privacy & Security.")
        explanation.frame = NSRect(x: 24, y: 238, width: 382, height: 58)
        content.addSubview(explanation)
        let status = NSTextField(wrappingLabelWithString: "")
        status.frame = NSRect(x: 24, y: 100, width: 382, height: 128)
        content.addSubview(status); self.status = status
        let actions: [(String, Selector, CGFloat, CGFloat)] = [
            ("Request Permissions", #selector(requestMissing), 24, 180),
            ("Open System Settings", #selector(openSettings), 214, 192),
            ("Check Again", #selector(recheck), 24, 180),
            ("Quit", #selector(quit), 214, 192)
        ]
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.0, target: self, action: action.1)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: action.2, y: index < 2 ? 58 : 20, width: action.3, height: 30)
            content.addSubview(button)
        }
        self.window = window
        recheck(); window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
                                          configuration: NSWorkspace.OpenConfiguration())
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func cancel() {
        onReady = nil; isFinished = true
        timer?.invalidate(); timer = nil; window?.orderOut(nil)
    }
}
