import Foundation

enum StatsBaselineEngine {
    static func percentile(_ p: Double, values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let sorted = values.sorted()
        let position = clamped * Double(sorted.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }
        let lower = sorted[lowerIndex]
        let upper = sorted[upperIndex]
        let fraction = position - Double(lowerIndex)
        return lower + (upper - lower) * fraction
    }

    static func baseline(
        series: [WeeklyMetricValue],
        defaultFloor: Double = 0,
        userFloor: Double? = nil,
        window: Int = 8
    ) -> BaselineResult? {
        guard !series.isEmpty else { return nil }
        let ordered = series.sorted { $0.weekStart < $1.weekStart }
        let values = ordered.suffix(window).map { max(0, $0.value) }
        guard !values.isEmpty else { return nil }

        let autoFloor = percentile(0.2, values: values)
        let bandHigh = percentile(0.8, values: values)
        let resolvedFloor = max(userFloor ?? autoFloor, defaultFloor)
        let currentValue = max(0, ordered.last?.value ?? 0)
        let delta = resolvedFloor > 0 ? (currentValue - resolvedFloor) / resolvedFloor : 0
        let streak = streakWeeks(series: ordered, floor: resolvedFloor)

        let type: BaselineType
        if let userFloor {
            type = .user
        } else if defaultFloor > 0 && resolvedFloor == defaultFloor && autoFloor < defaultFloor {
            type = .default
        } else {
            type = .auto
        }

        let band: ClosedRange<Double>? = resolvedFloor <= 0 ? nil : (resolvedFloor...max(resolvedFloor, bandHigh))
        return BaselineResult(floor: resolvedFloor, band: band, type: type, streakWeeks: streak, deltaPercent: delta)
    }

    static func streakWeeks(series: [WeeklyMetricValue], floor: Double) -> Int {
        guard floor > 0 else { return 0 }
        let ordered = series.sorted { $0.weekStart < $1.weekStart }
        var streak = 0
        for point in ordered.reversed() {
            if point.value >= floor {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    static func trend(current: Double, previous: Double, tolerance: Double = 0.01) -> TrendDirection {
        guard previous > 0 else { return current > 0 ? .up : .flat }
        let delta = (current - previous) / previous
        if delta > tolerance { return .up }
        if delta < -tolerance { return .down }
        return .flat
    }
}
