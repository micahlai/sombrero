import AppKit
import PetCore
import PetAssets

final class PetCoordinator: NSObject, NSMenuDelegate {
    private let store = PreferenceStore()
    private var preferences: PetPreferences
    private var behavior = PetBehavior()
    private let panel: PetPanel
    private let petView: SpriteView
    private let sprites: SpriteLibrary
    private var controller = DuckController()
    private var playback: SpritePlayback
    private var clock = DrawingClock()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var pointerCaptured = false
    private var menuTracking = false
    private var suspended = false
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        let loaded = store.load()
        preferences = loaded
        panel = PetPanel(size: CGFloat(loaded.size))
        let library = SpriteLibrary()
        sprites = library
        playback = SpritePlayback(frameCounts: library.frameCounts)
        petView = SpriteView(frame: NSRect(x: 0, y: 0, width: loaded.size, height: loaded.size))
        super.init()
        petView.coordinator = self; panel.contentView = petView
        petView.autoresizingMask = [.width, .height]
        behavior.isPaused = loaded.isPaused
        if !loaded.isVisible { behavior.hide() }
        renderFrame()
    }

    func start() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.fill", accessibilityDescription: "Duck controls")
            button.image?.isTemplate = true
            button.toolTip = "Watercolor Duck — show, hide, or recover your companion"
        }
        statusItem.menu = makeMenu()
        applyWindowPolicy()
        restorePlacement()
        if behavior.isVisible { panel.orderFrontRegardless() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.recoverAfterDisplayChange() })
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.resume() })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.resume() })
        startTimerIfNeeded()
    }

    func stop() {
        savePlacement(); persist(); timer?.invalidate(); timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func applyWindowPolicy() {
        // Above ordinary applications; never attempt to cover protected system UI.
        panel.level = preferences.alwaysOnTop ? .statusBar : .normal
        var collection: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .stationary]
        if preferences.allSpaces { collection.insert(.canJoinAllSpaces) }
        panel.collectionBehavior = collection
    }

    private func startTimerIfNeeded() {
        guard behavior.isVisible, !suspended, timer == nil else { return }
        rebaseClock()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    private func tick() {
        let delta = clock.sample(at: ProcessInfo.processInfo.systemUptime,
                                 running: behavior.isVisible && !behavior.isPaused && !suspended)
        let oldState = playback.state, oldFrame = playback.frameIndex
        playback.advance(by: delta) { self.controller.complete { Int.random(in: 0..<100) } }
        if oldState != playback.state || oldFrame != playback.frameIndex { renderFrame() }
        updateMouseRouting()
    }

    private func rebaseClock() {
        _ = clock.sample(at: ProcessInfo.processInfo.systemUptime, running: behavior.isVisible && !behavior.isPaused && !suspended)
    }

    private func renderFrame() {
        petView.sprite = sprites.frame(state: playback.state, index: playback.frameIndex)
        petView.needsDisplay = true
    }

    private func updateMouseRouting() {
        if pointerCaptured || menuTracking { panel.ignoresMouseEvents = false; return }
        let screenPoint = NSEvent.mouseLocation
        let local = NSPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
        let desired = preferences.clickThrough || !petView.containsInteractivePoint(local)
        if panel.ignoresMouseEvents != desired { panel.ignoresMouseEvents = desired }
    }

    func beginPointerGesture() { pointerCaptured = true; panel.ignoresMouseEvents = false }
    func endPointerGesture() { pointerCaptured = false; savePlacement(); persist(); updateMouseRouting() }
    func drag(to origin: NSPoint) {
        panel.setFrameOrigin(origin)
        // Allow crossing displays during drag; recover/clamp on release.
    }

    func showContextMenu(event: NSEvent, view: NSView) { NSMenu.popUpContextMenu(makeMenu(), with: event, for: view) }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        let heading = NSMenuItem(title: "Watercolor Duck", action: nil, keyEquivalent: ""); heading.isEnabled = false
        menu.addItem(heading); menu.addItem(.separator())
        menu.addItem(item(behavior.isVisible ? "Hide Pet" : "Show Pet", #selector(toggleVisibility)))
        menu.addItem(item("Bring Back to This Screen", #selector(bringBack)))
        menu.addItem(.separator())
        menu.addItem(item("Always on Top", #selector(toggleOnTop), checked: preferences.alwaysOnTop))
        menu.addItem(item("Show on All Desktops", #selector(toggleSpaces), checked: preferences.allSpaces))
        menu.addItem(item("Click Through Pet", #selector(toggleClickThrough), checked: preferences.clickThrough))
        menu.addItem(item("Pause Motion", #selector(togglePause), checked: behavior.isPaused))
        let sizes = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (title, size) in [("Small", 88), ("Medium", 112), ("Large", 152)] {
            let option = item(title, #selector(changeSize(_:)), checked: preferences.size == Double(size))
            option.tag = size; submenu.addItem(option)
        }
        sizes.submenu = submenu; menu.addItem(sizes)
        menu.addItem(.separator())
        menu.addItem(item("Quit Watercolor Duck", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.state = checked ? .on : .off; return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuTracking = true; panel.ignoresMouseEvents = false
        // Rebuild the status menu before display so labels/checkmarks reflect pet actions.
        let fresh = makeMenu()
        menu.removeAllItems()
        for item in fresh.items { fresh.removeItem(item); menu.addItem(item) }
    }

    func menuDidClose(_ menu: NSMenu) { menuTracking = false; updateMouseRouting() }

    func recoverCompanion() { bringBack() }

    @objc private func toggleVisibility() {
        if behavior.isVisible {
            behavior.hide(); panel.orderOut(nil); timer?.invalidate(); timer = nil
        } else {
            behavior.show(); restorePlacement(); panel.orderFrontRegardless(); startTimerIfNeeded()
        }
        rebaseClock(); renderFrame(); updateMouseRouting()
        pointerCaptured = false; persist()
    }
    @objc private func bringBack() {
        guard let screen = screenAtPointer() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        behavior.show(); preferences.clickThrough = false
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        panel.ignoresMouseEvents = false; panel.orderFrontRegardless()
        startTimerIfNeeded(); savePlacement(); persist()
    }
    @objc private func toggleOnTop() { preferences.alwaysOnTop.toggle(); applyWindowPolicy(); persist() }
    @objc private func toggleSpaces() { preferences.allSpaces.toggle(); applyWindowPolicy(); persist() }
    @objc private func toggleClickThrough() { preferences.clickThrough.toggle(); updateMouseRouting(); persist() }
    @objc private func togglePause() {
        tick()
        behavior.isPaused.toggle(); preferences.isPaused = behavior.isPaused
        rebaseClock(); persist()
    }
    @objc private func changeSize(_ sender: NSMenuItem) {
        savePlacement(); preferences.size = Double(sender.tag)
        panel.setContentSize(NSSize(width: sender.tag, height: sender.tag))
        restorePlacement(); savePlacement(); persist()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private var displays: [PetDisplay] { NSScreen.screens.map { screen in
        let area = screen.visibleFrame
        return PetDisplay(id: screenID(screen), workArea: PetRect(x: area.minX, y: area.minY, width: area.width, height: area.height))
    } }
    private func screenID(_ screen: NSScreen) -> String { String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown") }
    private func screenAtPointer() -> NSScreen? { NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } }
    private func restorePlacement() {
        guard let point = Placement.restore(preferences.placement, size: preferences.size, displays: displays,
            fallbackID: (screenAtPointer() ?? NSScreen.main).map(screenID)) else { return }
        panel.setFrameOrigin(NSPoint(x: point.x, y: point.y))
    }
    private func savePlacement() {
        guard let screen = panel.screen ?? screenAtPointer() ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let display = PetDisplay(id: screenID(screen), workArea: PetRect(x: area.minX, y: area.minY, width: area.width, height: area.height))
        let point = Placement.clamp(PetPoint(x: panel.frame.minX, y: panel.frame.minY), size: preferences.size, to: display.workArea)
        panel.setFrameOrigin(NSPoint(x: point.x, y: point.y))
        preferences.placement = Placement.save(origin: point, size: preferences.size, display: display)
    }
    private func persist() { preferences.isVisible = behavior.isVisible; preferences.isPaused = behavior.isPaused; store.save(preferences) }
    private func recoverAfterDisplayChange() { pointerCaptured = false; restorePlacement(); savePlacement(); persist() }
    private func suspend() { suspended = true; rebaseClock(); pointerCaptured = false; timer?.invalidate(); timer = nil; panel.orderOut(nil) }
    private func resume() {
        suspended = false; rebaseClock(); restorePlacement()
        if behavior.isVisible { panel.orderFrontRegardless() }; startTimerIfNeeded()
    }
}
