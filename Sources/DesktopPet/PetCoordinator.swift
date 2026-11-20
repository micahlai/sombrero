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
    private let bubble: SpeechBubble
    private let focusedWindow = FocusedWindowTracker()
    private var windowAnchored = false
    private var uiClock = DrawingClock()
    private var outsideMonitor: Any?
    private var awayMinutes: Int?
    private var returnDeadline: Date?
    private var controller = DuckController()
    private var playback: SpritePlayback
    private var clock = DrawingClock()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var recallTimer: Timer?
    private var pointerCaptured = false
    private var menuTracking = false
    private var suspended = false
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        let loaded = store.load()
        preferences = loaded
        panel = PetPanel(size: CGFloat(loaded.size * SpriteLibrary.viewportScale))
        let library = SpriteLibrary()
        sprites = library
        bubble = SpeechBubble(images: library.speechFrames)
        playback = SpritePlayback(frameCounts: library.frameCounts)
        petView = SpriteView(frame: NSRect(x: 0, y: 0, width: loaded.size * SpriteLibrary.viewportScale, height: loaded.size * SpriteLibrary.viewportScale))
        super.init()
        petView.coordinator = self; panel.contentView = petView
        petView.autoresizingMask = [.width, .height]
        bubble.onAction = { [weak self] action in self?.handleBubble(action) }
        behavior.isPaused = loaded.isPaused
        if !loaded.isVisible { behavior.hide(); controller.reset(to: .timeout) }
        returnDeadline = UserDefaults.standard.object(forKey: "sombrero.returnDeadline") as? Date
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
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.bubble.isVisible else { return }
            if !self.bubble.containsPointer && !self.panel.frame.contains(NSEvent.mouseLocation) { self.closeBubble() }
        }
        startTimerIfNeeded()
    }

    func stop() {
        savePlacement(); persist(); timer?.invalidate(); timer = nil; recallTimer?.invalidate()
        bubble.close(immediately: true)
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private func applyWindowPolicy() {
        // Above ordinary applications; never attempt to cover protected system UI.
        panel.level = preferences.alwaysOnTop ? .statusBar : .normal
        var collection: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .stationary]
        if preferences.allSpaces { collection.insert(.canJoinAllSpaces) }
        panel.collectionBehavior = collection
        bubble.panel.level = panel.level
        bubble.panel.collectionBehavior = collection
    }

    private func startTimerIfNeeded() {
        guard behavior.isVisible, !suspended, timer == nil else { scheduleRecall(); return }
        rebaseClock()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    private func tick() {
        if let deadline = returnDeadline, Date() >= deadline, controller.state == .timeout { recallPet() }
        let now = ProcessInfo.processInfo.systemUptime
        let uiDelta = uiClock.sample(at: now, running: !suspended)
        let delta = clock.sample(at: now, running: behavior.isVisible && !behavior.isPaused && !suspended)
        let oldState = playback.state, oldFrame = playback.frameIndex, oldGeneration = controller.generation
        if behavior.isVisible && !pointerCaptured && !menuTracking {
            let point = NSEvent.mouseLocation
            let local = NSPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
            if !bubble.isVisible {
                controller.setPet(!preferences.clickThrough && petView.containsInteractivePoint(local))
            }
        }
        playback.advance(by: delta, controller: &controller) { Double.random(in: 0..<1) }
        bubble.advance(by: uiDelta)
        if oldState != playback.state || oldFrame != playback.frameIndex || oldGeneration != controller.generation { renderFrame() }
        if controller.state == .timeout && behavior.isVisible {
            behavior.hide(); panel.orderOut(nil); bubble.close(immediately: true)
            if let minutes = awayMinutes { returnDeadline = Date().addingTimeInterval(Double(minutes) * 60) }
            awayMinutes = nil; persist()
            timer?.invalidate(); timer = nil; scheduleRecall()
        }
        updateBubblePlacement(); updateMouseRouting()
    }

    private func rebaseClock() {
        _ = clock.sample(at: ProcessInfo.processInfo.systemUptime, running: behavior.isVisible && !behavior.isPaused && !suspended)
    }

    private func renderFrame() {
        playback.synchronize(with: controller)
        petView.state = playback.state
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
        windowAnchored = false
        panel.setFrameOrigin(origin)
        updateBubblePlacement()
        // Allow crossing displays during drag; recover/clamp on release.
    }

    func toggleBubble() {
        if bubble.wantsOpen { closeBubble() }
        else { bubble.show(); updateBubblePlacement() }
    }

    private func closeBubble() {
        bubble.close(); controller.finishRoutine(); controller.setPet(false)
    }

    private func updateBubblePlacement() {
        guard bubble.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = sprites.occupiedBounds(state: controller.state)
        let local = bounds.map { NSRect(x: $0.minX * panel.frame.width, y: $0.minY * panel.frame.height,
            width: $0.width * panel.frame.width, height: $0.height * panel.frame.height) } ?? petView.interactiveRect
        let occupied = local.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        bubble.anchor(to: occupied, workArea: screen.visibleFrame)
    }

    private func handleBubble(_ action: SpeechBubble.Action) {
        switch action {
        case .close, .done: closeBubble()
        case .goAway: bubble.setMode(.away)
        case .back: bubble.setMode(.menu)
        case .away(let minutes):
            awayMinutes = minutes; returnDeadline = nil
            bubble.close(); controller.dismiss(); renderFrame(); persist()
        case .seePhoto:
            controller.request(.photoShow); bubble.setMode(.photo); renderFrame()
        case .sendPhoto:
            controller.request(.photoTake); bubble.setMode(.camera); renderFrame()
        case .readBible:
            controller.request(.bibleRead); bubble.setMode(.bible); renderFrame()
        case .capture:
            controller.takingPhoto = false; bubble.close(); renderFrame()
        }
    }

    private func recallPet() {
        recallTimer?.invalidate(); recallTimer = nil
        bubble.close(immediately: true)
        returnDeadline = nil; awayMinutes = nil
        if controller.state == .timeout {
            let origin = focusedWindow.peekOrigin(viewportSize: panel.frame.width)
            controller.recall(windowAvailable: origin != nil)
            windowAnchored = controller.state == .windowPeek
            if windowAnchored, let origin { panel.setFrameOrigin(origin) }
            else { restorePlacement() }
        } else { controller.reset(); windowAnchored = false }
        behavior.show(); renderFrame(); panel.orderFrontRegardless(); startTimerIfNeeded(); persist()
    }

    private func scheduleRecall() {
        recallTimer?.invalidate(); recallTimer = nil
        guard !suspended, controller.state == .timeout, let deadline = returnDeadline else { return }
        let timer = Timer(timeInterval: max(0.01, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            guard let self, self.controller.state == .timeout, self.returnDeadline == deadline else { return }
            self.recallPet()
        }
        RunLoop.main.add(timer, forMode: .common); recallTimer = timer
    }

    func showContextMenu(event: NSEvent, view: NSView) { NSMenu.popUpContextMenu(makeMenu(), with: event, for: view) }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        let heading = NSMenuItem(title: "Watercolor Duck", action: nil, keyEquivalent: ""); heading.isEnabled = false
        menu.addItem(heading); menu.addItem(.separator())
        menu.addItem(item(behavior.isVisible ? "Hide Pet" : "Show Pet", #selector(toggleVisibility)))
        menu.addItem(item("Bring Back to This Screen", #selector(bringBack)))
        menu.addItem(item("Open Speech Menu", #selector(openSpeechMenu)))
        if !focusedWindow.hasPermission {
            menu.addItem(item("Enable Window Peek…", #selector(enableWindowPeek)))
        } else {
            let available = focusedWindow.peekOrigin(viewportSize: panel.frame.width) != nil
            let status = NSMenuItem(title: "Window Peek: \(available ? "Available" : "No clearance / no focused window")", action: nil, keyEquivalent: "")
            status.isEnabled = false; menu.addItem(status)
        }
        let animations = NSMenuItem(title: "Preview Animation", action: nil, keyEquivalent: "")
        let animationMenu = NSMenu()
        for state in DuckState.allCases where state != .timeout {
            let missing = sprites.missingStates.contains(state) ? " — pink placeholder" : ""
            let option = item("\(state.rawValue.uppercased()) · \(state.title)\(missing)", #selector(previewAnimation(_:)), checked: controller.state == state)
            option.representedObject = state.rawValue; animationMenu.addItem(option)
        }
        animations.submenu = animationMenu; menu.addItem(animations)
        if [.grabPhoto, .showPhoto, .showingPhoto, .grabCamera, .cameraIdle, .grabBible, .bibleIdle].contains(controller.state) {
            menu.addItem(item("Finish Current Preview", #selector(finishPreview)))
        }
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

    @objc private func openSpeechMenu() {
        if !behavior.isVisible { recallPet() }
        bubble.show(); updateBubblePlacement()
    }
    @objc private func enableWindowPeek() { focusedWindow.requestPermission() }
    @objc private func previewAnimation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let state = DuckState(rawValue: id) else { return }
        closeBubble(); returnDeadline = nil; awayMinutes = nil
        controller.reset(to: state); windowAnchored = false
        if state == .windowPeek, let origin = focusedWindow.peekOrigin(viewportSize: panel.frame.width) {
            panel.setFrameOrigin(origin); windowAnchored = true
        }
        behavior.show(); renderFrame()
        panel.orderFrontRegardless(); startTimerIfNeeded(); persist()
    }
    @objc private func finishPreview() { closeBubble() }
    @objc private func toggleVisibility() {
        if behavior.isVisible {
            controller.reset(to: .timeout); behavior.hide(); panel.orderOut(nil); bubble.close(immediately: true)
            returnDeadline = nil; awayMinutes = nil
        } else { recallPet() }
        if !behavior.isVisible { timer?.invalidate(); timer = nil; recallTimer?.invalidate(); recallTimer = nil }
        rebaseClock(); renderFrame(); updateMouseRouting()
        pointerCaptured = false; persist()
    }
    @objc private func bringBack() {
        guard let screen = screenAtPointer() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        recallPet(); preferences.clickThrough = false
        let area = screen.visibleFrame
        if !windowAnchored { panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2)) }
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
        windowAnchored = false
        savePlacement(); preferences.size = Double(sender.tag)
        let side = Double(sender.tag) * SpriteLibrary.viewportScale
        panel.setContentSize(NSSize(width: side, height: side))
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
        guard let point = Placement.restore(preferences.placement, size: panel.frame.width, displays: displays,
            fallbackID: (screenAtPointer() ?? NSScreen.main).map(screenID)) else { return }
        panel.setFrameOrigin(NSPoint(x: point.x, y: point.y))
    }
    private func savePlacement() {
        guard !windowAnchored else { return }
        guard let screen = panel.screen ?? screenAtPointer() ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let display = PetDisplay(id: screenID(screen), workArea: PetRect(x: area.minX, y: area.minY, width: area.width, height: area.height))
        let point = Placement.clamp(PetPoint(x: panel.frame.minX, y: panel.frame.minY), size: panel.frame.width, to: display.workArea)
        panel.setFrameOrigin(NSPoint(x: point.x, y: point.y))
        preferences.placement = Placement.save(origin: point, size: panel.frame.width, display: display)
    }
    private func persist() {
        preferences.isVisible = behavior.isVisible; preferences.isPaused = behavior.isPaused; store.save(preferences)
        if let deadline = returnDeadline { UserDefaults.standard.set(deadline, forKey: "sombrero.returnDeadline") }
        else { UserDefaults.standard.removeObject(forKey: "sombrero.returnDeadline") }
    }
    private func recoverAfterDisplayChange() { pointerCaptured = false; windowAnchored = false; restorePlacement(); savePlacement(); persist() }
    private func suspend() { bubble.close(immediately: true); controller.finishRoutine(); uiClock = DrawingClock(); suspended = true; rebaseClock(); pointerCaptured = false; timer?.invalidate(); timer = nil; recallTimer?.invalidate(); recallTimer = nil; panel.orderOut(nil) }
    private func resume() {
        suspended = false; rebaseClock(); restorePlacement()
        if behavior.isVisible { panel.orderFrontRegardless() }; startTimerIfNeeded()
    }
}
