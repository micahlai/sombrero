// Component render checks: no interaction with the user's other windows or services.
import AppKit
import PetAssets
import PetCore

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let assets = SpriteLibrary()
precondition(assets.failure == nil, "Packaged assets must load")
let bubble = SpeechBubble(images: assets.speechFrames)
let output = URL(fileURLWithPath: ".build/ui-smoke")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, mode) in [("menu", SpeechBubble.Mode.menu), ("away", .away), ("photo", .photo), ("camera", .camera), ("bible", .bible)] {
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
precondition(abs(bubble.panel.frame.width - 355.0/3) < 1)
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
print("PASS one-third size, fixed ink, no heading, and non-overlapping placement")

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
