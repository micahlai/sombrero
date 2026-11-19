import XCTest
import PetCore
import PetAssets

final class SpriteTests: XCTestCase {
    func testStandingChoiceBoundariesAndEveryCompletionIncludingRepeats() {
        for (sample, expected) in [(0,DuckState.look),(39,.look),(40,.alternateLook),(79,.alternateLook),(80,.sitDown),(99,.sitDown)] {
            var controller = DuckController()
            XCTAssertEqual(controller.state,.look)
            XCTAssertEqual(controller.complete { sample },expected)
        }
        for origin in [DuckState.look,.alternateLook,.standUp] {
            var controller = DuckController()
            if origin == .alternateLook { controller.complete {40} }
            if origin == .standUp {
                controller.complete {80}; controller.complete { XCTFail("Sit-down consumed RNG"); return 0 }; controller.complete {80}
            }
            XCTAssertEqual(controller.state,origin)
            XCTAssertEqual(controller.complete {79},.alternateLook)
        }
    }
    func testSitDownRequiresSittingAndSittingBoundaries() {
        for (sample,expected) in [(0,DuckState.sitting),(79,.sitting),(80,.standUp),(99,.standUp)] {
            var controller = DuckController()
            controller.complete {80}
            XCTAssertEqual(controller.complete {XCTFail("Required transition must not consume RNG"); return 0},.sitting)
            XCTAssertEqual(controller.complete {sample},expected)
        }
    }
    func testDrawingHoldsAndClipCompletion() {
        var player = SpritePlayback(frameCounts: [.look:23,.alternateLook:25,.sitDown:20,.standUp:20,.sitting:20])
        var completions = 0
        let next = { completions += 1; return DuckState.alternateLook }
        player.advance(by:0.16,next:next); XCTAssertEqual(player.frameIndex,0)
        player.advance(by:0.01,next:next); XCTAssertEqual(player.frameIndex,1)
        player.advance(by:23.0/6 - 0.17 - 0.001,next:next); XCTAssertEqual(player.frameIndex,22); XCTAssertEqual(completions,0)
        player.advance(by:0.002,next:next); XCTAssertEqual(player.state,.alternateLook); XCTAssertEqual(player.frameIndex,0); XCTAssertEqual(completions,1)
        player.advance(by:25.0/6,next:next); XCTAssertEqual(completions,2); XCTAssertEqual(player.frameIndex,0)
        player.advance(by:.nan,next:next); player.advance(by:-10,next:next); XCTAssertEqual(completions,2)
    }
    func testPauseHideAndSleepNeverCatchUpWallTime() {
        var clock=DrawingClock()
        XCTAssertEqual(clock.sample(at:10,running:true),0)
        XCTAssertEqual(clock.sample(at:10.125,running:true),0.125)
        XCTAssertEqual(clock.sample(at:10.125,running:false),0)
        XCTAssertEqual(clock.sample(at:100,running:false),0)
        XCTAssertEqual(clock.sample(at:200,running:true),0)
        XCTAssertEqual(clock.sample(at:200.125,running:true),0.125)
        XCTAssertEqual(clock.sample(at:.nan,running:true),0)
        XCTAssertEqual(clock.sample(at:199,running:true),0)
    }
    func testPackagedAssetsHaveExpectedCountsAndTransparentHitMasks() throws {
        let assets=SpriteLibrary()
        XCTAssertNil(assets.failure)
        XCTAssertEqual(assets.frameCounts,[.look:23,.alternateLook:25,.sitDown:20,.standUp:20,.sitting:20])
        for state in DuckState.allCases {
            for index in 0..<assets.frameCounts[state]! {
                let frame=try XCTUnwrap(assets.frame(state:state,index:index))
                XCTAssertEqual(frame.image.width,320)
                XCTAssertFalse(frame.contains(x:0.01,y:0.01))
                XCTAssertTrue((0..<80).contains {frame.contains(x:0.5,y:Double($0)/80)})
            }
        }
    }
    func testMissingAndCorruptResourcesUseRecoverableFallback() throws {
        let missing=SpriteLibrary(directory:URL(fileURLWithPath:"/nonexistent-duck-sprites"))
        XCTAssertNotNil(missing.failure); XCTAssertNil(missing.frame(state:.look,index:0))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        try Data("{broken".utf8).write(to:directory.appendingPathComponent("manifest.json"))
        let corrupt=SpriteLibrary(directory:directory)
        XCTAssertNotNil(corrupt.failure); XCTAssertNil(corrupt.frame(state:.look,index:0))
        let manifest: [String:Any] = ["schemaVersion":1,"timelineFPS":24,"drawingFPS":6,"holdFrames":4,"frameWidth":320,"frameHeight":320,
            "clips": (1...5).map { ["state":$0,"frames":[["resource":"bad.png","durationFrames":4]]] as [String:Any] }]
        try JSONSerialization.data(withJSONObject:manifest).write(to:directory.appendingPathComponent("manifest.json"))
        let missingFrame=SpriteLibrary(directory:directory)
        XCTAssertNotNil(missingFrame.failure); XCTAssertTrue(missingFrame.frames.isEmpty)
        try Data("not a PNG".utf8).write(to:directory.appendingPathComponent("bad.png"))
        let corruptFrame=SpriteLibrary(directory:directory)
        XCTAssertNotNil(corruptFrame.failure); XCTAssertTrue(corruptFrame.frames.isEmpty)
    }
}
