import Foundation

public enum PetActivity: String, Codable { case idle, petting }

/// Pure behavior: artwork, window APIs, timers, and future networking stay outside.
public struct PetBehavior {
    public private(set) var activity: PetActivity = .idle
    public private(set) var isVisible = true
    public var isPaused = false
    public private(set) var elapsed: Double = 0
    private var petTimeRemaining: Double = 0

    public init() {}
    public mutating func show() { isVisible = true; resetToIdle() }
    public mutating func hide() { isVisible = false; resetToIdle() }
    public mutating func resetToIdle() { activity = .idle; elapsed = 0; petTimeRemaining = 0 }
    public mutating func pet() {
        guard isVisible else { return }
        activity = .petting; elapsed = 0; petTimeRemaining = PetConstants.Animation.legacyPetDuration
    }
    public mutating func advance(by delta: Double) {
        guard isVisible, !isPaused, delta.isFinite, delta > 0 else { return }
        elapsed += delta
        if activity == .petting {
            petTimeRemaining -= delta
            if petTimeRemaining <= 0 { resetToIdle() }
        }
    }
}

public struct PetPreferences: Codable, Equatable {
    public var schemaVersion = 1
    public var isVisible = true
    public var alwaysOnTop = true
    public var allSpaces = true
    public var clickThrough = false
    public var isPaused = false
    public var size: Double = PetConstants.Size.defaultPet
    public var placement: SavedPlacement?
    public init() {}
    public func validated() -> PetPreferences {
        var copy = self
        copy.schemaVersion = 1
        copy.size = size.isFinite ? min(PetConstants.Size.maximumPet, max(PetConstants.Size.minimumPet, size)) : PetConstants.Size.defaultPet
        return copy
    }
}
