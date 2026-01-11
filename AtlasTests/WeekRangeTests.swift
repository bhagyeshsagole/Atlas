import XCTest
@testable import Atlas

final class WeekRangeTests: XCTestCase {
    func testMondayWeekBoundaries() throws {
        var calendar = DateRanges.isoCalendar()
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard
            let sunday = formatter.date(from: "2026-01-11 12:00"),
            let sundayMorning = formatter.date(from: "2026-01-11 09:00"),
            let mondayCurrent = formatter.date(from: "2026-01-12 09:00"),
            let mondayPrev = formatter.date(from: "2026-01-05 09:00")
        else {
            XCTFail("Failed to create test dates")
            return
        }

        let range = DateRanges.weekRangeMonday(for: sunday, calendar: calendar)
        let start = range.lowerBound
        let end = range.upperBound

        let expectedStart = formatter.date(from: "2026-01-05 00:00")!
        let expectedEnd = formatter.date(from: "2026-01-12 00:00")!

        XCTAssertEqual(start, expectedStart)
        XCTAssertEqual(end, expectedEnd)
        XCTAssertTrue(range.contains(sundayMorning))
        XCTAssertFalse(range.contains(mondayCurrent))
        XCTAssertTrue(range.contains(mondayPrev))
    }
}
