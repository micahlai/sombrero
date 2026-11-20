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
