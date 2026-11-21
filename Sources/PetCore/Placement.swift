import Foundation

public struct PetPoint: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct PetRect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isValid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
    public func intersects(_ other: PetRect) -> Bool {
        x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }
    public func contains(_ other: PetRect) -> Bool {
        other.x >= x && other.maxX <= maxX && other.y >= y && other.maxY <= maxY
    }
    public func offsetBy(x dx: Double, y dy: Double) -> PetRect {
        PetRect(x: x+dx, y: y+dy, width: width, height: height)
    }
    public func scaled(by scale: Double) -> PetRect {
        PetRect(x: x*scale, y: y*scale, width: width*scale, height: height*scale)
    }
    public var center: PetPoint { PetPoint(x: x + width / 2, y: y + height / 2) }
}

public struct PetDisplay: Equatable {
    public var id: String
    public var workArea: PetRect
    public init(id: String, workArea: PetRect) { self.id = id; self.workArea = workArea }
}

public struct SavedPlacement: Codable, Equatable {
    public var displayID: String
    public var normalizedX: Double
    public var normalizedY: Double
    public var usesVisibleBounds: Bool?
    public init(displayID: String, normalizedX: Double, normalizedY: Double, usesVisibleBounds: Bool? = nil) {
        self.usesVisibleBounds = usesVisibleBounds
        self.displayID = displayID; self.normalizedX = normalizedX; self.normalizedY = normalizedY
    }
}

/// All geometry is in macOS points, independent of Retina backing pixels.
public enum Placement {
    public static func clamp(_ origin: PetPoint, size: Double, to area: PetRect) -> PetPoint {
        let maxX = max(area.x, area.x + area.width - size)
        let maxY = max(area.y, area.y + area.height - size)
        let x = origin.x.isFinite ? origin.x : area.x
        let y = origin.y.isFinite ? origin.y : area.y
        return PetPoint(x: min(maxX, max(area.x, x)), y: min(maxY, max(area.y, y)))
    }

    public static func restore(_ saved: SavedPlacement?, size: Double, displays: [PetDisplay], fallbackID: String?) -> PetPoint? {
        guard let display = displays.first(where: { $0.id == saved?.displayID })
            ?? displays.first(where: { $0.id == fallbackID }) ?? displays.first else { return nil }
        let area = display.workArea
        let nx = finiteUnit(saved?.normalizedX ?? PetConstants.Geometry.initialNormalizedPosition.x)
        let ny = finiteUnit(saved?.normalizedY ?? PetConstants.Geometry.initialNormalizedPosition.y)
        return clamp(PetPoint(x: area.x + max(0, area.width - size) * nx,
                              y: area.y + max(0, area.height - size) * ny), size: size, to: area)
    }

    public static func save(origin: PetPoint, size: Double, display: PetDisplay) -> SavedPlacement {
        let point = clamp(origin, size: size, to: display.workArea)
        return SavedPlacement(displayID: display.id,
            normalizedX: finiteUnit((point.x - display.workArea.x) / max(1, display.workArea.width - size)),
            normalizedY: finiteUnit((point.y - display.workArea.y) / max(1, display.workArea.height - size)))
    }

    /// Keep the painted rectangle on screen; transparent canvas padding may extend outside it.
    public static func clamp(_ origin: PetPoint, visibleBounds bounds: PetRect, to area: PetRect) -> PetPoint {
        guard bounds.isValid, area.isValid else { return origin }
        let minX = area.x - bounds.x, minY = area.y - bounds.y
        let maxX = max(minX, area.maxX - bounds.maxX), maxY = max(minY, area.maxY - bounds.maxY)
        return PetPoint(x: min(maxX, max(minX, origin.x.isFinite ? origin.x : minX)),
                        y: min(maxY, max(minY, origin.y.isFinite ? origin.y : minY)))
    }
    public static func save(origin: PetPoint, visibleBounds bounds: PetRect, display: PetDisplay) -> SavedPlacement {
        let point = clamp(origin, visibleBounds: bounds, to: display.workArea)
        return SavedPlacement(displayID: display.id,
            normalizedX: finiteUnit((point.x+bounds.x-display.workArea.x) / max(1,display.workArea.width-bounds.width)),
            normalizedY: finiteUnit((point.y+bounds.y-display.workArea.y) / max(1,display.workArea.height-bounds.height)), usesVisibleBounds: true)
    }
    public static func restore(_ saved: SavedPlacement?, viewportSize: Double, visibleBounds bounds: PetRect,
                               displays: [PetDisplay], fallbackID: String?) -> PetPoint? {
        guard let display = displays.first(where: { $0.id == saved?.displayID })
            ?? displays.first(where: { $0.id == fallbackID }) ?? displays.first else { return nil }
        if let saved, saved.usesVisibleBounds != true {
            guard let old = restore(saved, size: viewportSize, displays: displays, fallbackID: fallbackID) else { return nil }
            return clamp(old, visibleBounds: bounds, to: display.workArea)
        }
        let area = display.workArea
        let initial = PetConstants.Geometry.initialNormalizedPosition
        return clamp(PetPoint(x: area.x-bounds.x+max(0,area.width-bounds.width)*finiteUnit(saved?.normalizedX ?? initial.x),
                              y: area.y-bounds.y+max(0,area.height-bounds.height)*finiteUnit(saved?.normalizedY ?? initial.y)),
                     visibleBounds: bounds, to: area)
    }

    private static func finiteUnit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.5 }
}
