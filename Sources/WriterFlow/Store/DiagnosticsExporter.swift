import AppKit
import Foundation

/// Stage 4.4 crash reporting: local-only diagnostics collection. Never uploads anything —
/// gathers a plain-text bundle the user can inspect and choose to send themselves (e.g.
/// attach to a bug report), triggered only by an explicit "Share Diagnostics" click.
enum DiagnosticsExporter {
    /// Builds a diagnostics `.txt` bundle and returns its contents. Includes: app/OS version,
    /// the last few WriterFlow crash reports macOS already collected under
    /// `~/Library/Logs/DiagnosticReports/`, and `compatibility.json` (per-app AX success/fail
    /// counters — no field content, just counts).
    static func buildReport() -> String {
        var sections: [String] = []

        sections.append(systemSection())
        sections.append(compatibilitySection())
        sections.append(crashReportsSection())

        return sections.joined(separator: "\n\n" + String(repeating: "-", count: 60) + "\n\n")
    }

    /// Presents a save panel and writes the report if the user confirms. Never sends
    /// anything automatically or over the network — purely a local file the user controls.
    @MainActor
    static func exportWithSavePanel() {
        let report = buildReport()

        let panel = NSSavePanel()
        panel.title = "Share Diagnostics"
        panel.nameFieldStringValue = "WriterFlow-diagnostics-\(dateStamp()).txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            ErrorToast.show("Diagnostics saved to \(url.lastPathComponent)", style: .success)
        } catch {
            Log.store.error("DiagnosticsExporter: write failed: \(String(describing: error), privacy: .public)")
            ErrorToast.show("Couldn't save diagnostics file.")
        }
    }

    // MARK: - Sections

    private static func systemSection() -> String {
        let bundle = Bundle.main
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        WriterFlow Diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        App version: \(appVersion) (\(build))
        macOS: \(os)
        """
    }

    private static func compatibilitySection() -> String {
        let url = AzureModelsConfig.appSupportURL.appendingPathComponent("compatibility.json")
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return "Per-app compatibility diagnostics: none recorded yet."
        }
        return "Per-app compatibility diagnostics (read/write/context success counts, no field content):\n\(text)"
    }

    /// macOS writes a `.ips`/`.crash` file here on every crash, independent of whether
    /// WriterFlow ships its own reporter — surface the most recent few rather than
    /// building separate crash-capture machinery.
    private static func crashReportsSection() -> String {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/DiagnosticReports")
        guard let dir,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else {
            return "Crash reports: none found."
        }

        let recent = entries
            .filter { $0.lastPathComponent.hasPrefix("WriterFlow") }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhs > rhs
            }
            .prefix(3)

        guard !recent.isEmpty else {
            return "Crash reports: none found in ~/Library/Logs/DiagnosticReports."
        }

        let bodies = recent.map { url -> String in
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? "(couldn't read \(url.lastPathComponent))"
            return "=== \(url.lastPathComponent) ===\n\(contents)"
        }
        return "Recent crash reports:\n\n" + bodies.joined(separator: "\n\n")
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
