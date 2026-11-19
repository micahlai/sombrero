import AppKit
import PetAssets

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: PetCoordinator?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppTypography.installDefaults()
        NSApp.setActivationPolicy(.accessory)
        let controller = PetCoordinator(); coordinator = controller; controller.start()
    }
    func applicationWillTerminate(_ notification: Notification) { coordinator?.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.recoverCompanion(); return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
