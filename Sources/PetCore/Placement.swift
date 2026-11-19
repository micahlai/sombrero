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
    public init(displayID: String, normalizedX: Double, normalizedY: Double) {
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
        let nx = finiteUnit(saved?.normalizedX ?? 0.85)
        let ny = finiteUnit(saved?.normalizedY ?? 0.12)
        return clamp(PetPoint(x: area.x + max(0, area.width - size) * nx,
                              y: area.y + max(0, area.height - size) * ny), size: size, to: area)
    }

    public static func save(origin: PetPoint, size: Double, display: PetDisplay) -> SavedPlacement {
        let point = clamp(origin, size: size, to: display.workArea)
        return SavedPlacement(displayID: display.id,
            normalizedX: finiteUnit((point.x - display.workArea.x) / max(1, display.workArea.width - size)),
            normalizedY: finiteUnit((point.y - display.workArea.y) / max(1, display.workArea.height - size)))
    }

    private static func finiteUnit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.5 }
}
