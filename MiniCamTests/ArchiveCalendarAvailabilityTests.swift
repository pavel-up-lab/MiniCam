import XCTest
@testable import MiniCam

final class ArchiveCalendarAvailabilityTests: XCTestCase {
    func testDayIsAvailableOnlyWhenRecordingIntersectsIt() throws {
        let calendar = makeCalendar()
        let segment = try makeSegment(
            id: "one",
            start: "2026-09-01T10:30:00Z",
            end: "2026-09-01T11:00:00Z"
        )
        let availability = ArchiveCalendarAvailability(
            segments: [segment],
            calendar: calendar
        )

        XCTAssertTrue(availability.isDayAvailable(date("2026-09-01T00:00:00Z")))
        XCTAssertFalse(availability.isDayAvailable(date("2026-09-02T00:00:00Z")))
    }

    func testAvailableHoursIncludeEveryHourIntersectingRecording() throws {
        let calendar = makeCalendar()
        let segment = try makeSegment(
            id: "one",
            start: "2026-09-01T10:30:00Z",
            end: "2026-09-01T11:15:00Z"
        )
        let availability = ArchiveCalendarAvailability(
            segments: [segment],
            calendar: calendar
        )

        let hours = availability.availableHours(
            on: date("2026-09-01T00:00:00Z")
        )

        XCTAssertEqual(hours, Set([10, 11]))
    }

    func testGapUsesNextRecordingThenFallsBackToPreviousRecording() throws {
        let calendar = makeCalendar()
        let first = try makeSegment(
            id: "first",
            start: "2026-09-01T10:00:00Z",
            end: "2026-09-01T10:15:00Z"
        )
        let second = try makeSegment(
            id: "second",
            start: "2026-09-01T10:30:00Z",
            end: "2026-09-01T10:45:00Z"
        )
        let availability = ArchiveCalendarAvailability(
            segments: [first, second],
            calendar: calendar
        )

        let next = availability.nearestPlayableDate(
            to: date("2026-09-01T10:20:00Z")
        )
        let previous = availability.nearestPlayableDate(
            to: date("2026-09-01T10:50:00Z")
        )

        XCTAssertEqual(next, second.start)
        XCTAssertEqual(previous, second.end.addingTimeInterval(-0.001))
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func makeSegment(
        id: String,
        start: String,
        end: String
    ) throws -> RecordingSegment {
        try RecordingSegment(
            id: id,
            start: date(start),
            end: date(end),
            playbackURI: "rtsp://camera/\(id)"
        )
    }
}

final class RussianDateFormattingTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testUsesRussianMonthAndTwentyFourHourTime() {
        let date = makeDate()

        XCTAssertEqual(
            RussianDateFormatting.dateAndTime(date, timeZone: utc),
            "5 сент. 2026, 13:07:09"
        )
        XCTAssertEqual(
            RussianDateFormatting.shortTime(date, timeZone: utc),
            "13:07"
        )
    }

    func testUsesStandaloneRussianMonthInCalendarHeader() {
        XCTAssertEqual(
            RussianDateFormatting.monthAndYear(makeDate(), timeZone: utc),
            "сентябрь 2026"
        )
    }

    func testCalendarStartsOnMondayWithRussianWeekdayNames() {
        let calendar = RussianDateFormatting.calendar
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let mondayIndex = calendar.firstWeekday - 1

        XCTAssertEqual(calendar.firstWeekday, 2)
        XCTAssertEqual(symbols[mondayIndex].lowercased(), "пн")
    }

    private func makeDate() -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = utc
        components.year = 2026
        components.month = 9
        components.day = 5
        components.hour = 13
        components.minute = 7
        components.second = 9
        return components.date!
    }
}
