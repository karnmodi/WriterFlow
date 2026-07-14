import Combine
import Foundation
import GRDB

/// Reactive CRUD for `memory_notes` (snippets/facts + learned style notes) — Stage 3.3.
/// Same reactive-GRDB pattern as `HistoryViewModel`: a `ValueObservation` stream keeps
/// `notes` current, and since this runs on `@MainActor`, `ActionEngine` can read `notes`
/// synchronously when building a prompt (no async plumbing needed at the prompt call sites).
@MainActor
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()

    @Published private(set) var notes: [MemoryNote] = []

    private let db: DatabaseQueue
    private var observationTask: Task<Void, Never>?

    init(db: DatabaseQueue = WriterFlowDatabase.shared) {
        self.db = db
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try MemoryNote.order(Column("updatedAt").desc).fetchAll(db)
            }
            do {
                for try await notes in observation.values(in: db) {
                    self.notes = notes
                }
            } catch {
                Log.store.error("MemoryNote ValueObservation failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    @discardableResult
    func add(kind: MemoryNote.Kind, text: String) async -> MemoryNote {
        let note = MemoryNote(kind: kind, text: text)
        do {
            try await db.write { db in try note.insert(db) }
        } catch {
            Log.store.error("MemoryNote insert failed: \(String(describing: error), privacy: .public)")
        }
        return note
    }

    func setEnabled(id: String, enabled: Bool) async {
        do {
            try await db.write { db in
                guard var note = try MemoryNote.fetchOne(db, key: id) else { return }
                note.enabled = enabled
                note.updatedAt = Date()
                try note.update(db)
            }
        } catch {
            Log.store.error("MemoryNote update failed: \(String(describing: error), privacy: .public)")
        }
    }

    func updateText(id: String, text: String) async {
        do {
            try await db.write { db in
                guard var note = try MemoryNote.fetchOne(db, key: id) else { return }
                note.text = text
                note.updatedAt = Date()
                try note.update(db)
            }
        } catch {
            Log.store.error("MemoryNote update failed: \(String(describing: error), privacy: .public)")
        }
    }

    func delete(id: String) async {
        do {
            try await db.write { db in
                _ = try MemoryNote.deleteOne(db, key: id)
            }
        } catch {
            Log.store.error("MemoryNote delete failed: \(String(describing: error), privacy: .public)")
        }
    }
}
