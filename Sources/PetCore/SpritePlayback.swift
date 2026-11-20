import Foundation

public enum DuckState: String, Codable, CaseIterable {
    case look = "1a", alternateLook = "1b", wave = "1c", standingPet = "1d"
    case sitDown = "2a", standUp = "2b", sitting = "3a", sittingLook = "3b", sittingPet = "3c"
    case goodbye = "4a", peek = "4b", windowPeek = "4c", timeout
    case grabPhoto = "5a", showPhoto = "5b", showingPhoto = "5c", putPhotoAway = "5d"
    case grabCamera = "6a", cameraIdle = "6b", deliverPhoto = "6c"
    case grabBible = "7a", bibleIdle = "7b", stowBible = "7c"

    public var title: String {
        switch self {
        case .look: return "Standing idle"
        case .alternateLook: return "Standing look"
        case .wave: return "Standing wave"
        case .standingPet: return "Standing pet"
        case .sitDown: return "Sit down"
        case .standUp: return "Stand up"
        case .sitting: return "Sitting idle"
        case .sittingLook: return "Sitting look"
        case .sittingPet: return "Sitting pet"
        case .goodbye: return "Goodbye"
        case .peek: return "Peek in"
        case .windowPeek: return "Window peek in"
        case .timeout: return "Hidden timeout"
        case .grabPhoto: return "Grab photo"
        case .showPhoto: return "Show photo"
        case .showingPhoto: return "Showing photo"
        case .putPhotoAway: return "Put photo away"
        case .grabCamera: return "Grab camera"
        case .cameraIdle: return "Camera idle"
        case .deliverPhoto: return "Take photo and deliver"
        case .grabBible: return "Pull out Bible"
        case .bibleIdle: return "Bible idle"
        case .stowBible: return "Stow Bible"
        }
    }
}

public enum DuckRequest: String, Equatable { case photoShow, photoTake, bibleRead }

/// Native implementation of docs/sombrero-v1-state-graph.json. Requests survive
/// intermediate gateways; only explicit entry into a routine consumes a request.
public struct DuckController {
    public private(set) var state: DuckState = .look
    public private(set) var generation = 0
    public private(set) var pending: [DuckRequest] = []
    public private(set) var active: DuckRequest?
    public private(set) var pet = false
    public private(set) var goodbye = false
    public var showPhoto = false
    public var takingPhoto = false
    public var reading = false
    private var hasEvent: Bool { goodbye || !pending.isEmpty }
    public init() {}

    public mutating func setPet(_ value: Bool) { pet = value && !goodbye; resolveImmediate() }
    public mutating func request(_ request: DuckRequest) {
        guard active != request, !pending.contains(request), pending.count < 8 else { return }
        pending.append(request)
        switch request {
        case .photoShow: showPhoto = true
        case .photoTake: takingPhoto = true
        case .bibleRead: reading = true
        }
        resolveImmediate()
    }
    public mutating func dismiss() {
        pending.removeAll(); goodbye = true; pet = false
        showPhoto = false; takingPhoto = false; reading = false
        resolveImmediate()
    }
    public mutating func finishRoutine() {
        showPhoto = false; takingPhoto = false; reading = false
    }
    public mutating func recall(windowAvailable: Bool = false, sample: () -> Double = { Double.random(in: 0..<1) }) {
        guard state == .timeout else { return }
        goodbye = false; pet = false
        if windowAvailable {
            let value = sample()
            precondition(value.isFinite && value >= 0 && value < 1)
            enter(value < 0.2 ? .peek : .windowPeek)
        } else { enter(.peek) }
    }
    /// Explicit preview/recovery, never used as an automatic transition.
    public mutating func reset(to state: DuckState = .look) {
        let previous = generation
        self = DuckController(); generation = previous; enter(state)
        showPhoto = [.grabPhoto, .showPhoto, .showingPhoto].contains(state)
        takingPhoto = [.grabCamera, .cameraIdle].contains(state)
        reading = [.grabBible, .bibleIdle].contains(state)
    }
    private mutating func enter(_ next: DuckState) {
        if [.putPhotoAway, .deliverPhoto, .stowBible].contains(state), next == .look { active = nil }
        state = next; generation += 1
        if next == .timeout {
            pet = false; goodbye = false; pending.removeAll(); active = nil; finishRoutine()
        }
    }
    private mutating func resolveImmediate() {
        // All immediate paths terminate; bound hops as a guard against future cycles.
        for _ in 0..<DuckState.allCases.count {
            switch state {
            case .look:
                if goodbye { enter(.goodbye) }
                else if let request = pending.first {
                    pending.removeFirst(); active = request
                    enter(request == .photoShow ? .grabPhoto : request == .photoTake ? .grabCamera : .grabBible)
                } else if pet { enter(.standingPet) } else { return }
            case .alternateLook:
                if goodbye { enter(.goodbye) } else if pet { enter(.standingPet) } else { return }
            case .wave:
                if pet { enter(.standingPet) } else { return }
            case .sitting, .sittingLook:
                if hasEvent { enter(.standUp) } else if pet { enter(.sittingPet) } else { return }
            case .standingPet:
                if hasEvent { enter(.look) } else if !pet { enter(.wave) } else { return }
            case .sittingPet:
                if hasEvent || !pet { enter(.sitting) } else { return }
            default: return
            }
        }
    }
    public static func defaults(from state: DuckState) -> [(DuckState, Double)] {
        switch state {
        case .look: return [(.look, 0.975), (.alternateLook, 0.02), (.wave, 0.02), (.sitDown, 0.005)]
        case .alternateLook: return [(.look, 0.8), (.wave, 0.2)]
        case .wave, .standUp, .putPhotoAway, .deliverPhoto, .stowBible: return [(.look, 1)]
        case .sitDown: return [(.sitting, 1)]
        case .sitting: return [(.sitting, 0.985), (.sittingLook, 0.01), (.standUp, 0.005)]
        case .sittingLook: return [(.sittingLook, 0.1), (.sitting, 0.9)]
        case .goodbye: return [(.timeout, 1)]
        case .peek: return [(.alternateLook, 1)]
        case .windowPeek: return [(.sitting, 1)]
        case .grabPhoto: return [(.showPhoto, 1)]
        case .showPhoto: return [(.showingPhoto, 1)]
        case .grabCamera: return [(.cameraIdle, 1)]
        case .grabBible: return [(.bibleIdle, 1)]
        default: return []
        }
    }
    @discardableResult public mutating func complete(token: Int? = nil, sample: () -> Double) -> DuckState {
        guard state != .timeout, token == nil || token == generation else { return state }
        let before = generation
        resolveImmediate()
        guard before == generation else { return state }
        let next: DuckState
        switch state {
        case .alternateLook where hasEvent: next = .look
        case .standingPet: next = .standingPet
        case .sittingPet: next = .sittingPet
        case .showingPhoto: next = showPhoto ? .showingPhoto : .putPhotoAway
        case .cameraIdle: next = takingPhoto ? .cameraIdle : .deliverPhoto
        case .bibleIdle: next = reading ? .bibleIdle : .stowBible
        default:
            let edges = Self.defaults(from: state)
            guard let first = edges.first else { return state }
            if edges.count == 1 { next = first.0 }
            else {
                let value = sample()
                precondition(value.isFinite && value >= 0 && value < 1)
                var remaining = value * edges.reduce(0) { $0 + $1.1 }
                var chosen = edges.last!.0
                for edge in edges { remaining -= edge.1; if remaining < 0 { chosen = edge.0; break } }
                next = chosen
            }
        }
        enter(next); resolveImmediate(); return state
    }
}

public struct SpriteManifest: Codable {
    public struct Frame: Codable { public let resource: String }
    public struct Clip: Codable {
        public let state: DuckState
        public let frames: [Frame]
        public let scale: Double
        public let offsetX: Double
        public let offsetY: Double
    }
    public let schemaVersion: Int
    public let drawingFPS: Int
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let clips: [Clip]
    public let speechFrames: [Frame]
    public var isValid: Bool {
        let safe: (Frame) -> Bool = { !$0.resource.contains("..") && !$0.resource.hasPrefix("/") && $0.resource.hasSuffix(".png") }
        return schemaVersion == 2 && drawingFPS == 6 && canvasWidth > 0 && canvasHeight > 0 &&
            Set(clips.map(\.state)) == Set(DuckState.allCases.filter { $0 != .timeout }) && clips.count == DuckState.allCases.count - 1 &&
            clips.allSatisfy { $0.scale.isFinite && $0.scale > 0 && $0.offsetX.isFinite && $0.offsetY.isFinite &&
                $0.frames.count <= 500 && $0.frames.allSatisfy(safe) } && speechFrames.count == 5 && speechFrames.allSatisfy(safe)
    }
}

public struct SpritePlayback {
    public private(set) var state: DuckState = .look
    public private(set) var frameIndex = 0
    public private(set) var elapsed: Double = 0
    private var generation = 0
    private let counts: [DuckState: Int]
    public init(frameCounts: [DuckState: Int]) { counts = frameCounts }
    public mutating func synchronize(with controller: DuckController) {
        if state != controller.state || generation != controller.generation {
            state = controller.state; generation = controller.generation; elapsed = 0; frameIndex = 0
        }
    }
    public mutating func advance(by delta: Double, controller: inout DuckController, sample: () -> Double) {
        synchronize(with: controller)
        guard state != .timeout, delta.isFinite, delta > 0 else { return }
        elapsed += delta
        // Bounded work after an unexpectedly delayed timer; no unbounded catch-up loop.
        for _ in 0..<120 {
            let duration = Double(counts[state] ?? 10) / 6
            guard elapsed + 1e-9 >= duration else { break }
            let remainder = max(0, elapsed - duration)
            controller.complete(token: generation, sample: sample)
            synchronize(with: controller); elapsed = remainder
            if state == .timeout { elapsed = 0; break }
        }
        frameIndex = min((counts[state] ?? 10) - 1, Int(elapsed * 6 + 1e-9))
    }
}

/// Five authored growth frames; the last drawing holds until a reversed collapse.
public struct SpeechBubblePlayback {
    public private(set) var frameIndex = 0
    public private(set) var isVisible = false
    public private(set) var isExpanded = false
    public private(set) var wantsOpen = false
    private var elapsed: Double = 0
    public init() {}
    public mutating func open() {
        if !isVisible { frameIndex = 0 }
        isVisible = true; wantsOpen = true; isExpanded = false; elapsed = 0
    }
    public mutating func close() { wantsOpen = false; isExpanded = false; elapsed = 0 }
    public mutating func advance(by delta: Double) {
        guard isVisible, !isExpanded, delta.isFinite, delta > 0 else { return }
        elapsed += delta
        while elapsed + 1e-9 >= 1.0 / 6 {
            elapsed = max(0, elapsed - 1.0 / 6)
            if wantsOpen {
                if frameIndex == 4 { isExpanded = true; break }
                frameIndex += 1
            } else {
                if frameIndex == 0 { isVisible = false; break }
                frameIndex -= 1
            }
        }
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
