import Foundation

public struct BibleVerse: Codable, Equatable, Identifiable {
    public let id: String
    public let reference: String
    public let topic: String
    public let text: String
    public init(id: String, reference: String, topic: String, text: String) {
        self.id=id; self.reference=reference; self.topic=topic; self.text=text
    }
}
public struct BibleCatalog: Codable {
    public let schemaVersion: Int
    public let translation: String
    public let abbreviation: String
    public let source: String
    public let verses: [BibleVerse]
    public var isValid: Bool {
        schemaVersion == 1 && verses.count >= PetConstants.Bible.excludedDays+1 &&
        Set(verses.map(\.id)).count == verses.count && verses.allSatisfy { !$0.id.isEmpty && !$0.reference.isEmpty && !$0.text.isEmpty }
    }
}
public struct DailyVerseAssignment: Codable, Equatable {
    public let localDate: String
    public let timeZoneID: String
    public let readyAt: Date
    public let verseID: String
    public var isRead: Bool
    public func isReady(at date: Date) -> Bool { date >= readyAt }
}
/// Local calendar dates, rather than elapsed hours, define the no-repeat window.
/// Existing dates retain their selection, ready time and read status across travel/restarts.
public struct DailyBible: Codable, Equatable {
    public private(set) var assignments: [DailyVerseAssignment] = []
    public init() {}
    public static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=timeZone; return calendar
    }
    public static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts=calendar.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",parts.year!,parts.month!,parts.day!)
    }
    public func today(at now: Date, calendar: Calendar = Self.calendar()) -> DailyVerseAssignment? {
        let key=Self.dateKey(now,calendar:calendar)
        return assignments.first { $0.localDate == key }
    }
    @discardableResult public mutating func reconcile(at now: Date, catalog: BibleCatalog, calendar: Calendar = Self.calendar(),
                                                     sample: () -> Double = { Double.random(in:0..<1) }) -> Bool {
        guard catalog.isValid, today(at:now,calendar:calendar) == nil else { return false }
        let day=calendar.startOfDay(for:now)
        let priorDates=Set((1...PetConstants.Bible.excludedDays).compactMap { calendar.date(byAdding:.day,value:-$0,to:day) }.map { Self.dateKey($0,calendar:calendar) })
        let excluded=Set(assignments.filter { priorDates.contains($0.localDate) }.map(\.verseID))
        let candidates=catalog.verses.filter { !excluded.contains($0.id) }
        guard !candidates.isEmpty,
              let start=calendar.date(bySettingHour:PetConstants.Bible.readyHourStart,minute:0,second:0,of:day),
              let end=calendar.date(bySettingHour:PetConstants.Bible.readyHourEnd,minute:0,second:0,of:day) else { return false }
        let timeRoll=sample(), verseRoll=sample()
        precondition(timeRoll.isFinite && (0...1).contains(timeRoll) && verseRoll.isFinite && (0...1).contains(verseRoll))
        let choice=candidates[min(candidates.count-1,Int(verseRoll*Double(candidates.count)))]
        assignments.append(DailyVerseAssignment(localDate:Self.dateKey(now,calendar:calendar),timeZoneID:calendar.timeZone.identifier,
            readyAt:start.addingTimeInterval(timeRoll*end.timeIntervalSince(start)),verseID:choice.id,isRead:false))
        return true
    }
    @discardableResult public mutating func markRead(localDate: String, verseID: String) -> Bool {
        guard let index=assignments.firstIndex(where:{ $0.localDate == localDate && $0.verseID == verseID }), !assignments[index].isRead else { return false }
        assignments[index].isRead=true; return true
    }
    public func nextChange(after now: Date, calendar: Calendar = Self.calendar()) -> Date? {
        let midnight=calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now))
        if let assignment=today(at:now,calendar:calendar), assignment.readyAt > now { return min(assignment.readyAt,midnight ?? assignment.readyAt) }
        return midnight
    }
}

/// The host completes a session only after the reader displays the final page.
public struct BibleReadingSession {
    public let verse: BibleVerse
    public let localDate: String?
    public private(set) var hasPresentedContent = false
    public init(verse: BibleVerse, localDate: String?) { self.verse=verse; self.localDate=localDate }
    public mutating func presentedContent() { hasPresentedContent=true }
    @discardableResult public func complete(in daily: inout DailyBible) -> Bool {
        guard hasPresentedContent, let localDate else { return false }
        return daily.markRead(localDate:localDate,verseID:verse.id)
    }
}
