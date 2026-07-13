import Foundation

/// Per-bundle read/write success counters, persisted to
/// `~/Library/Application Support/WriterFlow/compatibility.json`.
/// Used later for the dashboard's diagnostics tab.
actor CompatibilityMap {
    struct Entry: Codable, Sendable {
        var readOK: Int = 0
        var readFail: Int = 0
        var writeOK: Int = 0
        var writeFail: Int = 0
    }

    static let shared = CompatibilityMap()

    private let url: URL
    private var entries: [String: Entry]
    private var writeTask: Task<Void, Never>?

    init() {
        self.url = CompatibilityMap.defaultURL()
        self.entries = CompatibilityMap.load(url: url)
    }

    func recordRead(bundleID: String?, ok: Bool) {
        guard let bundleID else { return }
        var entry = entries[bundleID] ?? Entry()
        if ok { entry.readOK += 1 } else { entry.readFail += 1 }
        entries[bundleID] = entry
        scheduleWrite()
    }

    func recordWrite(bundleID: String?, ok: Bool) {
        guard let bundleID else { return }
        var entry = entries[bundleID] ?? Entry()
        if ok { entry.writeOK += 1 } else { entry.writeFail += 1 }
        entries[bundleID] = entry
        scheduleWrite()
    }

    func snapshot() -> [String: Entry] { entries }

    // MARK: - Persistence

    private func scheduleWrite() {
        writeTask?.cancel()
        let payload = entries
        let target = url
        writeTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            try? CompatibilityMap.write(payload, to: target)
        }
    }

    private static func load(url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func write(_ payload: [String: Entry], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    private static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("WriterFlow/compatibility.json")
    }
}
