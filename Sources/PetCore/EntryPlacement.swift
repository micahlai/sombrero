import Foundation

public enum ScreenEdge: Equatable {
    case left, right
    /// The authored 4b clip enters from the left; mirror it for a right edge.
    public var flipsPeekAnimation: Bool { self == .right }
    /// A window side opens outward; its facing is opposite the same screen edge.
    public var flipsWindowPeekAnimation: Bool { self == .left }
}
/// Calibrated position of the vertical cut in the unmirrored 4b artwork.
public struct PeekArtwork {
    public let viewportSize: Double
    public let cutX: Double
    public init(viewportSize: Double, cutX: Double) { self.viewportSize = viewportSize; self.cutX = cutX }
    public func boundaryX(flipped: Bool) -> Double { flipped ? viewportSize-cutX : cutX }
}

public struct ScreenEntryPlacement {
    public let origin: PetPoint
    public let edge: ScreenEdge
    public var flipsAnimation: Bool { edge.flipsPeekAnimation }
    public static func choose(screen: PetRect, referenceBounds bounds: PetRect, artwork: PeekArtwork, sideSample: Double, heightSample: Double) -> ScreenEntryPlacement {
        precondition((0..<1).contains(sideSample) && (0...1).contains(heightSample))
        let edge: ScreenEdge = sideSample < PetConstants.ScreenEntry.leftChance ? .left : .right
        let inset = PetConstants.ScreenEntry.edgeOffset
        let margin = PetConstants.ScreenEntry.verticalMargin
        let bottom = screen.y+margin-bounds.y
        let top = max(bottom,screen.maxY-margin-bounds.maxY)
        return ScreenEntryPlacement(origin: PetPoint(
            x: (edge == .left ? screen.x+inset : screen.maxX-inset)-artwork.boundaryX(flipped: edge.flipsPeekAnimation),
            y: bottom+(top-bottom)*heightSample), edge: edge)
    }
}

public struct WindowAttachment: Equatable {
    public let windowID: UInt32
    public let horizontalFraction: Double
    public let ownerPID: Int32
    public init(windowID: UInt32, horizontalFraction: Double, ownerPID: Int32 = 0) {
        self.windowID = windowID; self.horizontalFraction = horizontalFraction; self.ownerPID = ownerPID
    }
}
/// Attachment is established only on an explicit 4c entry. Updating geometry
/// cannot select a new window, so a user drag cannot accidentally reattach.
public struct PetAttachment {
    public private(set) var window: WindowAttachment?
    public private(set) var screenEdge: ScreenEdge?
    public private(set) var side: WindowSideAttachment?
    public init() {}
    public mutating func enterWindow(_ target: WindowAttachment) { window = target; screenEdge = nil; side = nil }
    public mutating func enterScreen(_ edge: ScreenEdge) { window = nil; screenEdge = edge; side = nil }
    public mutating func enterSide(_ target: WindowSideAttachment) { window=nil; screenEdge=nil; side=target }
    public mutating func didEnterState(_ state: DuckState) { if state != .peek { side=nil } }
    public mutating func detach() { window = nil; screenEdge = nil; side = nil }
    public mutating func drag() { detach() }
}

public enum RecallEntry: String, Codable { case screenEdge = "screen-edge", windowTop = "window-top", windowSide = "window-side" }
public struct WindowSideAttachment: Equatable {
    public let windowID: UInt32
    public let ownerPID: Int32
    public let edge: ScreenEdge
    public let verticalFraction: Double
    public var flipsAnimation: Bool { edge.flipsWindowPeekAnimation }
    public init(windowID: UInt32, ownerPID: Int32, edge: ScreenEdge, verticalFraction: Double) {
        self.windowID = windowID; self.ownerPID = ownerPID; self.edge = edge; self.verticalFraction = verticalFraction
    }
}
public enum WindowSidePlacement {
    public static func horizontalOrigin(window: PetRect, artwork: PeekArtwork, edge: ScreenEdge) -> Double {
        let inset = PetConstants.ScreenEntry.edgeOffset
        let boundary = edge == .left ? window.x-inset : window.maxX+inset
        return boundary-artwork.boundaryX(flipped: edge.flipsWindowPeekAnimation)
    }
    public struct Interval { public let lower: Double; public let upper: Double }
    public static func intervals(window: PetRect, area: PetRect, bounds: PetRect, artwork: PeekArtwork, edge: ScreenEdge, occluders: [PetRect] = []) -> [Interval] {
        guard window.isValid, area.isValid, bounds.isValid else { return [] }
        let x = horizontalOrigin(window: window, artwork: artwork, edge: edge)
        guard x+bounds.x >= area.x, x+bounds.maxX <= area.maxX else { return [] }
        let low = max(window.y,area.y)-bounds.y, high = min(window.maxY,area.maxY)-bounds.maxY
        guard high >= low else { return [] }
        let strip = PetConstants.WindowEntry.visibleTopStripHeight
        let bandX = edge == .left ? x+bounds.x : window.maxX-strip
        let bandRight = edge == .left ? window.x+strip : x+bounds.maxX
        var ranges = [Interval(lower: low, upper: high)]
        for blocker in occluders where blocker.x < bandRight && blocker.maxX > bandX {
            let a = blocker.y-bounds.maxY, b = blocker.maxY-bounds.y
            ranges = ranges.flatMap { range -> [Interval] in
                if b <= range.lower || a >= range.upper { return [range] }
                var next: [Interval] = []
                if a > range.lower { next.append(Interval(lower: range.lower, upper: a)) }
                if b < range.upper { next.append(Interval(lower: b, upper: range.upper)) }
                return next
            }
        }
        return ranges
    }
    public static func origin(window: PetRect, area: PetRect, bounds: PetRect, artwork: PeekArtwork, edge: ScreenEdge, sample: Double, occluders: [PetRect] = []) -> PetPoint? {
        guard sample.isFinite, (0...1).contains(sample) else { return nil }
        let ranges = intervals(window: window, area: area, bounds: bounds, artwork: artwork, edge: edge, occluders: occluders)
        guard let first = ranges.first else { return nil }
        let total = ranges.reduce(0) { $0+($1.upper-$1.lower) }
        var distance = sample*total, y = ranges.last?.upper ?? first.lower
        for range in ranges {
            let length = range.upper-range.lower
            if distance <= length { y = range.lower+distance; break }
            distance -= length
        }
        return PetPoint(x: horizontalOrigin(window: window, artwork: artwork, edge: edge), y: y)
    }
}
