import Combine
import Foundation
import GRDB

/// Reactive CRUD for `app_rules` (per-app tone/signature/instruction/exclude) — Stage 3.3.
/// `@MainActor`-isolated like `MemoryStore`, so `ActionEngine` and `OverlayController` can
/// read `rules` synchronously.
@MainActor
final class AppRuleStore: ObservableObject {
    static let shared = AppRuleStore()

    @Published private(set) var rules: [AppRule] = []

    private let db: DatabaseQueue
    private var observationTask: Task<Void, Never>?

    init(db: DatabaseQueue = WriterFlowDatabase.shared) {
        self.db = db
        observationTask = Task {
            let observation = ValueObservation.tracking { db in
                try AppRule.order(Column("bundleOrSite")).fetchAll(db)
            }
            do {
                for try await rules in observation.values(in: db) {
                    self.rules = rules
                }
            } catch {
                Log.store.error("AppRule ValueObservation failed: \(String(describing: error), privacy: .public)")
            }
        }
        Task { await Self.seedDefaultsIfNeeded(db: self.db) }
    }

    deinit {
        observationTask?.cancel()
    }

    /// Site-keyed rule wins when a site label is known (e.g. "gmail" inside Chrome);
    /// falls back to the app's bundle id (native/Electron apps with no site concept).
    func rule(forBundleID bundleID: String?, site: String?) -> AppRule? {
        if let site, let match = rules.first(where: { $0.bundleOrSite == site }) {
            return match
        }
        if let bundleID, let match = rules.first(where: { $0.bundleOrSite == bundleID }) {
            return match
        }
        return nil
    }

    /// Icon-gating check. Bundle-id only: a browser's window title (needed to resolve a
    /// per-site label like "gmail") isn't available yet at focus time, so exclusion can
    /// only be scoped to a whole app, not one site inside a shared-bundle-ID browser.
    func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return rules.first(where: { $0.bundleOrSite == bundleID })?.excluded ?? false
    }

    func upsert(_ rule: AppRule) async {
        do {
            try await db.write { db in try rule.save(db) }
        } catch {
            Log.store.error("AppRule upsert failed: \(String(describing: error), privacy: .public)")
        }
    }

    func delete(bundleOrSite: String) async {
        do {
            try await db.write { db in
                _ = try AppRule.deleteOne(db, key: bundleOrSite)
            }
        } catch {
            Log.store.error("AppRule delete failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// One-time seed from Phase 2's `AppAdapter` tone defaults so the Personalization
    /// tab's per-app table isn't empty on first open. Idempotent: skipped once any
    /// `app_rules` row exists (including user-deleted-back-to-empty, which is fine —
    /// there's nothing destructive about re-seeding being skipped).
    private static func seedDefaultsIfNeeded(db: DatabaseQueue) async {
        let defaultsKey = "wf.appRulesSeeded"
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        do {
            let seeds: [(site: String, tone: String)] = [
                ("gmail", "Email/web compose — lean slightly formal unless the draft is clearly casual."),
                ("outlook", "Email/web compose — lean slightly formal unless the draft is clearly casual."),
                ("linkedin", "Email/web compose — lean slightly formal unless the draft is clearly casual."),
                ("whatsapp-web", "Chat app — lean casual and concise."),
                ("whatsapp-desktop", "Chat app — lean casual and concise."),
                ("slack", "Chat app — lean casual and concise."),
                ("telegram", "Chat app — lean casual and concise."),
                ("notion", "Notes/docs — match the draft's register."),
                ("cursor", "Cursor IDE chat — write the next user message in the thread; technical and concise."),
                ("terminal", "Terminal input — keep it terse; likely a command, commit message, or note.")
            ]
            try await db.write { db in
                for seed in seeds {
                    let rule = AppRule(bundleOrSite: seed.site, tone: seed.tone)
                    try rule.insert(db, onConflict: .ignore)
                }
            }
            UserDefaults.standard.set(true, forKey: defaultsKey)
        } catch {
            Log.store.error("AppRule seed failed: \(String(describing: error), privacy: .public)")
        }
    }
}
