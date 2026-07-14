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

    /// The product's north-star metric — nil (not 0%) when there's no data yet, so the UI
    /// can show "No actions yet" instead of a misleading 0%.
    var acceptanceRate: Double? {
        guard !events.isEmpty else { return nil }
        return Double(events.filter(\.accepted).count) / Double(events.count)
    }

    var totalTokensIn: Int { events.reduce(0) { $0 + ($1.tokensIn ?? 0) } }
    var totalTokensOut: Int { events.reduce(0) { $0 + ($1.tokensOut ?? 0) } }

    /// Rough estimate from the editable pricing table in `models.json` (Settings tab) —
    /// intentionally labeled "estimated" in the UI, not a billing-accurate figure.
    var estimatedCostUSD: Double {
        events.reduce(0.0) { partial, event in
            guard let model = event.model else { return partial }
            let pricing = modelsConfig.pricing(for: model)
            let inCost = Double(event.tokensIn ?? 0) / 1_000_000 * pricing.inputPerMillion
            let outCost = Double(event.tokensOut ?? 0) / 1_000_000 * pricing.outputPerMillion
            return partial + inCost + outCost
        }
    }

    // MARK: - Chart data

    /// One row per (bucket, action) for a stacked bar chart of action-type volume over time.
    var actionCountsBySeries: [SeriesCount] {
        bucketedCounts(keyed: { $0.action })
    }

    /// One row per (bucket, "Input"/"Output") for a stacked bar chart of token volume over time.
    var tokenCountsBySeries: [SeriesCount] {
        let calendar = Calendar.current
        let cutoff = bucketCutoff(calendar: calendar)
        var totals: [Date: [String: Int]] = [:]
        for event in events where event.timestamp >= cutoff {
            let bucket = bucketStart(for: event.timestamp, calendar: calendar)
            totals[bucket, default: [:]]["Input", default: 0] += event.tokensIn ?? 0
            totals[bucket, default: [:]]["Output", default: 0] += event.tokensOut ?? 0
        }
        return totals.flatMap { bucket, series in
            series.map { SeriesCount(bucketStart: bucket, series: $0.key, count: $0.value) }
        }.sorted { $0.bucketStart < $1.bucketStart }
    }

    private func bucketedCounts(keyed seriesKey: (ConversionEvent) -> String) -> [SeriesCount] {
        let calendar = Calendar.current
        let cutoff = bucketCutoff(calendar: calendar)
        var totals: [Date: [String: Int]] = [:]
        for event in events where event.timestamp >= cutoff {
            let bucket = bucketStart(for: event.timestamp, calendar: calendar)
            totals[bucket, default: [:]][seriesKey(event), default: 0] += 1
        }
        return totals.flatMap { bucket, series in
            series.map { SeriesCount(bucketStart: bucket, series: $0.key, count: $0.value) }
        }.sorted { $0.bucketStart < $1.bucketStart }
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
