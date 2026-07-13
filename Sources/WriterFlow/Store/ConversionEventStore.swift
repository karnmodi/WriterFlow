import Foundation

struct ConversionEvent: Codable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let appBundleID: String?
    let action: String
    let input: String
    var output: String
    var accepted: Bool

    init(
        appBundleID: String?,
        action: WritingAction,
        input: String,
        output: String = "",
        accepted: Bool = false
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.appBundleID = appBundleID
        self.action = action.title
        self.input = input
        self.output = output
        self.accepted = accepted
    }
}

/// Append-only JSON-lines log until Phase 3 migrates to GRDB.
actor ConversionEventStore {
    static let shared = ConversionEventStore()

    private let fileURL: URL
    private let encoder = JSONEncoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        fileURL = AzureModelsConfig.appSupportURL.appendingPathComponent("conversions.jsonl")
        try? FileManager.default.createDirectory(
            at: AzureModelsConfig.appSupportURL,
            withIntermediateDirectories: true
        )
    }

    func append(_ event: ConversionEvent) {
        guard let line = try? encoder.encode(event),
              var text = String(data: line, encoding: .utf8)
        else { return }
        text += "\n"
        guard let data = text.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
        Log.store.info("ConversionEvent logged action=\(event.action, privacy: .public)")
    }
}
