import Foundation

/// Parses a simple KEY=VALUE `.env` file. Keys and values are trimmed;
/// lines with spaces around `=` are handled (e.g. `API_KEY_GPT_5-4_Pro = xxx`).
enum DotEnvLoader {
    static func load(from url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Search upward from `start` for a `.env` file (up to `maxDepth` parents).
    static func findEnvFile(startingAt start: URL, maxDepth: Int = 6) -> URL? {
        var dir = start
        for _ in 0...maxDepth {
            let candidate = dir.appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Merged map: process environment overrides file values.
    static func loadMerged(fileURL: URL?) -> [String: String] {
        var merged = fileURL.flatMap { load(from: $0) } ?? [:]
        for (key, value) in ProcessInfo.processInfo.environment where !value.isEmpty {
            merged[key] = value
        }
        return merged
    }

    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            out[key] = value
        }
        return out
    }
}
