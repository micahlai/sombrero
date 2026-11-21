import XCTest
import PetCore
import PetAssets

final class SpriteTests: XCTestCase {
    func testDefaultEdgesMatchAuthoredGraphAndNormalizeWeights() throws {
        let graph = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "docs/sombrero-v1-state-graph.json"))) as! [String: Any]
        let edges = graph["transitions"] as! [[String: Any]]
        for state in DuckState.allCases {
            let expected = edges.filter { $0["from"] as? String == state.rawValue && $0["kind"] as? String == "default" }
            let actual = DuckController.defaults(from: state)
            XCTAssertEqual(actual.map { $0.0.rawValue }, expected.map { $0["to"] as! String })
            XCTAssertEqual(actual.map { $0.1 }, expected.map { ($0["weight"] as! NSNumber).doubleValue })
            let total = actual.reduce(0) { $0 + $1.1 }
            var lower: Double = 0
            for edge in actual {
                var controller = DuckController(); controller.reset(to: state)
                let midpoint = (lower + edge.1 / 2) / total
                XCTAssertEqual(controller.complete { midpoint }, edge.0)
                lower += edge.1
            }
        }
    }
    func testRequestSurvivesSittingPetAndSkipsGatewaysWithoutRandomRolls() {
        var controller = DuckController(); controller.reset(to: .sitting)
        controller.setPet(true); XCTAssertEqual(controller.state, .sittingPet)
        controller.request(.photoShow); XCTAssertEqual(controller.state, .sittingPet)
        XCTAssertEqual(controller.pending, [.photoShow])
        let noRandom = { XCTFail("Conditional or deterministic transition consumed randomness"); return 0.0 }
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .standUp)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .grabPhoto)
        XCTAssertEqual(controller.active, .photoShow); XCTAssertTrue(controller.pending.isEmpty)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .showPhoto)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .showingPhoto)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .showingPhoto)
        controller.finishRoutine(); controller.setPet(false)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .putPhotoAway)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .look); XCTAssertNil(controller.active)
    }
    func testPetReleaseAndEventPriorityAndPurpleBoundaries() {
        let noRandom = { XCTFail("Unexpected random roll"); return 0.0 }
        for origin in [DuckState.look, .alternateLook, .wave] {
            var controller = DuckController(); controller.reset(to: origin)
            controller.setPet(true); XCTAssertEqual(controller.state, .standingPet)
            let stale = controller.generation
            controller.setPet(false); XCTAssertEqual(controller.state, .standingPet)
            controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .wave)
            controller.complete(token: stale, sample: noRandom); XCTAssertEqual(controller.state, .wave)
        }
        for origin in [DuckState.sitting, .sittingLook] {
            var controller = DuckController(); controller.reset(to: origin)
            controller.request(.bibleRead); XCTAssertEqual(controller.state, .standUp)
            controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .grabBible)
        }
        var controller = DuckController(); controller.reset(to: .alternateLook)
        controller.request(.photoTake); XCTAssertEqual(controller.state, .alternateLook)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .grabCamera)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .cameraIdle)
        controller.takingPhoto = false; XCTAssertEqual(controller.state, .cameraIdle)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .deliverPhoto)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .look)
        controller.request(.bibleRead); controller.complete(sample: noRandom)
        XCTAssertEqual(controller.state, .bibleIdle)
        controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .bibleIdle)
        controller.finishRoutine(); controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .stowBible)
    }
    func testGoodbyeReturnsFromSittingAndActiveRoutineAndRecallUsesPeek() {
        let noRandom = { XCTFail("Unexpected random roll"); return 0.0 }
        for origin in [DuckState.sittingPet, .cameraIdle, .bibleIdle, .showingPhoto] {
            var controller = DuckController(); controller.reset(to: origin); controller.dismiss()
            for _ in 0..<8 where controller.state != .timeout { controller.complete(sample: noRandom) }
            XCTAssertEqual(controller.state, .timeout)
            controller.recall(); XCTAssertEqual(controller.state, .peek)
            controller.complete(sample: noRandom); XCTAssertEqual(controller.state, .alternateLook)
        }
    }
    func testWindowRecallWeightsAndUnavailableDeterminism() {
        for (value, expected) in [(0.0, DuckState.peek), (0.199999, .peek), (0.2, .windowPeek), (0.999999, .windowPeek)] {
            var controller = DuckController(); controller.reset(to: .timeout)
            var rolls = 0
            controller.recall(windowAvailable: true) { rolls += 1; return value }
            XCTAssertEqual(controller.state, expected); XCTAssertEqual(rolls, 1)
            controller.complete { XCTFail("Peek exit consumed randomness"); return 0 }
            XCTAssertEqual(controller.state, expected == .windowPeek ? .sitting : .alternateLook)
        }
        var controller = DuckController(); controller.reset(to: .timeout)
        controller.recall(windowAvailable: false) { XCTFail("Unavailable window consumed RNG"); return 0 }
        XCTAssertEqual(controller.state, .peek)
    }
    func testFocusedWindowClearanceAcrossDisplaysAndSizes() {
        let area = PetRect(x: -1440, y: 40, width: 1440, height: 860)
        let window = PetRect(x: -1300, y: 120, width: 800, height: 500)
        let point = WindowPeekPlacement.origin(window: window, workArea: area, viewportSize: 300)
        XCTAssertNotNil(point)
        XCTAssertEqual(point!.y + 300 * 0.26, 620, accuracy: 0.001)
        XCTAssertNil(WindowPeekPlacement.origin(window: window, workArea: area, viewportSize: 300, isFullScreen: true))
        XCTAssertNil(WindowPeekPlacement.origin(window: PetRect(x: -1440, y: 40, width: 1440, height: 860), workArea: area, viewportSize: 300))
        let closeTop = PetRect(x: -1300, y: 120, width: 800, height: 700)
        XCTAssertNil(WindowPeekPlacement.origin(window: closeTop, workArea: area, viewportSize: 100))
        XCTAssertNotNil(WindowPeekPlacement.origin(window: closeTop, workArea: area, viewportSize: 100, minimumClearance: 0))
        XCTAssertNil(WindowPeekPlacement.origin(window: closeTop, workArea: area, viewportSize: 300))
        XCTAssertNil(WindowPeekPlacement.origin(window: PetRect(x: 100, y: 100, width: 600, height: 400), workArea: area, viewportSize: 300))
        XCTAssertNil(WindowPeekPlacement.origin(window: window, workArea: area, viewportSize: .nan))
    }
    func testSittingPetReleaseIsImmediateAndHeldClipsLoop() {
        var controller = DuckController(); controller.reset(to: .sitting); controller.setPet(true)
        controller.complete { XCTFail("Pet loop consumed randomness"); return 0 }
        XCTAssertEqual(controller.state, .sittingPet)
        let stale = controller.generation
        controller.setPet(false); XCTAssertEqual(controller.state, .sitting)
        controller.complete(token: stale) { XCTFail("Stale completion consumed RNG"); return 0 }
        XCTAssertEqual(controller.state, .sitting)
    }
    func testStaleCompletionAndPreviewResetDoNotAdvanceReplacement() {
        var controller = DuckController()
        let old = controller.generation
        controller.request(.bibleRead)
        controller.complete(token: old) { XCTFail("Stale completion used RNG"); return 0 }
        XCTAssertEqual(controller.state, .grabBible)
        let previous = controller.generation
        controller.reset(); XCTAssertTrue(controller.generation > previous)
        controller.reset(); XCTAssertTrue(controller.generation > previous + 1)
    }
    func testDrawingHoldsAndImmediateTransitionsResetClipClock() {
        let counts = Dictionary(uniqueKeysWithValues: DuckState.allCases.filter { $0 != .timeout }.map { ($0, 6) })
        var player = SpritePlayback(frameCounts: counts), controller = DuckController()
        player.advance(by: 0.16, controller: &controller) { 0 }; XCTAssertEqual(player.frameIndex, 0)
        player.advance(by: 0.01, controller: &controller) { 0 }; XCTAssertEqual(player.frameIndex, 1)
        player.advance(by: 0.829, controller: &controller) { 0 }; XCTAssertEqual(player.frameIndex, 5)
        player.advance(by: 0.002, controller: &controller) { 0.99 }; XCTAssertEqual(player.state, .wave)
        controller.setPet(true); player.synchronize(with: controller)
        XCTAssertEqual(player.state, .standingPet); XCTAssertEqual(player.frameIndex, 0)
        player.advance(by: .nan, controller: &controller) { 0 }; XCTAssertEqual(player.frameIndex, 0)
    }
    func testEveryPetSessionFinishesFirstCycleThenReleasesImmediately() {
        for (idle, petState, released) in [(DuckState.look, DuckState.standingPet, DuckState.wave), (.sitting, .sittingPet, .sitting)] {
            var controller = DuckController(); controller.reset(to: idle)
            for _ in 0..<2 {
                controller.setPet(true); XCTAssertEqual(controller.state, petState)
                XCTAssertFalse(controller.petCycleCompleted)
                let token = controller.generation
                controller.setPet(false); XCTAssertEqual(controller.state, petState)
                controller.setPet(true); XCTAssertEqual(controller.generation, token)
                controller.complete { XCTFail("Pet cycle consumed randomness"); return 0 }
                XCTAssertEqual(controller.state, petState); XCTAssertTrue(controller.petCycleCompleted)
                controller.complete { XCTFail("Pet loop consumed randomness"); return 0 }
                XCTAssertTrue(controller.petCycleCompleted)
                let stale = controller.generation
                controller.setPet(false); XCTAssertEqual(controller.state, released)
                controller.complete(token: stale) { XCTFail("Stale completion used randomness"); return 0 }
                XCTAssertEqual(controller.state, released)
            }
        }
    }
    func testShortHoverHoldsActualFramesUntilFirstCycleCompletes() {
        let counts = Dictionary(uniqueKeysWithValues: DuckState.allCases.filter { $0 != .timeout }.map { ($0, 6) })
        for (idle, petState, released) in [(DuckState.look, DuckState.standingPet, DuckState.wave), (.sitting, .sittingPet, .sitting)] {
            var controller = DuckController(); controller.reset(to: idle); controller.setPet(true)
            var player = SpritePlayback(frameCounts: counts); player.synchronize(with: controller)
            controller.setPet(false)
            player.advance(by: 0.999, controller: &controller) { XCTFail("Pet exit used randomness"); return 0 }
            XCTAssertEqual(player.state, petState); XCTAssertEqual(player.frameIndex, 5)
            player.advance(by: 0.001, controller: &controller) { XCTFail("Pet exit used randomness"); return 0 }
            XCTAssertEqual(player.state, released); XCTAssertEqual(player.frameIndex, 0)
        }
    }
    func testDialogueForcesPetFalseDuringFirstCycleAndSubsequentHover() {
        for (idle, petState, released) in [(DuckState.look, DuckState.standingPet, DuckState.wave), (.sitting, .sittingPet, .sitting)] {
            var controller = DuckController(); controller.reset(to: idle); controller.setPet(true)
            controller.setDialogueOpen(true)
            XCTAssertFalse(controller.pet); XCTAssertEqual(controller.state, petState)
            controller.setPet(true); XCTAssertFalse(controller.pet)
            controller.complete { XCTFail("Dialogue pet exit used randomness"); return 0 }
            XCTAssertEqual(controller.state, released)
            controller.setPet(true); XCTAssertFalse(controller.pet); XCTAssertEqual(controller.state, released)
            controller.setDialogueOpen(false); XCTAssertFalse(controller.pet)
            controller.setPet(true); XCTAssertEqual(controller.state, petState); XCTAssertFalse(controller.petCycleCompleted)
            controller.complete { XCTFail("Pet cycle used randomness"); return 0 }
            controller.setDialogueOpen(true); XCTAssertFalse(controller.pet); XCTAssertEqual(controller.state, released)
        }
    }
    func testBubbleUsesAllFiveFramesHoldsLastAndCollapsesInReverse() {
        var bubble = SpeechBubblePlayback(); bubble.open()
        XCTAssertEqual(bubble.frameIndex, 0)
        for index in 1...4 { bubble.advance(by: 1.0 / 6); XCTAssertEqual(bubble.frameIndex, index) }
        XCTAssertFalse(bubble.isExpanded)
        bubble.advance(by: 1.0 / 6); XCTAssertTrue(bubble.isExpanded)
        bubble.advance(by: 100); XCTAssertEqual(bubble.frameIndex, 4)
        bubble.close(); XCTAssertFalse(bubble.isExpanded)
        for index in (0...3).reversed() { bubble.advance(by: 1.0 / 6); XCTAssertEqual(bubble.frameIndex, index) }
        XCTAssertTrue(bubble.isVisible)
        bubble.advance(by: 1.0 / 6); XCTAssertFalse(bubble.isVisible)
        bubble.open(); bubble.advance(by: 2.0 / 6); bubble.close()
        bubble.advance(by: 1.0 / 6); XCTAssertEqual(bubble.frameIndex, 1)
        bubble.open(); bubble.advance(by: 1.0 / 6); XCTAssertEqual(bubble.frameIndex, 2)
    }
    func testPauseHideAndSleepNeverCatchUpWallTime() {
        var clock = DrawingClock()
        XCTAssertEqual(clock.sample(at: 10, running: true), 0)
        XCTAssertEqual(clock.sample(at: 10.125, running: true), 0.125)
        XCTAssertEqual(clock.sample(at: 10.125, running: false), 0)
        XCTAssertEqual(clock.sample(at: 100, running: false), 0)
        XCTAssertEqual(clock.sample(at: 200, running: true), 0)
        XCTAssertEqual(clock.sample(at: 200.125, running: true), 0.125)
    }
    func testFinalAssetsPreserveCountsCalibrationAndFiveSpeechFrames() throws {
        let assets = SpriteLibrary()
        XCTAssertNil(assets.failure)
        let expected: [DuckState: Int] = [.look:14, .alternateLook:24, .wave:21, .standingPet:18, .sitDown:20,
            .standUp:23, .sitting:9, .sittingLook:18, .sittingPet:9, .goodbye:27, .peek:23, .windowPeek:39,
            .grabCamera:14, .cameraIdle:12, .deliverPhoto:23, .grabBible:17, .bibleIdle:14, .stowBible:11]
        XCTAssertEqual(assets.frames.count, 18); XCTAssertEqual(assets.missingStates.count, 4)
        XCTAssertEqual(assets.speechFrames.count, 5)
        for (state, count) in expected {
            XCTAssertEqual(assets.frameCounts[state], count)
            for index in 0..<count {
                let frame = try XCTUnwrap(assets.frame(state: state, index: index))
                XCTAssertEqual(frame.image.width, 700); XCTAssertEqual(frame.image.height, 500)
                XCTAssertTrue(frame.placement.width > 0)
                XCTAssertFalse(frame.contains(x: 0.01, y: 0.01))
            }
        }
        let first = try XCTUnwrap(assets.frame(state: .look, index: 0))
        XCTAssertEqual(first.placement.minX, 360.7 / 1700, accuracy: 0.0001)
        XCTAssertTrue((0..<80).contains { first.contains(x: 0.5, y: Double($0)/80) })
        XCTAssertTrue(first.contains(x: 0.5, y: 0.62))
        XCTAssertFalse(first.contains(x: 0.5, y: 0.74))
        for state in assets.missingStates {
            XCTAssertEqual(assets.frameCounts[state], 10); XCTAssertNil(assets.frame(state: state, index: 0))
        }
    }
    func testMissingAndCorruptResourcesUseRecoverablePinkFallback() throws {
        let missing = SpriteLibrary(directory: URL(fileURLWithPath: "/nonexistent-duck-sprites"))
        XCTAssertNotNil(missing.failure); XCTAssertNil(missing.frame(state: .look, index: 0))
        XCTAssertEqual(missing.missingStates.count, 22)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("{broken".utf8).write(to: directory.appendingPathComponent("manifest.json"))
        let corrupt = SpriteLibrary(directory: directory)
        XCTAssertNotNil(corrupt.failure); XCTAssertTrue(corrupt.frames.isEmpty)
    }
}
