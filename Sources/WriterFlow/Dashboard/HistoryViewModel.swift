import Foundation
import GRDB
import Combine

/// Reactive History tab state — reads `conversions` via GRDB `ValueObservation`
/// so new events (and deletes/purges) appear without a manual refresh.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var events: [ConversionEvent] = []
    @Published var searchText: String = ""
    @Published var appFilter: String?
    @Published var actionFilter: String?
    @Published var acceptedFilter: Bool?
    @Published var selectedEventID: String?

    private var observationTask: Task<Void, Never>?

    var availableApps: [String] {
        Array(Set(events.compactMap(\.appBundleID))).sorted()
    }

    var availableActions: [String] {
        Array(Set(events.map(\.action))).sorted()
    }

    var filteredEvents: [ConversionEvent] {
        events.filter { event in
            if let appFilter, event.appBundleID != appFilter { return false }
            if let actionFilter, event.action != actionFilter { return false }
            if let acceptedFilter, event.accepted != acceptedFilter { return false }
            if !searchText.isEmpty {
                let needle = searchText.lowercased()
                guard event.input.lowercased().contains(needle)
                    || event.output.lowercased().contains(needle)
                else { return false }
            }
            return true
        }
    }

    /// `filteredEvents` grouped by calendar day, most recent day first.
    var groupedEvents: [(day: Date, events: [ConversionEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        return groups.keys.sorted(by: >).map { day in (day: day, events: groups[day]!.sorted { $0.timestamp > $1.timestamp }) }
    }

    init(db: DatabaseQueue = WriterFlowDatabase.shared) {
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try ConversionEvent.order(Column("timestamp").desc).fetchAll(db)
            }
            do {
                for try await events in observation.values(in: db) {
                    self.events = events
                }
            } catch {
                Log.store.error("History ValueObservation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func clearAllHistory() {
        Task { await ConversionEventStore.shared.deleteAll() }
    }
}
