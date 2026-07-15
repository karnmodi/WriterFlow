import Foundation
import GRDB

/// Reactive aggregation over `conversions` for the Stage 3.5 Usage tab. Aggregates are
/// computed client-side from the full (already-small, personal-scale) event list rather than
/// with SQL `GROUP BY` — simpler, and cheap at the data volumes this app produces.
@MainActor
final class UsageViewModel: ObservableObject {
    enum Granularity: String, CaseIterable, Identifiable {
        case daily = "Last 14 Days"
        case weekly = "Last 12 Weeks"
        var id: String { rawValue }
    }

    struct SeriesCount: Identifiable {
        let bucketStart: Date
        let series: String
        let count: Int
        var id: String { "\(bucketStart.timeIntervalSince1970)-\(series)" }
    }

    struct StackedSeriesCount: Identifiable {
        let bucketStart: Date
        let series: String
        let count: Int
        let lowerBound: Int
        let upperBound: Int
        var id: String { "\(bucketStart.timeIntervalSince1970)-\(series)" }
    }

    @Published private(set) var events: [ConversionEvent] = []
    @Published var granularity: Granularity = .daily

    private let modelsConfig: AzureModelsConfig
    private var observationTask: Task<Void, Never>?

    init(modelsConfig: AzureModelsConfig, db: DatabaseQueue = WriterFlowDatabase.shared) {
        self.modelsConfig = modelsConfig
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try ConversionEvent.order(Column("timestamp")).fetchAll(db)
            }
            do {
                for try await events in observation.values(in: db) {
                    self.events = events
                }
            } catch {
                Log.store.error("Usage ValueObservation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Headline stats

    var totalActions: Int { events.count }
    var acceptedActions: Int { events.filter(\.accepted).count }

    /// The product's north-star metric — nil (not 0%) when there's no data yet, so the UI
    /// can show "No actions yet" instead of a misleading 0%.
    var acceptanceRate: Double? {
        guard !events.isEmpty else { return nil }
        return Double(acceptedActions) / Double(events.count)
    }

    var totalTokensIn: Int { events.reduce(0) { $0 + ($1.tokensIn ?? 0) } }
    var totalTokensOut: Int { events.reduce(0) { $0 + ($1.tokensOut ?? 0) } }
    var actionsWithTokenUsage: Int {
        events.filter { $0.tokensIn != nil || $0.tokensOut != nil }.count
    }

    /// Rough estimate from the editable pricing table in `models.json` (Settings tab) —
    /// intentionally labeled "estimated" in the UI, not a billing-accurate figure.
    var estimatedCostUSD: Double {
        let config = AzureModelsConfig.loadFromDisk() ?? modelsConfig
        return events.reduce(0.0) { partial, event in
            guard let model = event.model else { return partial }
            let pricing = config.pricing(for: model)
            let inCost = Double(event.tokensIn ?? 0) / 1_000_000 * pricing.inputPerMillion
            let outCost = Double(event.tokensOut ?? 0) / 1_000_000 * pricing.outputPerMillion
            return partial + inCost + outCost
        }
    }

    var actionsUsingFallbackPricing: Int {
        let config = AzureModelsConfig.loadFromDisk() ?? modelsConfig
        return events.filter { event in
            guard let model = event.model,
                  event.tokensIn != nil || event.tokensOut != nil
            else { return false }
            return config.pricing[model] == nil
        }.count
    }

    // MARK: - Chart data

    /// One row per (bucket, action) for a stacked bar chart of action-type volume over time.
    var actionCountsBySeries: [SeriesCount] {
        bucketedCounts(keyed: { $0.action })
    }

    /// Explicit bounds avoid Swift Charts treating wide, overlapping date bars as one
    /// implicit stack, which can inflate the Y scale and make real values look invisible.
    var actionStackedSeries: [StackedSeriesCount] {
        let counts = actionCountsBySeries
        return chartBuckets.flatMap { bucket in
            var runningTotal = 0
            return activeActionSeries.compactMap { series -> StackedSeriesCount? in
                guard let row = counts.first(where: {
                    $0.bucketStart == bucket && $0.series == series
                }), row.count > 0 else { return nil }

                let lowerBound = runningTotal
                runningTotal += row.count
                return StackedSeriesCount(
                    bucketStart: bucket,
                    series: series,
                    count: row.count,
                    lowerBound: lowerBound,
                    upperBound: runningTotal
                )
            }
        }
    }

    var actionDataBuckets: [Date] {
        Array(Set(actionStackedSeries.map(\.bucketStart))).sorted()
    }

    var actionYAxisUpperBound: Int {
        let peak = chartBuckets.map { bucket in
            actionCountsBySeries
                .filter { $0.bucketStart == bucket }
                .reduce(0) { $0 + $1.count }
        }.max() ?? 0

        switch peak {
        case ...10: return 10
        case ...50: return Int(ceil(Double(peak) / 10) * 10)
        case ...200: return Int(ceil(Double(peak) / 25) * 25)
        default: return Int(ceil(Double(peak) / 100) * 100)
        }
    }

    /// Series names that have at least one non-zero count in the current window.
    var activeActionSeries: [String] {
        let cutoff = bucketCutoff(calendar: .current)
        return Array(Set(events.filter { $0.timestamp >= cutoff }.map(\.action))).sorted {
            let left = actionSeriesOrder.firstIndex(of: $0) ?? Int.max
            let right = actionSeriesOrder.firstIndex(of: $1) ?? Int.max
            return left == right ? $0 < $1 : left < right
        }
    }

    private let actionSeriesOrder = ["Elaborate", "Formal", "Casual", "Fix Grammar", "Reply", "Prompt Builder", "Custom"]

    /// One row per (bucket, "Input"/"Output") for a grouped bar chart of token volume over time.
    var tokenCountsBySeries: [SeriesCount] {
        let calendar = Calendar.current
        var totals: [Date: [String: Int]] = [:]

        for bucket in chartBuckets {
            totals[bucket] = ["Input": 0, "Output": 0]
        }

        let cutoff = bucketCutoff(calendar: calendar)
        for event in events where event.timestamp >= cutoff {
            let bucket = bucketStart(for: event.timestamp, calendar: calendar)
            totals[bucket, default: ["Input": 0, "Output": 0]]["Input", default: 0] += event.tokensIn ?? 0
            totals[bucket, default: ["Input": 0, "Output": 0]]["Output", default: 0] += event.tokensOut ?? 0
        }

        return totals.flatMap { bucket, series in
            series.map { SeriesCount(bucketStart: bucket, series: $0.key, count: $0.value) }
        }.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return $0.series < $1.series
        }
    }

    /// Keep both directions for a populated period, but omit periods where neither
    /// direction has usage so the chart only labels dates represented by real data.
    var tokenSeriesWithData: [SeriesCount] {
        let rows = tokenCountsBySeries
        let populatedBuckets = Set(
            chartBuckets.filter { bucket in
                rows.contains { $0.bucketStart == bucket && $0.count > 0 }
            }
        )
        return rows.filter { populatedBuckets.contains($0.bucketStart) }
    }

    var tokenDataBuckets: [Date] {
        Array(Set(tokenSeriesWithData.map(\.bucketStart))).sorted()
    }

    var tokenStackedSeries: [StackedSeriesCount] {
        let rows = tokenSeriesWithData
        return tokenDataBuckets.flatMap { bucket in
            var runningTotal = 0
            return ["Input", "Output"].compactMap { series -> StackedSeriesCount? in
                guard let row = rows.first(where: {
                    $0.bucketStart == bucket && $0.series == series
                }), row.count > 0 else { return nil }

                let lowerBound = runningTotal
                runningTotal += row.count
                return StackedSeriesCount(
                    bucketStart: bucket,
                    series: series,
                    count: row.count,
                    lowerBound: lowerBound,
                    upperBound: runningTotal
                )
            }
        }
    }

    var tokenYAxisUpperBound: Int {
        let peak = tokenDataBuckets.map { bucket in
            tokenSeriesWithData
                .filter { $0.bucketStart == bucket }
                .reduce(0) { $0 + $1.count }
        }.max() ?? 0

        let step: Int
        switch peak {
        case ...1_000: step = 100
        case ...10_000: step = 1_000
        case ...100_000: step = 10_000
        default: step = 100_000
        }
        return max(step, Int(ceil(Double(peak) / Double(step))) * step)
    }

    var chartBuckets: [Date] {
        let calendar = Calendar.current
        return allBuckets(
            from: bucketCutoff(calendar: calendar),
            through: bucketStart(for: Date(), calendar: calendar),
            calendar: calendar
        )
    }

    var actionChartDomain: ClosedRange<Date> {
        chartDomain(for: actionDataBuckets)
    }

    var tokenChartDomain: ClosedRange<Date> {
        chartDomain(for: tokenDataBuckets)
    }

    private func chartDomain(for buckets: [Date]) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let first = buckets.first ?? bucketStart(for: Date(), calendar: calendar)
        let last = buckets.last ?? first
        let component: Calendar.Component = granularity == .daily ? .day : .weekOfYear
        let next = calendar.date(byAdding: component, value: 1, to: last) ?? last
        let halfBucket = next.timeIntervalSince(last) / 2
        return first.addingTimeInterval(-halfBucket)...last.addingTimeInterval(halfBucket)
    }

    func actionRows(for bucket: Date) -> [SeriesCount] {
        actionCountsBySeries.filter { $0.bucketStart == bucket && $0.count > 0 }
    }

    func tokenRows(for bucket: Date) -> [SeriesCount] {
        tokenCountsBySeries.filter { $0.bucketStart == bucket }
    }

    private func bucketedCounts(keyed seriesKey: (ConversionEvent) -> String) -> [SeriesCount] {
        let calendar = Calendar.current
        let cutoff = bucketCutoff(calendar: calendar)
        var totals: [Date: [String: Int]] = [:]
        let series = activeActionSeries

        for bucket in chartBuckets {
            totals[bucket] = Dictionary(uniqueKeysWithValues: series.map { ($0, 0) })
        }

        for event in events where event.timestamp >= cutoff {
            let bucket = bucketStart(for: event.timestamp, calendar: calendar)
            totals[bucket, default: [:]][seriesKey(event), default: 0] += 1
        }

        return totals.flatMap { bucket, series in
            series.map { SeriesCount(bucketStart: bucket, series: $0.key, count: $0.value) }
        }.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return $0.series < $1.series
        }
    }

    private func allBuckets(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var buckets: [Date] = []
        var current = bucketStart(for: start, calendar: calendar)
        let endBucket = bucketStart(for: end, calendar: calendar)
        while current <= endBucket {
            buckets.append(current)
            switch granularity {
            case .daily:
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            case .weekly:
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: current) else { break }
                current = next
            }
        }
        return buckets
    }

    private func bucketCutoff(calendar: Calendar) -> Date {
        switch granularity {
        case .daily:
            return calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: Date())) ?? Date()
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: -11, to: startOfWeek(Date(), calendar: calendar)) ?? Date()
        }
    }

    private func bucketStart(for date: Date, calendar: Calendar) -> Date {
        switch granularity {
        case .daily: return calendar.startOfDay(for: date)
        case .weekly: return startOfWeek(date, calendar: calendar)
        }
    }

    private func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}
