import AppKit
import PetAssets

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: PetCoordinator?
    private let startupPermissions = StartupPermissions()
    private var hasLaunched = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        startupPermissions.begin { [weak self] in
            guard let self else { return }
            let controller = PetCoordinator(); self.coordinator = controller
            controller.start(); self.hasLaunched = true
            if ProcessInfo.processInfo.arguments.contains("--setup") { controller.showMessageSetup() }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { startupPermissions.cancel(); coordinator?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if hasLaunched { coordinator?.recoverCompanion() }
        else { startupPermissions.recheck() }
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
