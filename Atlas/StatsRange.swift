import Foundation

enum StatsRange: String, CaseIterable, Identifiable {
    case sevenDays = "7D"
    case fourWeeks = "4W"
    case twelveWeeks = "12W"
    case oneYear = "1Y"

    var id: String { rawValue }

    var title: String { rawValue }

    var weeks: Int {
        switch self {
        case .sevenDays: return 1
        case .fourWeeks: return 4
        case .twelveWeeks: return 12
        case .oneYear: return 52
        }
    }

    var days: Int { weeks * 7 }

    func dateInterval(now: Date = Date(), calendar: Calendar = DateRanges.isoCalendar()) -> DateInterval {
        let startOfCurrentWeek = DateRanges.startOfWeekMonday(for: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: startOfCurrentWeek) ?? startOfCurrentWeek
        let rawEnd = calendar.date(byAdding: .day, value: weeks * 7, to: start) ?? now
        let end = max(rawEnd, start)
        return DateInterval(start: start, end: end)
    }

    func extendedInterval(extraWeeks: Int = 8, now: Date = Date(), calendar: Calendar = DateRanges.isoCalendar()) -> DateInterval {
        let base = dateInterval(now: now, calendar: calendar)
        let extendedStart = calendar.date(byAdding: .day, value: -7 * extraWeeks, to: base.start) ?? base.start
        return DateInterval(start: extendedStart, end: base.end)
    }

    func weekStarts(now: Date = Date(), calendar: Calendar = DateRanges.isoCalendar(), includePadding padding: Int = 0) -> [Date] {
        let interval = dateInterval(now: now, calendar: calendar)
        let paddedStart = calendar.date(byAdding: .day, value: -7 * padding, to: interval.start) ?? interval.start
        var starts: [Date] = []
        var cursor = paddedStart
        while cursor < interval.end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return starts
    }
}
