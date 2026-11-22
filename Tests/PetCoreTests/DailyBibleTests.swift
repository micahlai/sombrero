import XCTest
import PetCore
import PetAssets

final class DailyBibleTests: XCTestCase {
    let calendar=DailyBible.calendar(timeZone:TimeZone(identifier:"America/New_York")!)
    func date(_ year: Int=2026,_ month: Int=11,_ day: Int=21,_ hour: Int=12) -> Date {
        calendar.date(from:DateComponents(year:year,month:month,day:day,hour:hour))!
    }
    func testOfflineCatalogContainsEveryPlannedPassageAndExactText() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        XCTAssertTrue(catalog.isValid); XCTAssertEqual(catalog.verses.count,100)
        XCTAssertEqual(catalog.verses.first?.reference,"Genesis 1:1")
        XCTAssertEqual(catalog.verses.first?.text,"In the beginning, God created the heavens and the earth.")
        XCTAssertTrue(catalog.verses.allSatisfy { !$0.text.contains("<") && !$0.text.contains("Reader preview") })
        XCTAssertNil(BibleLibrary(directory:URL(fileURLWithPath:"/missing-bible")).catalog)
    }
    func testDailyScheduleIsPersistedAndReconciliationNeverRerolls() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        var daily=DailyBible()
        XCTAssertTrue(daily.reconcile(at:date(2026,11,21,8),catalog:catalog,calendar:calendar) { 0 })
        let today=try XCTUnwrap(daily.today(at:date(),calendar:calendar))
        XCTAssertEqual(today.readyAt,date(2026,11,21,0)); XCTAssertFalse(today.isRead)
        XCTAssertTrue(today.isReady(at:date(2026,11,21,0))); XCTAssertTrue(today.isReady(at:date(2026,11,21,23)))
        let stored=try JSONDecoder().decode(DailyBible.self,from:JSONEncoder().encode(daily))
        XCTAssertEqual(stored,daily)
        XCTAssertFalse(daily.reconcile(at:date(2026,11,21,22),catalog:catalog,calendar:calendar) { XCTFail("Reconciliation rerolled the day"); return 0 })
        XCTAssertEqual(daily.today(at:date(),calendar:calendar),today)
        XCTAssertEqual(daily.nextChange(after:date(2026,11,21,10),calendar:calendar),date(2026,11,22,0))
        XCTAssertEqual(daily.nextChange(after:date(2026,11,21,20),calendar:calendar),date(2026,11,22,0))
    }
    func testVerseAvailableAllDayAndWakeDoesNotBackfillMissedDays() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        var daily=DailyBible()
        daily.reconcile(at:date(),catalog:catalog,calendar:calendar) { 1 }
        XCTAssertEqual(daily.today(at:date(),calendar:calendar)?.readyAt,date(2026,11,21,0))
        XCTAssertEqual(daily.today(at:date(),calendar:calendar)?.verseID,catalog.verses.last?.id)
        daily.reconcile(at:date(2026,11,29,22),catalog:catalog,calendar:calendar) { 0 }
        XCTAssertEqual(daily.assignments.count,2)
        XCTAssertTrue(daily.today(at:date(2026,11,29,22),calendar:calendar)!.isReady(at:date(2026,11,29,22)))
    }
    func testThreePriorLocalDatesAreExcludedAcrossDaylightSavingChange() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        var daily=DailyBible(), ids: [String]=[]
        for day in 6...10 {
            let now=date(2026,3,day,12)
            daily.reconcile(at:now,catalog:catalog,calendar:calendar) { 0 }
            ids.append(daily.today(at:now,calendar:calendar)!.verseID)
            XCTAssertEqual(calendar.component(.hour,from:daily.today(at:now,calendar:calendar)!.readyAt),0)
        }
        XCTAssertEqual(Set(ids.prefix(4)).count,4); XCTAssertEqual(ids[0],ids[4])
    }
    func testTimeZoneChangesKeepExistingLocalDateAssignment() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        var daily=DailyBible(); let now=date()
        daily.reconcile(at:now,catalog:catalog,calendar:calendar) { 0.5 }
        let assignment=daily.today(at:now,calendar:calendar)
        let west=DailyBible.calendar(timeZone:TimeZone(identifier:"America/Los_Angeles")!)
        XCTAssertFalse(daily.reconcile(at:now,catalog:catalog,calendar:west) { XCTFail("Travel rerolled an existing date"); return 0 })
        XCTAssertEqual(daily.today(at:now,calendar:west),assignment)
    }
    func testPreviouslyScheduledVerseBecomesAvailableWithoutRerolling() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        let payload:[String:Any] = ["assignments":[["localDate":"2026-11-21", "timeZoneID":calendar.timeZone.identifier,
            "readyAt":date(2026,11,21,19).timeIntervalSinceReferenceDate,"verseID":catalog.verses[0].id,"isRead":true]]]
        var daily=try JSONDecoder().decode(DailyBible.self,from:JSONSerialization.data(withJSONObject:payload))
        XCTAssertTrue(daily.reconcile(at:date(2026,11,21,8),catalog:catalog,calendar:calendar) { XCTFail("Migration must preserve the verse"); return 0 })
        let assignment=try XCTUnwrap(daily.today(at:date(),calendar:calendar))
        XCTAssertTrue(assignment.isReady(at:date(2026,11,21,8)))
        XCTAssertEqual(assignment.verseID,catalog.verses[0].id); XCTAssertTrue(assignment.isRead)
    }
    func testOnlyCompletedDisplayedDailyReaderClearsItsOwnBadge() throws {
        let catalog=try XCTUnwrap(BibleLibrary().catalog)
        var daily=DailyBible(); daily.reconcile(at:date(),catalog:catalog,calendar:calendar) { 0 }
        let assignment=daily.today(at:date(),calendar:calendar)!
        let verse=catalog.verses.first { $0.id == assignment.verseID }!
        var session=BibleReadingSession(verse:verse,localDate:assignment.localDate)
        XCTAssertFalse(session.complete(in:&daily)); XCTAssertFalse(daily.today(at:date(),calendar:calendar)!.isRead)
        var preview=BibleReadingSession(verse:verse,localDate:nil); preview.presentedContent()
        XCTAssertFalse(preview.complete(in:&daily))
        session.presentedContent()
        daily.reconcile(at:date(2026,11,22,12),catalog:catalog,calendar:calendar) { 0 }
        XCTAssertTrue(session.complete(in:&daily)); XCTAssertFalse(session.complete(in:&daily))
        XCTAssertTrue(daily.today(at:date(),calendar:calendar)!.isRead)
        XCTAssertFalse(daily.today(at:date(2026,11,22,12),calendar:calendar)!.isRead)
    }
    func testBibleCancellationClearsQueueAndFinishesSafeAnimationExit() {
        var controller=DuckController(); controller.reset(to:.sitDown)
        controller.request(.bibleRead); controller.cancel(.bibleRead)
        XCTAssertTrue(controller.pending.isEmpty); XCTAssertFalse(controller.reading)
        controller.complete { 0 }; XCTAssertEqual(controller.state,.sitting)
        controller.reset(); controller.setDialogueOpen(true); controller.request(.bibleRead)
        XCTAssertEqual(controller.state,.grabBible); controller.setPet(true); XCTAssertFalse(controller.pet)
        controller.cancel(.bibleRead); XCTAssertEqual(controller.state,.grabBible)
        controller.complete { 0 }; XCTAssertEqual(controller.state,.bibleIdle)
        controller.complete { 0 }; XCTAssertEqual(controller.state,.stowBible)
        controller.complete { 0 }; XCTAssertEqual(controller.state,.look)
    }
    func testPaginationPreservesWordsWhitespaceAndUnicodeWithoutDroppingText() {
        for text in ["A verse with words.\n\nA second paragraph with ‘quotes’ and 🕊️.",String(repeating:"Longword",count:30),"", "日本語の文章も改変しない"] {
            let pages=BiblePagination.pages(text) { $0.count<=20 }
            XCTAssertEqual(pages.joined(),text)
            XCTAssertTrue(pages.allSatisfy { $0.count<=20 })
        }
    }
    func testReopeningBibleDuringItsExitCannotLoseTheRequest() {
        var controller=DuckController(); controller.request(.bibleRead)
        controller.complete { 0 }; XCTAssertEqual(controller.state,.bibleIdle)
        controller.cancel(.bibleRead); controller.request(.bibleRead)
        XCTAssertTrue(controller.reading); XCTAssertTrue(controller.pending.isEmpty)
        controller.cancel(.bibleRead); controller.complete { 0 }; XCTAssertEqual(controller.state,.stowBible)
        controller.request(.bibleRead); XCTAssertEqual(controller.pending,[.bibleRead])
        controller.complete { 0 }; XCTAssertEqual(controller.state,.grabBible); XCTAssertTrue(controller.reading)
    }

}
