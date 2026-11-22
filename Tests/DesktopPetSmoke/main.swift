// Component render checks: no interaction with the user's other windows or services.
import AppKit
import PetAssets
import PetCore

@MainActor
func runDesktopSmoke() throws {
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let assets = SpriteLibrary()
precondition(assets.failure == nil, "Packaged assets must load")
let bubble = SpeechBubble(images: assets.speechFrames)
let output = URL(fileURLWithPath: ".build/ui-smoke")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, mode) in [("menu", SpeechBubble.Mode.menu), ("away", .away), ("bible", .bible)] {
    bubble.show(mode: mode); bubble.advance(by: 1); bubble.panel.orderOut(nil)
    let view = bubble.panel.contentView!
    view.layoutSubtreeIfNeeded()
    let body = NSRect(x: view.bounds.width*0.04, y: view.bounds.height*0.30, width: view.bounds.width*0.92, height: view.bounds.height*0.66)
    var buttonCount = 0
    func checkControls(_ parent: NSView) {
        for child in parent.subviews {
            if child is NSButton || child is NSTextField {
                let rect = child.convert(child.bounds, to: view)
                precondition(body.contains(rect), "\(name): control exceeds bubble body: \(rect)")
                if let button = child as? NSButton {
                    buttonCount += 1
                    let color = button.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                    precondition(color != nil, "Bubble button must have fixed ink color")
                }
                if let label = child as? NSTextField { precondition(label.stringValue.lowercased() != "sombrero") }
            }
            checkControls(child)
        }
    }
    checkControls(view)
    precondition(buttonCount > 0)
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
    print("PASS \(name): controls fit final speech drawing")
}
bubble.show(); bubble.advance(by: 1)
let workArea = NSRect(x: -800, y: 0, width: 800, height: 600)
bubble.anchor(to: NSRect(x: -90, y: 40, width: 70, height: 120), workArea: workArea)
precondition(workArea.contains(bubble.panel.frame), "Flipped bubble must remain on screen")
precondition(!bubble.panel.frame.intersects(NSRect(x: -90, y: 40, width: 70, height: 120)))
precondition(bubble.panel.frame.width < 200 && bubble.panel.frame.height < 250, "Menu stays compact while accommodating font metrics")
bubble.panel.appearance = NSAppearance(named: .darkAqua)
bubble.panel.orderOut(nil)
let view = bubble.panel.contentView!
view.layoutSubtreeIfNeeded()
let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
view.cacheDisplay(in: view.bounds, to: bitmap)
try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("menu-flipped.png"))
bubble.anchor(to: .zero, workArea: NSRect(x: 0, y: 0, width: 300, height: 350))
precondition(bubble.panel.frame.maxX <= 300 && bubble.panel.frame.maxY <= 350)
bubble.close(immediately: true)
for sprite in [NSRect(x: -780, y: 440, width: 100, height: 130), NSRect(x: -120, y: 440, width: 100, height: 130), NSRect(x: -440, y: 440, width: 100, height: 130)] {
    bubble.anchor(to: sprite, workArea: workArea)
    precondition(workArea.contains(bubble.panel.frame))
    precondition(!bubble.panel.frame.intersects(sprite), "Bubble overlaps sprite at top edge")
}
print("PASS compact size, fixed ink, no heading, and non-overlapping placement")

let duckPanel = PetPanel(size: 300)
let outsideCanvas = NSRect(x: -120, y: -70, width: 300, height: 300)
precondition(duckPanel.constrainFrameRect(outsideCanvas, to: NSScreen.main) == outsideCanvas,
             "AppKit must allow transparent padding outside physical screen edges")
duckPanel.setFrameOrigin(outsideCanvas.origin)
precondition(duckPanel.frame.origin == outsideCanvas.origin)
let duckView = SpriteView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
duckView.sprite = assets.frame(state: .peek, index: 0)
precondition(duckView.sprite != nil, "Imported 4b artwork must be available")
var asymmetricPoints = 0
for y in stride(from: 2.5, to: 300.0, by: 5) {
    for x in stride(from: 2.5, to: 300.0, by: 5) {
        let point = NSPoint(x: x, y: y)
        duckView.flipsHorizontally = false
        let original = duckView.containsInteractivePoint(point)
        let mirrored = duckView.containsInteractivePoint(NSPoint(x: 300-x, y: y))
        duckView.flipsHorizontally = true
        precondition(duckView.containsInteractivePoint(point) == mirrored, "Right-entry hit testing must mirror its artwork")
        if original != mirrored { asymmetricPoints += 1 }
    }
}
precondition(asymmetricPoints > 0, "Flip check must exercise an asymmetric frame")
for flipped in [false, true] {
    duckView.flipsHorizontally = flipped
    let bitmap = duckView.bitmapImageRepForCachingDisplay(in: duckView.bounds)!
    duckView.cacheDisplay(in: duckView.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(flipped ? "4b-right.png" : "4b-left.png"))
}
print("PASS native edge placement and mirrored entry rendering/input")

// Exercise the actual WindowServer parser and candidate detector. Floating
// full-screen overlays report alpha=1 even when their pixels are transparent.
let display = WindowTracker.Display(frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                                    visibleFrame: NSRect(x: 0, y: 61, width: 1512, height: 888))
func windowInfo(_ id: Int, _ rect: NSRect, layer: Int = 0, pid: Int = 123) -> [String: Any] {
    [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
     kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1.0,
     kCGWindowBounds as String: ["X": rect.minX, "Y": display.frame.maxY-rect.maxY,
                                "Width": rect.width, "Height": rect.height]]
}
var document = NSRect(x: 400, y: 200, width: 600, height: 400)
let overlay = windowInfo(99, display.frame, layer: 20)
var inventory = [overlay, windowInfo(42, document)]
let tracker = WindowTracker(displays: { [display] }, readWindowInfo: { inventory }, ownPID: 999)
let viewport = 300.0
let reference = PetRect(x: 109, y: 76, width: 73, height: 120)
let anchorBounds = PetRect(x: 91, y: 73, width: 109, height: 128)
let firstPeek = assets.frame(state: .peek, index: 0)!
let cut = (firstPeek.placement.minX + firstPeek.placement.width*PetConstants.ScreenEntry.sourceCutX/Double(firstPeek.image.width))*viewport
let artwork = PeekArtwork(viewportSize: viewport, cutX: cut)
let top = tracker.targets(viewportSize: viewport, visibleBounds: anchorBounds, force: true)
let sides = tracker.sideTargets(visibleBounds: reference, artwork: artwork)
precondition(top.map { $0.attachment.windowID } == [42], "Transparent floating overlay must not hide top clearance")
precondition(sides.count == 2 && sides.allSatisfy { $0.attachment.windowID == 42 }, "Both window sides must be detected through a floating overlay")
for side in sides {
    let boundary = side.origin.x+artwork.boundaryX(flipped: side.attachment.flipsAnimation)
    let expected = side.attachment.edge == .left ? document.minX : document.maxX
    precondition(abs(boundary-expected) < 0.001, "Window-side cut must meet the window border")
}
let area = PetRect(x: 0, y: 0, width: 1512, height: 982)
for sample in [0.0, 0.9] {
    let entry = ScreenEntryPlacement.choose(screen: area, referenceBounds: reference, artwork: artwork, sideSample: sample, heightSample: 0.5)
    let boundary = entry.origin.x+artwork.boundaryX(flipped: entry.flipsAnimation)
    precondition(abs(boundary-(entry.edge == .left ? area.x : area.maxX)) < 0.001, "Actual calibrated 4b cut must meet the physical screen edge")
}
document = document.offsetBy(dx: 40, dy: 20)
inventory = [overlay, windowInfo(42, document)]
let moved = tracker.origin(for: top[0].attachment, viewportSize: viewport, visibleBounds: anchorBounds, force: true)!
precondition(abs(moved.x-top[0].origin.x-40) < 0.001 && abs(moved.y-top[0].origin.y-20) < 0.001)
let movedSide = tracker.origin(for: sides[0].attachment, visibleBounds: reference, artwork: artwork)!
precondition(abs(movedSide.x-sides[0].origin.x-40) < 0.001 && abs(movedSide.y-sides[0].origin.y-20) < 0.001)
inventory = [windowInfo(100, display.visibleFrame), windowInfo(42, document)]
precondition(tracker.targets(viewportSize: viewport, visibleBounds: anchorBounds, force: true).isEmpty,
             "A real foreground document must still block windows behind it")
precondition(tracker.sideTargets(visibleBounds: reference, artwork: artwork).isEmpty)
print("PASS WindowServer detection: transparent overlay, both clearances, moving anchors, real occlusion, calibrated cut alignment")

// Render the supplied 4c ledge against a window edge at every native pet size.
// This catches source padding/calibration offsets, beyond a synthetic ground anchor.
inventory = [overlay, windowInfo(42, document)]
let firstTop = assets.frame(state: .windowPeek, index: 0)!
let ledgeNormalized = firstTop.placement.maxY-firstTop.placement.height*PetConstants.WindowEntry.sourceLedgeY/Double(firstTop.image.height)
for (name, petSize) in PetConstants.Size.options {
    let side=Double(petSize)*PetConstants.Geometry.viewportScale
    let ledge=ledgeNormalized*side
    let normalBounds=PetRect(x:0.31,y:0.25,width:0.38,height:0.44).scaled(by:side)
    let topTarget=tracker.targets(viewportSize:side,visibleBounds:normalBounds,baselineY:ledge,force:true).first!
    precondition(abs(topTarget.origin.y+ledge-document.maxY) < 0.001, "4c ledge must meet the window top at \(name) size")
    let tracked=tracker.origin(for:topTarget.attachment,viewportSize:side,visibleBounds:normalBounds,baselineY:ledge)!
    precondition(abs(tracked.y+ledge-document.maxY) < 0.001, "Following the window must retain the calibrated baseline")
    for frame in [0,38] {
        let sprite=assets.frame(state:.windowPeek,index:frame)!
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:800,pixelsHigh:560,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.size=NSSize(width:400,height:280)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        let context=NSGraphicsContext.current!.cgContext
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x:0,y:0,width:400,height:280))
        context.setFillColor(NSColor(calibratedWhite:0.15,alpha:1).cgColor); context.fill(CGRect(x:20,y:0,width:360,height:100))
        let origin=NSPoint(x:200-side/2,y:100-ledge)
        let rect=sprite.placement
        context.draw(sprite.image,in:CGRect(x:origin.x+rect.minX*side,y:origin.y+rect.minY*side,width:rect.width*side,height:rect.height*side))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("4c-edge-\(name.lowercased())-\(frame).png"))
    }
}
print("PASS actual 4c ledge aligned to window top at small, medium, and large sizes")

let bibleCatalog=BibleLibrary().catalog!
let scriptureBubble=SpeechBubble(images:assets.speechFrames)
var longest=bibleCatalog.verses[0]
for verse in bibleCatalog.verses {
    scriptureBubble.setBible(verse:verse); scriptureBubble.show(mode:.bible); scriptureBubble.advance(by:1)
    scriptureBubble.panel.orderOut(nil)
    let root=scriptureBubble.panel.contentView!
    root.layoutSubtreeIfNeeded()
    precondition(root.bounds.width <= 220 && root.bounds.height <= 260,"Verse length must not enlarge the compact reader")
    precondition(scriptureBubble.biblePageTexts.joined() == verse.text,"Pagination must retain every source character")
    for page in scriptureBubble.biblePageTexts.indices {
        if page>0 { scriptureBubble.changeBiblePage(by:1) }
        root.layoutSubtreeIfNeeded()
        var foundText=false, foundNext=false
        func checkReader(_ parent: NSView) {
            for child in parent.subviews {
                if let scroll=child as? NSScrollView, let text=scroll.documentView as? NSTextView {
                    foundText=true
                    precondition(text.string == scriptureBubble.biblePageTexts[page].trimmingCharacters(in:.whitespacesAndNewlines))
                    let manager=text.layoutManager!,container=text.textContainer!
                    manager.ensureLayout(for:container)
                    precondition(manager.glyphRange(for:container).length == manager.numberOfGlyphs)
                    precondition(manager.usedRect(for:container).maxY+2*text.textContainerInset.height <= text.frame.height+1,
                                 "Last line must remain reachable: \(verse.reference)")
                    precondition(text.frame.height <= scroll.contentSize.height+1,
                                 "Normal reader must use more pages instead of scrolling: \(verse.reference)")
                    precondition(root.bounds.contains(scroll.convert(scroll.bounds,to:root)))
                }
                if let button=child as? NSButton {
                    precondition(button.title != "Done" && button.title != "Back","Reader shows only page controls")
                    if button.title == "Next" && button.isEnabled { foundNext=true }
                    precondition(root.bounds.contains(button.convert(button.bounds,to:root)))
                    precondition(button.bounds.width >= button.attributedTitle.size().width+2*PetConstants.Speech.horizontalTextPadding)
                    precondition(button.bounds.height >= button.font!.ascender-button.font!.descender+button.font!.leading)
                }
                if let label=child as? NSTextField {
                    precondition(!label.stringValue.contains("eBible.org") && !label.stringValue.contains("WEB") && !label.stringValue.contains("World English Bible"),
                                 "Reader must not show a source or translation line")
                }
                checkReader(child)
            }
        }
        checkReader(root)
        precondition(foundText && (page == scriptureBubble.biblePageTexts.count-1 || foundNext))
    }
    if verse.text.count>longest.text.count { longest=verse }
}
scriptureBubble.setBible(verse:longest); scriptureBubble.show(mode:.bible)
let readerRoot=scriptureBubble.panel.contentView!; readerRoot.layoutSubtreeIfNeeded()
let readerBitmap=readerRoot.bitmapImageRepForCachingDisplay(in:readerRoot.bounds)!
readerRoot.cacheDisplay(in:readerRoot.bounds,to:readerBitmap)
try readerBitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("bible-reader-longest.png"))
scriptureBubble.close(immediately:true)
let dailyFile=output.appendingPathComponent("daily-verses-test.json")
let dailyStore=DailyBibleStore(file:dailyFile)
var persisted=DailyBible(); persisted.reconcile(at:Date(),catalog:bibleCatalog) { 0 }
dailyStore.save(persisted); precondition(dailyStore.load() == persisted)
let assignment=persisted.today(at:Date())!
var session=BibleReadingSession(verse:bibleCatalog.verses.first { $0.id == assignment.verseID }!,localDate:assignment.localDate)
precondition(!session.complete(in:&persisted)); session.presentedContent(); precondition(session.complete(in:&persisted))
dailyStore.save(persisted); precondition(dailyStore.load() == persisted)
print("PASS all 100 passages fit a compact paginated reader without a source/version line or Done button")

let stableBubble=SpeechBubble(images:assets.speechFrames)
let envelope=assets.conversationBounds()!
let stableDuck=NSRect(x:400+envelope.minX*300,y:100+envelope.minY*300,width:envelope.width*300,height:envelope.height*300)
let conversationArea=NSRect(x:0,y:0,width:1500,height:1000)
stableBubble.show(); stableBubble.advance(by:1); stableBubble.panel.orderOut(nil)
stableBubble.anchor(to:stableDuck,workArea:conversationArea)
let stableFrame=stableBubble.panel.frame
for (state,frames) in assets.frames where state != .goodbye {
    for frame in frames {
        duckView.state=state; duckView.sprite=frame
        stableBubble.anchor(to:stableDuck,workArea:conversationArea)
        precondition(stableBubble.panel.frame == stableFrame,"Animation drawings must not change the speech anchor")
    }
}
stableBubble.setBible(verse:nil,status:"Reader unavailable"); stableBubble.setMode(.bible)
stableBubble.anchor(to:stableDuck,workArea:conversationArea); let readerFrame=stableBubble.panel.frame
stableBubble.setBible(verse:longest); stableBubble.anchor(to:stableDuck,workArea:conversationArea)
precondition(stableBubble.panel.frame == readerFrame,"Changing reader content must not move the reader")
for _ in stableBubble.biblePageTexts.indices {
    stableBubble.changeBiblePage(by:1); stableBubble.anchor(to:stableDuck,workArea:conversationArea)
    precondition(stableBubble.panel.frame == readerFrame,"Page changes must not move the reader")
}
stableBubble.anchor(to:stableDuck.offsetBy(dx:40,dy:20),workArea:conversationArea)
precondition(abs(stableBubble.panel.frame.minX-readerFrame.minX-40)<0.001 && abs(stableBubble.panel.frame.minY-readerFrame.minY-20)<0.001)
stableBubble.close(immediately:true)
print("PASS speech position stays fixed across every drawing, loading, and page changes; dragging still carries it")

let constrainedBubble=SpeechBubble(images:assets.speechFrames)
constrainedBubble.setBible(verse:longest)
constrainedBubble.show(mode:.bible); constrainedBubble.advance(by:1)
for area in [NSRect(x:-800,y:0,width:800,height:600), NSRect(x:0,y:0,width:300,height:350)] {
    for duck in [NSRect(x:area.minX,y:area.maxY-140,width:100,height:130),
                 NSRect(x:area.midX-50,y:area.midY-60,width:100,height:130)] {
        constrainedBubble.anchor(to:duck,workArea:area)
        precondition(area.contains(constrainedBubble.panel.frame),"Constrained reader must stay on screen even when no non-overlapping placement fits")
        let root=constrainedBubble.panel.contentView!
        root.layoutSubtreeIfNeeded()
        func checkConstrainedControls(_ parent: NSView) {
            for child in parent.subviews {
                if child is NSButton || child is NSScrollView {
                    precondition(root.bounds.contains(child.convert(child.bounds,to:root)),"Reader controls must remain reachable on a small work area")
                }
                checkConstrainedControls(child)
            }
        }
        checkConstrainedControls(root)
    }
}
constrainedBubble.close(immediately:true)
print("PASS reader and page controls remain on screen in constrained work areas")

// Exercise the real coordinator tick order, not just the reader in isolation.
// Dedicated files/defaults keep these checks away from the user's daily history.
let integrationOutput=output.appendingPathComponent("bible-integration-\(UUID().uuidString)")
let integrationStore=DailyBibleStore(file:integrationOutput.appendingPathComponent("daily.json"))
let integrationPreferences=PreferenceStore(file:integrationOutput.appendingPathComponent("preferences.json"))
let defaultsName="sombrero.bible-tests.\(UUID().uuidString)"
let integrationDefaults=UserDefaults(suiteName:defaultsName)!
defer { integrationDefaults.removePersistentDomain(forName:defaultsName) }
let integrationCalendar=DailyBible.calendar()
let integrationDate=integrationCalendar.date(from:DateComponents(year:2026,month:11,day:21,hour:22))!
var integrationDaily=DailyBible()
let longestIndex=bibleCatalog.verses.firstIndex { $0.id == longest.id }!
var assignmentRolls=[(Double(longestIndex)+0.5)/Double(bibleCatalog.verses.count)].makeIterator()
integrationDaily.reconcile(at:integrationDate,catalog:bibleCatalog,calendar:integrationCalendar) { assignmentRolls.next()! }
integrationStore.save(integrationDaily)
let coordinator=PetCoordinator(store:integrationPreferences,dailyBibleStore:integrationStore,
                               defaults:integrationDefaults,currentDate:{ integrationDate })
defer { coordinator.stop() }
let dailyVerseID=integrationDaily.today(at:integrationDate)!.verseID
var uptime=100.0
func stepCoordinator(_ seconds: Double) {
    uptime+=seconds
    coordinator.tick(at:uptime)
}
func completeReader() {
    while coordinator.bubble.biblePageIndex<coordinator.bubble.biblePageTexts.count-1 {
        coordinator.bubble.changeBiblePage(by:1)
    }
    stepCoordinator(0.1)
}
coordinator.bubble.setBibleAvailable(true); coordinator.bubble.show(); coordinator.bubble.advance(by:1)
let originalMenuSize=coordinator.bubble.panel.frame.size
coordinator.readDailyBible()
precondition(!coordinator.bubble.wantsOpen && coordinator.bubble.isVisible,"Existing menu must animate closed")
precondition(coordinator.bubble.panel.frame.size == originalMenuSize,"Closing menu must retain its original drawing size")
precondition(coordinator.controller.state == .grabBible)
coordinator.tick(at:uptime); stepCoordinator(1)
precondition(!coordinator.bubble.isVisible && coordinator.bubble.bibleVerseID == nil,"Bubble must stay hidden during 7a")
precondition(coordinator.bibleSession?.hasPresentedContent == false,"7a must not count as displayed scripture")
stepCoordinator(Double(assets.frameCounts[.grabBible]!)/Double(PetConstants.Animation.drawingFPS)-1+0.01)
precondition(coordinator.controller.state == .bibleIdle)
precondition(coordinator.bubble.wantsOpen && !coordinator.bubble.isExpanded,"Reader must animate open only after 7a finishes")
precondition(coordinator.bibleSession?.hasPresentedContent == false)
stepCoordinator(1)
precondition(coordinator.bubble.presentedBibleVerseID == dailyVerseID)
precondition(coordinator.bibleSession?.hasPresentedContent == true)
precondition(coordinator.dailyBible.today(at:integrationDate)?.isRead == false)
coordinator.bubble.onAction?(.close)
precondition(coordinator.bibleSession == nil && !coordinator.controller.reading)
precondition(integrationStore.load().today(at:integrationDate)?.isRead == false,"Cancel preserves the unread badge")
stepCoordinator(Double(assets.frameCounts[.bibleIdle]!)/Double(PetConstants.Animation.drawingFPS))
precondition(coordinator.controller.state == .stowBible)
coordinator.readDailyBible()
precondition(coordinator.controller.pending == [.bibleRead],"Reopening during 7c retains the new request")
stepCoordinator(Double(assets.frameCounts[.stowBible]!)/Double(PetConstants.Animation.drawingFPS))
precondition(coordinator.controller.state == .grabBible)
stepCoordinator(Double(assets.frameCounts[.grabBible]!)/Double(PetConstants.Animation.drawingFPS))
stepCoordinator(1)
precondition(coordinator.bubble.presentedBibleVerseID == dailyVerseID)
completeReader()
precondition(integrationStore.load().today(at:integrationDate)?.isRead == true,"Displaying the last page persists the daily read state")
precondition(coordinator.controller.reading && coordinator.bubble.wantsOpen,"Final page stays open until dismissed")
coordinator.toggleBubble()
precondition(!coordinator.controller.reading && coordinator.bibleSession == nil)

// A preview is independent of the daily assignment, even when completed.
integrationStore.save(integrationDaily)
let previewCoordinator=PetCoordinator(store:integrationPreferences,dailyBibleStore:integrationStore,
                                      defaults:integrationDefaults,currentDate:{ integrationDate })
previewCoordinator.previewBibleReader()
previewCoordinator.tick(at:100); previewCoordinator.tick(at:104); previewCoordinator.tick(at:105)
precondition(previewCoordinator.bubble.presentedBibleVerseID != nil)
while previewCoordinator.bubble.biblePageIndex<previewCoordinator.bubble.biblePageTexts.count-1 {
    previewCoordinator.bubble.changeBiblePage(by:1)
}
previewCoordinator.tick(at:105.1); previewCoordinator.toggleBubble()
precondition(previewCoordinator.dailyBible.today(at:integrationDate)?.isRead == false)
previewCoordinator.previewBibleReader()
previewCoordinator.readDailyBible()
precondition(previewCoordinator.bibleSession?.localDate == integrationDaily.today(at:integrationDate)?.localDate,
             "Read Today's Bible Verse replaces a preview with the actual daily assignment")
previewCoordinator.recoverCompanion()
precondition(previewCoordinator.bibleSession == nil && !previewCoordinator.controller.reading,"Recovery cancels the reader without completing it")
previewCoordinator.readDailyBible()
previewCoordinator.suspend()
precondition(previewCoordinator.bibleSession == nil && !previewCoordinator.controller.reading)
precondition(previewCoordinator.dailyBible.today(at:integrationDate)?.isRead == false)
previewCoordinator.stop()
print("PASS coordinator: menu closes during 7a, verse reopens at 7b, last-page completion, cancel/reopen, preview, and sleep")

// Readiness is reconciled by wall time even when drawing is hidden and paused.
let readinessFile=integrationOutput.appendingPathComponent("readiness.json")
let readinessStore=DailyBibleStore(file:readinessFile)
let pausedPreferences=PreferenceStore(file:integrationOutput.appendingPathComponent("paused.json"))
var paused=PetPreferences(); paused.isVisible=false; paused.isPaused=true
pausedPreferences.save(paused)
var readinessDate=integrationCalendar.date(bySettingHour:8,minute:0,second:0,of:integrationDate)!
var readinessDaily=DailyBible()
readinessDaily.reconcile(at:readinessDate,catalog:bibleCatalog) { 1 }
let originalAssignment=readinessDaily.today(at:readinessDate)!
readinessStore.save(readinessDaily)
let readinessCoordinator=PetCoordinator(store:pausedPreferences,dailyBibleStore:readinessStore,
                                        defaults:integrationDefaults,currentDate:{ readinessDate })
let readinessMenu=NSMenu()
readinessCoordinator.menuWillOpen(readinessMenu)
precondition(readinessMenu.items.contains { $0.title == "Read Today's Bible Verse" && $0.isEnabled },
             "The daily verse is available in the morning, including while hidden/paused")
func bubbleButtons(_ parent: NSView) -> [NSButton] {
    parent.subviews.flatMap { child in
        (child as? NSButton).map { [$0] } ?? bubbleButtons(child)
    }
}
readinessCoordinator.bubble.show()
let morningButtons=bubbleButtons(readinessCoordinator.bubble.panel.contentView!)
precondition(morningButtons.contains { $0.title == "Read Bible verse" })
precondition(!morningButtons.contains { ["Done","Close","See message"].contains($0.title) },
             "Main menu omits Done/Close and hides See message when no message exists")
readinessCoordinator.bubble.setMessagesAvailable(true)
precondition(bubbleButtons(readinessCoordinator.bubble.panel.contentView!).contains { $0.title == "See message" && $0.isEnabled })
readinessCoordinator.bubble.setMessagesAvailable(false)
precondition(!bubbleButtons(readinessCoordinator.bubble.panel.contentView!).contains { $0.title == "See message" })
precondition(readinessStore.load().today(at:readinessDate) == originalAssignment)
readinessCoordinator.menuDidClose(readinessMenu)
readinessDate=integrationDate
readinessCoordinator.menuWillOpen(readinessMenu)
precondition(readinessMenu.items.first { $0.title == "Read Today's Bible Verse" }?.isEnabled == true)
precondition(readinessStore.load().today(at:readinessDate) == originalAssignment,"The verse stays the same all day")
readinessCoordinator.menuDidClose(readinessMenu)
readinessDate=integrationCalendar.date(byAdding:.day,value:1,to:readinessDate)!
readinessCoordinator.readDailyBible()
precondition(readinessStore.load().today(at:readinessDate)?.verseID != originalAssignment.verseID,"A new local date receives a different verse")
readinessCoordinator.stop()
print("PASS daily verse is available all day and changes tomorrow; main menu hides unavailable messages and omits Done/Close")

// Startup checks never invoke real permission prompts during tests.
precondition(StartupPermissions.required.map(\.name) == ["Camera"],"Real photo capture needs camera access, without unrelated grants")
var allowedA=false, allowedB=false, requested: [String]=[], requestCallbacks: [()->Void]=[]
let requirements=[
    StartupPermission(name:"First",reason:"Test feature A",isGranted:{ allowedA },request:{ callback in requested.append("First"); requestCallbacks.append(callback) }),
    StartupPermission(name:"Second",reason:"Test feature B",isGranted:{ allowedB },request:{ callback in requested.append("Second"); requestCallbacks.append(callback) }),
    StartupPermission(name:"Already allowed",reason:"Test feature C",isGranted:{ true },request:{ _ in preconditionFailure("Granted permission must not prompt") })
]
let launchStore=PreferenceStore(file:integrationOutput.appendingPathComponent("launch.json"))
var launchPreferences=PetPreferences(); launchPreferences.isVisible=false; launchPreferences.isPaused=true; launchPreferences.clickThrough=true
launchStore.save(launchPreferences)
integrationDefaults.set(integrationDate.addingTimeInterval(3600),forKey:"sombrero.returnDeadline")
let launchCoordinator=PetCoordinator(store:launchStore,dailyBibleStore:integrationStore,
                                     defaults:integrationDefaults,currentDate:{ integrationDate })
let permissionGate=StartupPermissions(requirements:requirements,showsWindow:false)
var launches=0
permissionGate.recheck() // A recheck before begin must not consume the startup.
permissionGate.begin { launches+=1; launchCoordinator.launchFromTimeout() }
precondition(requested == ["First"] && launches == 0 && launchCoordinator.controller.state == .timeout)
requestCallbacks.removeFirst()()
precondition(requested == ["First","Second"],"Request every missing grant, even if an earlier request is denied")
requestCallbacks.removeFirst()()
precondition(launches == 0 && permissionGate.missing.count == 2,"Request completion is not authorization")
allowedA=true; permissionGate.recheck()
precondition(launches == 0 && launchCoordinator.controller.state == .timeout,"Do not animate with a missing required grant")
allowedB=true; permissionGate.recheck(); permissionGate.recheck()
precondition(launches == 1 && permissionGate.isFinished)
precondition([DuckState.peek,.windowPeek].contains(launchCoordinator.controller.state),"Launch must use an exit from timeout")
precondition(integrationDefaults.object(forKey:"sombrero.returnDeadline") == nil)
precondition(launchStore.load().isVisible && launchStore.load().isPaused,"Launching recalls the pet and retains Pause Motion")
let launchState=launchCoordinator.controller.state
let entryDuration=Double(assets.frameCounts[launchState]!)/Double(PetConstants.Animation.drawingFPS)
launchCoordinator.tick(at:100); launchCoordinator.tick(at:100+entryDuration+0.01)
precondition(![DuckState.peek,.windowPeek].contains(launchCoordinator.controller.state),"Startup entrance must complete even with motion paused")
let completedEntry=launchCoordinator.controller.generation
launchCoordinator.tick(at:130); launchCoordinator.tick(at:140)
precondition(launchCoordinator.controller.generation == completedEntry,"Pause Motion resumes after the entrance")
launchCoordinator.stop()

let noPermissionGate=StartupPermissions(requirements:[],showsWindow:false)
var immediateLaunches=0
noPermissionGate.begin { immediateLaunches+=1 }
noPermissionGate.begin { immediateLaunches+=1 }
precondition(immediateLaunches == 1,"No required grants means immediate startup without an unnecessary prompt")
allowedA=false; allowedB=false; requested=[]; requestCallbacks=[]
let canceledGate=StartupPermissions(requirements:requirements,showsWindow:false)
canceledGate.begin { preconditionFailure("Canceled startup must not launch") }
canceledGate.cancel(); requestCallbacks.removeFirst()()
precondition(requested == ["First"],"Cancel must stop pending authorization requests")
print("PASS startup: request all missing grants, verify actual status, launch once from timeout, retain pause, and cancel safely")

let pausedReader=PetCoordinator(store:launchStore,dailyBibleStore:integrationStore,
                                defaults:integrationDefaults,currentDate:{ integrationDate })
pausedReader.readDailyBible()
pausedReader.tick(at:100); pausedReader.tick(at:104); pausedReader.tick(at:105)
precondition(pausedReader.bubble.presentedBibleVerseID != nil,"Pause Motion must not block explicit reader entry")
let heldReaderGeneration=pausedReader.controller.generation
pausedReader.tick(at:115)
precondition(pausedReader.controller.generation == heldReaderGeneration,"Held reader pose stays paused")
pausedReader.toggleBubble(); pausedReader.tick(at:116); pausedReader.tick(at:120.2)
precondition(pausedReader.controller.state == .look,"Closing an explicit reader finishes its exit while idle motion is paused")
precondition(launchStore.load().isPaused)
pausedReader.stop()
print("PASS paused interaction: explicit reader can enter/exit, while its held pose remains still")

// A kept card belongs to its native window, not to the duck's active routine.
final class NoNetworkCredentials: MessageCredentialStorage {
    func read(account:String) throws -> String? { nil }
    func write(_ token:String,account:String) throws {}
    func remove(account:String) throws {}
}
let messageRoot=output.appendingPathComponent("kept-polaroid-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at:messageRoot) }
let messageStore=MessageStore(root:messageRoot)
let identity=ChatIdentity(deviceID:UUID().uuidString,peerID:UUID().uuidString,pairID:UUID().uuidString)
let messageConfiguration=MessageConfiguration(serverURL:URL(string:"https://fixture.invalid")!,identity:identity,credentialAccount:"fixture")
try messageStore.saveConfiguration(messageConfiguration)
var messageReplica=MessageReplica()
messageReplica.upsert(ChatMessage(id:UUID().uuidString,pairID:identity.pairID,senderID:identity.peerID,recipientID:identity.deviceID,
    clientRequestID:UUID().uuidString,body:RichMessageBody(text:"A little note to keep"),attachment:nil,createdAt:Date(),readAt:Date()))
try messageStore.save(messageReplica,configuration:messageConfiguration)
let messageService=MessageService(store:messageStore,credentials:NoNetworkCredentials())
let messagesCoordinator=MessageCoordinator(service:messageService)
var requestedMessages:[DuckRequest]=[], finishedMessages:[DuckRequest]=[]
messagesCoordinator.onRoutineRequested={ requestedMessages.append($0) }
messagesCoordinator.onRoutineEnded={ finishedMessages.append($0) }
func messageButtons(_ view:NSView)->[NSButton] {
    view.subviews.flatMap { child -> [NSButton] in (child as? NSButton).map { [$0] } ?? messageButtons(child) }
}
func visiblePhotoWindow(excluding other:NSWindow? = nil)->NSWindow {
    NSApp.windows.first { $0.isVisible && $0.title=="A photo for you" && $0 !== other }!
}
messagesCoordinator.showInbox(); messagesCoordinator.didEnter(.showingPhoto)
let keptWindow=visiblePhotoWindow()
messageButtons(keptWindow.contentView!).first { $0.title=="Keep" }!.performClick(nil)
precondition(finishedMessages==[.photoShow] && !messagesCoordinator.isInteracting && keptWindow.isVisible)
messagesCoordinator.closeWindows(); messagesCoordinator.suspend()
precondition(keptWindow.isVisible && finishedMessages==[.photoShow],"Routine changes/sleep must not close kept cards or finish twice")
messagesCoordinator.showInbox(); messagesCoordinator.didEnter(.showingPhoto)
let newWindow=visiblePhotoWindow(excluding:keptWindow)
precondition(messagesCoordinator.isInteracting && newWindow.isVisible && requestedMessages==[.photoShow,.photoShow])
keptWindow.close()
precondition(finishedMessages==[.photoShow] && messagesCoordinator.isInteracting,"Closing an old kept card must not end the new viewer's duck routine")
messageButtons(newWindow.contentView!).first { $0.title=="Keep" }!.performClick(nil)
precondition(finishedMessages==[.photoShow,.photoShow] && !messagesCoordinator.isInteracting)
messagesCoordinator.showComposer()
precondition(requestedMessages.last == .photoTake && newWindow.isVisible)
// Cancel before 6b, so this fixture never starts the real camera.
messagesCoordinator.closeWindows()
precondition(newWindow.isVisible && finishedMessages.last == .photoTake)
messagesCoordinator.stop()
precondition(!newWindow.isVisible,"App shutdown closes its independent windows")
print("PASS Polaroid coordinator: Keep releases duck, survives routine changes, allows another viewer/composer, and closing old cards cannot cancel new routines")

let previewService=MessageService(store:MessageStore(root:messageRoot.appendingPathComponent("receive-preview")),credentials:NoNetworkCredentials())
let previewMessages=MessageCoordinator(service:previewService)
previewMessages.receiveTestPhoto()
precondition(previewMessages.unreadCount==1 && previewMessages.hasMessages && previewService.messages.isEmpty)
previewMessages.showInbox(); previewMessages.didEnter(.showingPhoto)
let previewWindow=visiblePhotoWindow()
RunLoop.main.run(until:Date().addingTimeInterval(0.05))
precondition(previewMessages.unreadCount==0 && previewService.messages.isEmpty && previewService.outbox.isEmpty,"Fixture reads must never touch server history or send receipts")
func messageViews(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+messageViews($0) } }
precondition(messageViews(previewWindow.contentView!).compactMap { $0 as? NSTextView }.contains { $0.string.contains("Your test photo arrived") })
precondition(messageViews(previewWindow.contentView!).compactMap { $0 as? NSImageView }.contains { $0.image != nil },"Show a real bundled image in the test Polaroid")
previewMessages.stop()
print("PASS local receive preview: unread badge, bundled image and styled message, no connection needed, no server history or receipt changes")

}
try MainActor.assumeIsolated { try runDesktopSmoke() }
