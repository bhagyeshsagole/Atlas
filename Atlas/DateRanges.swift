import Foundation

/// Shared week calculations: Monday-start, half-open ranges.
enum DateRanges {
    static func isoCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    static func startOfWeekMonday(for date: Date, calendar: Calendar = isoCalendar()) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    static func weekRangeMonday(for date: Date, calendar: Calendar = isoCalendar()) -> Range<Date> {
        let start = startOfWeekMonday(for: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return start..<end
    }

    static func isInCurrentWeekMonday(_ date: Date, now: Date = Date(), calendar: Calendar = isoCalendar()) -> Bool {
        weekRangeMonday(for: now, calendar: calendar).contains(date)
    }
}
