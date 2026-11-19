import Foundation

public enum DuckState: Int, Codable, CaseIterable {
    case look = 1, alternateLook, sitDown, standUp, sitting
}

/// Decisions occur once per completed clip. Sit-down always enters sitting idle.
public struct DuckController {
    public private(set) var state: DuckState = .look
    public init() {}
    @discardableResult public mutating func complete(sample: () -> Int) -> DuckState {
        if state == .sitDown { state = .sitting; return state }
        let value = sample()
        precondition((0..<100).contains(value))
        if state == .sitting { state = value < 80 ? .sitting : .standUp }
        else { state = value < 40 ? .look : value < 80 ? .alternateLook : .sitDown }
        return state
    }
}

public struct SpriteManifest: Codable {
    public struct Frame: Codable {
        public let resource: String
        public let durationFrames: Int
    }
    public struct Clip: Codable {
        public let state: DuckState
        public let frames: [Frame]
    }
    public let schemaVersion: Int
    public let timelineFPS: Int
    public let drawingFPS: Int
    public let holdFrames: Int
    public let frameWidth: Int
    public let frameHeight: Int
    public let clips: [Clip]

    public var isValid: Bool {
        schemaVersion == 1 && timelineFPS == 24 && drawingFPS == 6 && holdFrames == 4 &&
        frameWidth == 320 && frameHeight == 320 && clips.count == 5 &&
        Set(clips.map(\.state)) == Set(DuckState.allCases) &&
        clips.allSatisfy { !$0.frames.isEmpty && $0.frames.count <= 100 && $0.frames.allSatisfy {
            $0.durationFrames == 4 && !$0.resource.contains("/") && !$0.resource.contains("..") && $0.resource.hasSuffix(".png")
        } }
    }
}

/// Character clock has no dependency on AppKit. Integer holds are measured against elapsed time.
public struct SpritePlayback {
    public private(set) var state: DuckState = .look
    public private(set) var frameIndex = 0
    public private(set) var elapsed: Double = 0
    private let counts: [DuckState: Int]
    public init(frameCounts: [DuckState: Int]) {
        precondition(DuckState.allCases.allSatisfy { (frameCounts[$0] ?? 0) > 0 })
        counts = frameCounts
    }
    public mutating func advance(by delta: Double, next: () -> DuckState) {
        guard delta.isFinite, delta > 0 else { return }
        elapsed += delta
        while elapsed >= Double(counts[state]!) / 6 {
            elapsed -= Double(counts[state]!) / 6
            state = next()
        }
        frameIndex = min(counts[state]! - 1, Int(floor(elapsed * 6)))
    }
}

/// Rebase on pause, hide, sleep, and resume; missed wall time is never caught up.
public struct DrawingClock {
    private var lastTime: Double?
    private var wasRunning = false
    public init() {}
    public mutating func sample(at now: Double, running: Bool) -> Double {
        guard now.isFinite else { return 0 }
        defer { lastTime = now; wasRunning = running }
        guard let previous = lastTime, now >= previous, running, wasRunning else { return 0 }
        return now - previous
    }
}
