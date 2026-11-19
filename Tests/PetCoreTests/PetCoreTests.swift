import XCTest
@testable import PetCore

final class PetCoreTests: XCTestCase {
    private let primary = PetDisplay(id: "main", workArea: PetRect(x: 0, y: 40, width: 1440, height: 820))
    private let left = PetDisplay(id: "left", workArea: PetRect(x: -1920, y: 0, width: 1920, height: 1080))

    func testPlacementRoundTripOnNegativeOriginDisplay() throws {
        let point = PetPoint(x: -1700, y: 300)
        let saved = Placement.save(origin: point, size: 112, display: left)
        let restored = try XCTUnwrap(Placement.restore(saved, size: 112, displays: [primary, left], fallbackID: "main"))
        XCTAssertEqual(restored.x, point.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, point.y, accuracy: 0.001)
    }

    func testDisconnectedDisplayRestoresInsideCurrentWorkArea() throws {
        let saved = SavedPlacement(displayID: "removed", normalizedX: 0.9, normalizedY: 0.9)
        let point = try XCTUnwrap(Placement.restore(saved, size: 152, displays: [primary], fallbackID: "main"))
        XCTAssertGreaterThanOrEqual(point.x, 0); XCTAssertLessThanOrEqual(point.x + 152, 1440)
        XCTAssertGreaterThanOrEqual(point.y, 40); XCTAssertLessThanOrEqual(point.y + 152, 860)
    }

    func testSizeChangeKeepsNormalizedPlacementAndBounds() throws {
        let saved = SavedPlacement(displayID: "main", normalizedX: 1, normalizedY: 0)
        let point = try XCTUnwrap(Placement.restore(saved, size: 200, displays: [primary], fallbackID: "main"))
        XCTAssertEqual(point, PetPoint(x: 1240, y: 40))
    }

    func testNonFiniteStoredCoordinatesAndTinyDisplayRecover() throws {
        let tiny = PetDisplay(id: "tiny", workArea: PetRect(x: 10, y: 20, width: 80, height: 70))
        let saved = SavedPlacement(displayID: "tiny", normalizedX: .nan, normalizedY: .infinity)
        let point = try XCTUnwrap(Placement.restore(saved, size: 112, displays: [tiny], fallbackID: nil))
        XCTAssertEqual(point, PetPoint(x: 10, y: 20))
        XCTAssertNil(Placement.restore(nil, size: 112, displays: [], fallbackID: nil))
    }

    func testDismissCancelsPetAndShowCannotResumeOldReaction() {
        var pet = PetBehavior(); pet.pet(); pet.advance(by: 0.5); pet.hide(); pet.advance(by: 4); pet.show()
        XCTAssertTrue(pet.isVisible); XCTAssertEqual(pet.activity, .idle); XCTAssertEqual(pet.elapsed, 0)
    }

    func testPausedReactionResumesWithRemainingTime() {
        var pet = PetBehavior(); pet.pet(); pet.advance(by: 1)
        pet.isPaused = true; pet.advance(by: 5); XCTAssertEqual(pet.activity, .petting)
        pet.isPaused = false; pet.advance(by: 0.9); XCTAssertEqual(pet.activity, .petting)
        pet.advance(by: 0.2); XCTAssertEqual(pet.activity, .idle)
    }

    func testRapidPetRetriggersFiniteReactionAndRejectsInvalidClock() {
        var pet = PetBehavior(); pet.pet(); pet.advance(by: 1.9); pet.pet()
        pet.advance(by: .nan); pet.advance(by: -10); pet.advance(by: 0.5)
        XCTAssertEqual(pet.activity, .petting); XCTAssertEqual(pet.elapsed, 0.5)
        pet.advance(by: 1.6); XCTAssertEqual(pet.activity, .idle)
    }

    func testPreferenceRoundTripPreservesRecoveryControls() throws {
        var preferences = PetPreferences(); preferences.isVisible = false; preferences.clickThrough = true
        preferences.placement = SavedPlacement(displayID: "left", normalizedX: 0.3, normalizedY: 0.7)
        let recovered = try JSONDecoder().decode(PetPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(recovered, preferences)
        var bad = preferences; bad.size = .infinity
        XCTAssertEqual(bad.validated().size, 112)
    }
}
