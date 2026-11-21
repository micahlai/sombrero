import AppKit
import PetCore

/// Geometry-only WindowServer inventory. Never reads titles or captures images.
/// Only document windows (layer 0) obstruct candidates: floating overlays can have
/// full-screen geometry and alpha=1 even when their pixels are transparent.
final class WindowTracker {
    struct Target { let attachment: WindowAttachment; let origin: NSPoint }
    struct SideTarget { let attachment: WindowSideAttachment; let origin: NSPoint }
    private struct Window { let id: UInt32; let ownerPID: Int32; let frame: PetRect; let layer: Int }
    struct Display { let frame: NSRect; let visibleFrame: NSRect }
    private let displays: () -> [Display]
    private let readWindowInfo: () -> [[String: Any]]?
    private let ownPID: Int32
    init(displays: @escaping () -> [Display] = { NSScreen.screens.map { Display(frame: $0.frame, visibleFrame: $0.visibleFrame) } },
         readWindowInfo: @escaping () -> [[String: Any]]? = {
             CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
         }, ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.displays = displays; self.readWindowInfo = readWindowInfo; self.ownPID = ownPID
    }
    private var lastSample = -Double.infinity
    private var cached: [Window] = []

    func targets(viewportSize: Double, visibleBounds: PetRect, baselineY: Double? = nil, force: Bool = false) -> [Target] {
        var occluders: [PetRect] = [], result: [Target] = []
        for window in windows(force: force) {
            defer { if window.layer == 0 { occluders.append(window.frame) } }
            guard window.layer == 0, window.frame.width >= PetConstants.WindowEntry.minimumWindowWidth,
                  window.frame.height >= PetConstants.WindowEntry.minimumWindowHeight else { continue }
            for fraction in PetConstants.WindowEntry.candidateAnchorFractions {
                guard let point = origin(window: window, fraction: fraction, viewportSize: viewportSize, visibleBounds: visibleBounds, baselineY: baselineY),
                      WindowPeekPlacement.isUnobstructed(window: window.frame, origin: point, visibleBounds: visibleBounds, occluders: occluders) else { continue }
                result.append(Target(attachment: WindowAttachment(windowID: window.id, horizontalFraction: fraction, ownerPID: window.ownerPID), origin: NSPoint(x: point.x, y: point.y)))
                break
            }
        }
        return result
    }
    func origin(for attachment: WindowAttachment, viewportSize: Double, visibleBounds: PetRect, baselineY: Double? = nil, force: Bool = false) -> NSPoint? {
        guard let window = windows(force: force).first(where: { $0.id == attachment.windowID && $0.ownerPID == attachment.ownerPID }),
              let point = origin(window: window, fraction: attachment.horizontalFraction, viewportSize: viewportSize, visibleBounds: visibleBounds, baselineY: baselineY) else { return nil }
        return NSPoint(x: point.x, y: point.y)
    }
    func sideTargets(visibleBounds: PetRect, artwork: PeekArtwork, force: Bool = false) -> [SideTarget] {
        var blockers: [PetRect] = [], result: [SideTarget] = []
        for window in windows(force: force) {
            defer { if window.layer == 0 { blockers.append(window.frame) } }
            guard window.layer == 0, window.frame.width >= PetConstants.WindowEntry.minimumWindowWidth,
                  window.frame.height >= PetConstants.WindowEntry.minimumWindowHeight else { continue }
            for edge in [ScreenEdge.left, .right] {
                let edgeX = edge == .left ? window.frame.x-1 : window.frame.maxX+1
                guard let screen = displays().first(where: { $0.frame.contains(NSPoint(x: edgeX, y: window.frame.center.y)) }) else { continue }
                let rect = screen.visibleFrame
                let area = PetRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
                guard let point = WindowSidePlacement.origin(window: window.frame, area: area, bounds: visibleBounds, artwork: artwork,
                      edge: edge, sample: Double.random(in: 0..<1), occluders: blockers) else { continue }
                let fraction = (point.y+visibleBounds.y-window.frame.y)/max(1,window.frame.height-visibleBounds.height)
                result.append(SideTarget(attachment: WindowSideAttachment(windowID: window.id, ownerPID: window.ownerPID, edge: edge, verticalFraction: fraction), origin: NSPoint(x: point.x,y: point.y)))
            }
        }
        return result
    }
    func origin(for attachment: WindowSideAttachment, visibleBounds bounds: PetRect, artwork: PeekArtwork, force: Bool = false) -> NSPoint? {
        guard let window = windows(force: force).first(where: { $0.id == attachment.windowID && $0.ownerPID == attachment.ownerPID }) else { return nil }
        let x = WindowSidePlacement.horizontalOrigin(window: window.frame, artwork: artwork, edge: attachment.edge)
        let y = window.frame.y+max(0,window.frame.height-bounds.height)*attachment.verticalFraction-bounds.y
        let painted = bounds.offsetBy(x:x,y:y)
        guard displays().contains(where: { $0.visibleFrame.contains(NSRect(x:painted.x,y:painted.y,width:painted.width,height:painted.height)) }) else { return nil }
        return NSPoint(x:x,y:y)
    }
    private func origin(window: Window, fraction: Double, viewportSize: Double, visibleBounds: PetRect, baselineY: Double?) -> PetPoint? {
        let anchor = NSPoint(x: window.frame.x+window.frame.width*fraction, y: window.frame.maxY-1)
        guard let screen = displays().first(where: { $0.frame.contains(anchor) }) else { return nil }
        let area = screen.visibleFrame
        return WindowPeekPlacement.origin(window: window.frame, workArea: PetRect(x: area.minX, y: area.minY, width: area.width, height: area.height),
            viewportSize: viewportSize, horizontalFraction: fraction, visibleBounds: visibleBounds, baselineY: baselineY)
    }
    private func windows(force: Bool) -> [Window] {
        let now = ProcessInfo.processInfo.systemUptime
        if !force, now-lastSample < PetConstants.WindowEntry.geometryPollInterval { return cached }
        lastSample = now; cached = []
        guard let primary = displays().first, let list = readWindowInfo() else { return [] }
        for info in list {
            guard let id = info[kCGWindowNumber as String] as? NSNumber,
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer >= 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) >= PetConstants.WindowEntry.minimumWindowAlpha,
                  let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { continue }
            let bounds = PetRect(x: rect.minX, y: primary.frame.maxY-rect.maxY, width: rect.width, height: rect.height)
            guard bounds.isValid else { continue }
            cached.append(Window(id: id.uint32Value, ownerPID: pid.int32Value, frame: bounds, layer: layer))
        }
        return cached
    }
}
