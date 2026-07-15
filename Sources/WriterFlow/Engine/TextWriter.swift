import Foundation

enum TextWriter {
    /// Write `replacement` into the focused field via the unified TextInserter pipeline.
    static func replace(
        pid: pid_t,
        range: NSRange,
        with replacement: String,
        bundleID: String? = nil,
        site: String? = nil,
        role: String? = nil
    ) async -> WriteResult {
        await TextInserter.replace(
            pid: pid,
            range: range,
            with: replacement,
            bundleID: bundleID,
            site: site,
            role: role
        )
    }
}
