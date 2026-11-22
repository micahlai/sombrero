import AppKit
#if SOMBRERO_SPARKLE
import Sparkle
#endif

/// Release builds embed Sparkle. Offline developer builds keep their existing
/// dependency-free path and never attempt an unconfigured update check.
@MainActor
final class UpdateController: NSObject {
#if SOMBRERO_SPARKLE
    private var controller: SPUStandardUpdaterController?
#endif
    func start() {
#if SOMBRERO_SPARKLE
        guard controller == nil,
              Bundle.main.bundleURL.pathExtension == "app",
              let feed=Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String,
              URL(string:feed)?.scheme == "https",
              let key=Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") as? String,
              Data(base64Encoded:key)?.count == 32 else { return }
        controller=SPUStandardUpdaterController(startingUpdater:true,updaterDelegate:nil,userDriverDelegate:nil)
#endif
    }
    func addMenuItems(to menu: NSMenu) {
#if SOMBRERO_SPARKLE
        guard let controller else { return }
        let check=NSMenuItem(title:"Check for Updates…",action:#selector(checkForUpdates),keyEquivalent:"")
        check.target=self; check.isEnabled=controller.updater.canCheckForUpdates; menu.addItem(check)
        let automatic=NSMenuItem(title:"Automatically Check for Updates",action:#selector(toggleChecks),keyEquivalent:"")
        automatic.target=self; automatic.state=controller.updater.automaticallyChecksForUpdates ? .on : .off
        menu.addItem(automatic)
        let install=NSMenuItem(title:"Automatically Install Updates",action:#selector(toggleInstallation),keyEquivalent:"")
        install.target=self; install.state=controller.updater.automaticallyDownloadsUpdates ? .on : .off
        menu.addItem(install); menu.addItem(.separator())
#endif
    }
#if SOMBRERO_SPARKLE
    @objc private func checkForUpdates() { controller?.checkForUpdates(nil) }
    @objc private func toggleChecks() {
        guard let updater=controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
    }
    @objc private func toggleInstallation() {
        guard let updater=controller?.updater else { return }
        updater.automaticallyDownloadsUpdates.toggle()
    }
#endif
}
