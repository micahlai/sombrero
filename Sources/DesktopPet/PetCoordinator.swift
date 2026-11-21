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
    private let windowTracker = WindowTracker()
    private var attachment = PetAttachment()
    private var sideAttachment: WindowSideAttachment? { attachment.side }
    private var configuredEntryGeneration = -1
    private var entryFlip = false
    private var preparedTop: WindowTracker.Target?
    private var preparedSide: WindowTracker.SideTarget?
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
            button.image = NSImage(systemSymbolName: "square.fill", accessibilityDescription: "sombrero controls")
            button.image?.isTemplate = true
            button.toolTip = "sombrero — show, hide, or recover your companion"
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
        let timer = Timer(timeInterval: 1.0 / PetConstants.Animation.updateFPS, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = PetConstants.Animation.timerTolerance
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    private func tick() {
        if let deadline = returnDeadline, Date() >= deadline, controller.state == .timeout { recallPet() }
        updateWindowAttachment()
        let now = ProcessInfo.processInfo.systemUptime
        let uiDelta = uiClock.sample(at: now, running: !suspended)
        let delta = clock.sample(at: now, running: behavior.isVisible && !behavior.isPaused && !suspended)
        let oldState = playback.state, oldFrame = playback.frameIndex, oldGeneration = controller.generation
        controller.setDialogueOpen(bubble.isVisible || menuTracking)
        if behavior.isVisible && !pointerCaptured && !menuTracking {
            let point = NSEvent.mouseLocation
            let local = NSPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
            if !bubble.isVisible {
                controller.setPet(!preferences.clickThrough && petView.containsInteractivePoint(local))
            }
        }
        playback.advance(by: delta, controller: &controller) { Double.random(in: 0..<1) }
        bubble.advance(by: uiDelta)
        controller.setDialogueOpen(bubble.isVisible || menuTracking)
        if oldState != playback.state || oldFrame != playback.frameIndex || oldGeneration != controller.generation { renderFrame() }
        if controller.state == .timeout && behavior.isVisible {
            behavior.hide(); panel.orderOut(nil); bubble.close(immediately: true)
            if let minutes = awayMinutes { returnDeadline = Date().addingTimeInterval(Double(minutes) * PetConstants.Interaction.secondsPerMinute) }
            awayMinutes = nil; persist()
            timer?.invalidate(); timer = nil; scheduleRecall()
        }
        updateBubblePlacement(); updateMouseRouting()
    }

    private func rebaseClock() {
        _ = clock.sample(at: ProcessInfo.processInfo.systemUptime, running: behavior.isVisible && !behavior.isPaused && !suspended)
    }

    private func renderFrame() {
        configureEntryIfNeeded()
        attachment.didEnterState(controller.state)
        if attachment.window != nil { updateWindowAttachment() }
        petView.flipsHorizontally = controller.state == .peek && entryFlip
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
        attachment.drag()
        panel.setFrameOrigin(origin)
        updateBubblePlacement()
        // Allow crossing displays during drag; recover/clamp on release.
    }

    func toggleBubble() {
        if bubble.wantsOpen { closeBubble() }
        else { showBubble() }
    }

    private func showBubble() {
        controller.setDialogueOpen(true)
        renderFrame(); bubble.show(); updateBubblePlacement()
    }

    private func closeBubble() {
        bubble.close(); controller.finishRoutine(); controller.setPet(false)
    }

    private func updateBubblePlacement() {
        guard bubble.isVisible, let screen = placementScreen() else { return }
        var bounds = sprites.occupiedBounds(state: controller.state)
        if petView.flipsHorizontally, let rect = bounds { bounds = CGRect(x: 1-rect.maxX, y: rect.minY, width: rect.width, height: rect.height) }
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
            preparedTop = windowTracker.targets(viewportSize: panel.frame.width, visibleBounds: anchoringBounds, baselineY: windowPeekBaselineY, force: true).randomElement()
            preparedSide = windowTracker.sideTargets(visibleBounds: referenceBounds, artwork: peekArtwork).randomElement()
            controller.recall(windowAvailable: preparedTop != nil, sideAvailable: preparedSide != nil)
        } else { controller.reset() }
        behavior.show(); renderFrame(); panel.orderFrontRegardless(); startTimerIfNeeded(); persist()
    }

    private func scheduleRecall() {
        recallTimer?.invalidate(); recallTimer = nil
        guard !suspended, controller.state == .timeout, let deadline = returnDeadline else { return }
        let timer = Timer(timeInterval: max(PetConstants.Interaction.recallTimerMinimumDelay, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            guard let self, self.controller.state == .timeout, self.returnDeadline == deadline else { return }
            self.recallPet()
        }
        RunLoop.main.add(timer, forMode: .common); recallTimer = timer
    }

    func showContextMenu(event: NSEvent, view: NSView) { NSMenu.popUpContextMenu(makeMenu(), with: event, for: view) }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        let heading = NSMenuItem(title: "sombrero", action: nil, keyEquivalent: ""); heading.isEnabled = false
        menu.addItem(heading); menu.addItem(.separator())
        menu.addItem(item(behavior.isVisible ? "Hide Pet" : "Show Pet", #selector(toggleVisibility)))
        menu.addItem(item("Bring Back to This Screen", #selector(bringBack)))
        menu.addItem(item("Open Speech Menu", #selector(openSpeechMenu)))
        let topAvailable = !windowTracker.targets(viewportSize: panel.frame.width, visibleBounds: anchoringBounds, baselineY: windowPeekBaselineY).isEmpty
        let sideAvailable = !windowTracker.sideTargets(visibleBounds: referenceBounds, artwork: peekArtwork).isEmpty
        let status = NSMenuItem(title: "Window peek: top \(topAvailable ? "available" : "unavailable"), side \(sideAvailable ? "available" : "unavailable")", action: nil, keyEquivalent: "")
        status.isEnabled = false; menu.addItem(status)
        let animations = NSMenuItem(title: "Preview Animation", action: nil, keyEquivalent: "")
        let animationMenu = NSMenu()
        for state in DuckState.allCases where state != .timeout {
            let missing = sprites.missingStates.contains(state) ? " — pink placeholder" : ""
            let option = item("\(state.rawValue.uppercased()) · \(state.title)\(missing)", #selector(previewAnimation(_:)), checked: controller.state == state)
            option.representedObject = state.rawValue; animationMenu.addItem(option)
        }
        animations.submenu = animationMenu; menu.addItem(animations)
        let sidePreview=item("Preview 4B from Window Side", #selector(previewWindowSide))
        sidePreview.isEnabled=sideAvailable; menu.addItem(sidePreview)
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
        for (title, size) in PetConstants.Size.options {
            let option = item(title, #selector(changeSize(_:)), checked: preferences.size == Double(size))
            option.tag = size; submenu.addItem(option)
        }
        sizes.submenu = submenu; menu.addItem(sizes)
        menu.addItem(.separator())
        menu.addItem(item("Quit sombrero", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.state = checked ? .on : .off; return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuTracking = true; panel.ignoresMouseEvents = false
        controller.setDialogueOpen(true); renderFrame()
        // Rebuild the status menu before display so labels/checkmarks reflect pet actions.
        let fresh = makeMenu()
        menu.removeAllItems()
        for item in fresh.items { fresh.removeItem(item); menu.addItem(item) }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTracking = false; controller.setDialogueOpen(bubble.isVisible); updateMouseRouting()
    }

    func recoverCompanion() { bringBack() }

    @objc private func openSpeechMenu() {
        if !behavior.isVisible { recallPet() }
        showBubble()
    }
    @objc private func previewAnimation(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let state = DuckState(rawValue: id) else { return }
        closeBubble(); returnDeadline = nil; awayMinutes = nil
        preparedTop = nil; preparedSide = nil
        controller.reset(to: state)
        behavior.show(); renderFrame()
        panel.orderFrontRegardless(); startTimerIfNeeded(); persist()
    }
    @objc private func previewWindowSide() {
        guard let candidate=windowTracker.sideTargets(visibleBounds:referenceBounds,artwork:peekArtwork,force:true).randomElement() else { return }
        closeBubble(); preparedSide=candidate; preparedTop=nil; returnDeadline=nil; awayMinutes=nil
        controller.reset(to:.timeout); controller.recall(sideAvailable:true) { 0.75 }
        behavior.show(); renderFrame(); panel.orderFrontRegardless(); startTimerIfNeeded(); persist()
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
        let wasHidden = !behavior.isVisible
        recallPet(); preferences.clickThrough = false
        if !wasHidden {
            attachment.detach()
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX-panel.frame.width/2, y: area.midY-panel.frame.height/2))
        }
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
        let side = Double(sender.tag)*PetConstants.Geometry.viewportScale
        panel.setContentSize(NSSize(width:side,height:side))
        if attachment.window != nil || sideAttachment != nil { updateWindowAttachment(force:true) }
        else { restorePlacement() }
        savePlacement(); persist()
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private var displays: [PetDisplay] { NSScreen.screens.map { screen in
        let area = freeArea(screen)
        return PetDisplay(id: screenID(screen), workArea: PetRect(x: area.minX, y: area.minY, width: area.width, height: area.height))
    } }
    private func screenID(_ screen: NSScreen) -> String { String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown") }
    private func screenAtPointer() -> NSScreen? { NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } }
    private func freeArea(_ screen: NSScreen) -> NSRect {
        PetConstants.Geometry.freePlacementUsesWorkArea ? screen.visibleFrame : screen.frame
    }
    private var visibleBounds: PetRect {
        let normal = petView.sprite?.occupiedBounds ?? sprites.occupiedBounds(state: controller.state)
        guard let normal, !normal.isNull else { return PetConstants.Geometry.placeholderBounds.scaled(by: panel.frame.width) }
        let x = petView.flipsHorizontally ? 1-normal.maxX : normal.minX
        return PetRect(x:x,y:normal.minY,width:normal.width,height:normal.height).scaled(by:panel.frame.width)
    }
    private var peekArtwork: PeekArtwork {
        guard let first = sprites.frame(state: .peek, index: 0) else {
            return PeekArtwork(viewportSize: panel.frame.width, cutX: panel.frame.width/2)
        }
        let cut = first.placement.minX + first.placement.width*PetConstants.ScreenEntry.sourceCutX/Double(first.image.width)
        return PeekArtwork(viewportSize: panel.frame.width, cutX: cut*panel.frame.width)
    }
    private var windowPeekBaselineY: Double {
        guard let first = sprites.frame(state: .windowPeek, index: 0) else {
            return panel.frame.width*PetConstants.Geometry.groundAnchor.y
        }
        let ledge = first.placement.maxY-first.placement.height*PetConstants.WindowEntry.sourceLedgeY/Double(first.image.height)
        return ledge*panel.frame.width
    }
    private var referenceBounds: PetRect {
        let normal = sprites.occupiedBounds(state:.look)
        return normal.map { PetRect(x:$0.minX,y:$0.minY,width:$0.width,height:$0.height).scaled(by:panel.frame.width) }
            ?? PetConstants.Geometry.placeholderBounds.scaled(by:panel.frame.width)
    }
    private var anchoringBounds: PetRect {
        let states: [DuckState] = [.look,.alternateLook,.wave,.standingPet,.sitDown,.standUp,.sitting,.sittingLook,.sittingPet]
        let combined = states.compactMap { sprites.occupiedBounds(state:$0) }.reduce(CGRect.null) { $0.union($1) }
        return combined.isNull ? referenceBounds : PetRect(x:combined.minX,y:combined.minY,width:combined.width,height:combined.height).scaled(by:panel.frame.width)
    }
    private func configureEntryIfNeeded() {
        guard [.peek,.windowPeek].contains(controller.state), configuredEntryGeneration != controller.generation else { return }
        attachment.detach(); entryFlip=false
        if controller.state == .windowPeek {
            if let target = preparedTop ?? windowTracker.targets(viewportSize:panel.frame.width,visibleBounds:anchoringBounds,baselineY:windowPeekBaselineY,force:true).randomElement() {
                attachment.enterWindow(target.attachment); panel.setFrameOrigin(target.origin)
                configuredEntryGeneration = controller.generation; preparedTop=nil; preparedSide=nil; return
            }
            controller.fallbackToScreenEntry()
        } else if controller.recallEntry == .windowSide {
            if let target = preparedSide ?? windowTracker.sideTargets(visibleBounds:referenceBounds,artwork:peekArtwork,force:true).randomElement() {
                attachment.enterSide(target.attachment); entryFlip=target.attachment.flipsAnimation; panel.setFrameOrigin(target.origin)
                configuredEntryGeneration = controller.generation; preparedTop=nil; preparedSide=nil; return
            }
            controller.fallbackToScreenEntry()
        }
        if let screen = screenAtPointer() ?? NSScreen.main ?? NSScreen.screens.first {
            let rect=screen.frame
            let placement=ScreenEntryPlacement.choose(screen:PetRect(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height),
                referenceBounds:referenceBounds,artwork:peekArtwork,sideSample:Double.random(in:0..<1),heightSample:Double.random(in:0..<1))
            attachment.enterScreen(placement.edge); entryFlip=placement.flipsAnimation; panel.setFrameOrigin(NSPoint(x:placement.origin.x,y:placement.origin.y))
        }
        configuredEntryGeneration=controller.generation; preparedTop=nil; preparedSide=nil
    }
    private func updateWindowAttachment(force: Bool = false) {
        guard !pointerCaptured else { return }
        let origin: NSPoint?
        if let target=attachment.window {
            origin=windowTracker.origin(for:target,viewportSize:panel.frame.width,visibleBounds:anchoringBounds,
                baselineY:controller.state == .windowPeek ? windowPeekBaselineY : nil,force:force)
        } else if let target=sideAttachment, controller.state == .peek {
            origin=windowTracker.origin(for:target,visibleBounds:referenceBounds,artwork:peekArtwork,force:force)
        } else { return }
        if let origin { panel.setFrameOrigin(origin) }
        else { attachment.detach(); savePlacement() }
    }
    private func placementScreen() -> NSScreen? {
        let b=visibleBounds
        let center=NSPoint(x:panel.frame.minX+b.center.x,y:panel.frame.minY+b.center.y)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? screenAtPointer() ?? NSScreen.main
    }
    private func restorePlacement() {
        guard let point=Placement.restore(preferences.placement,viewportSize:panel.frame.width,visibleBounds:visibleBounds,displays:displays,
            fallbackID:(screenAtPointer() ?? NSScreen.main).map(screenID)) else { return }
        panel.setFrameOrigin(NSPoint(x:point.x,y:point.y))
    }
    private func savePlacement() {
        guard attachment.window == nil, sideAttachment == nil, let screen=placementScreen() else { return }
        let area=freeArea(screen)
        let display=PetDisplay(id:screenID(screen),workArea:PetRect(x:area.minX,y:area.minY,width:area.width,height:area.height))
        let point=Placement.clamp(PetPoint(x:panel.frame.minX,y:panel.frame.minY),visibleBounds:visibleBounds,to:display.workArea)
        panel.setFrameOrigin(NSPoint(x:point.x,y:point.y))
        preferences.placement=Placement.save(origin:point,visibleBounds:visibleBounds,display:display)
    }
    private func persist() {
        preferences.isVisible = behavior.isVisible; preferences.isPaused = behavior.isPaused; store.save(preferences)
        if let deadline = returnDeadline { UserDefaults.standard.set(deadline, forKey: "sombrero.returnDeadline") }
        else { UserDefaults.standard.removeObject(forKey: "sombrero.returnDeadline") }
    }
    private func recoverAfterDisplayChange() { pointerCaptured = false; attachment.detach(); restorePlacement(); savePlacement(); persist() }
    private func suspend() { bubble.close(immediately: true); controller.finishRoutine(); uiClock = DrawingClock(); suspended = true; rebaseClock(); pointerCaptured = false; timer?.invalidate(); timer = nil; recallTimer?.invalidate(); recallTimer = nil; panel.orderOut(nil) }
    private func resume() {
        suspended = false; rebaseClock();
        if attachment.window != nil || sideAttachment != nil { updateWindowAttachment(force:true) } else { restorePlacement() }
        if behavior.isVisible { panel.orderFrontRegardless() }; startTimerIfNeeded()
    }
}
