import Foundation

/// Combines the voice profile, enabled memory notes, and a resolved per-app rule into the
/// text `PromptBuilder` injects into every system prompt. Pure/synchronous — callers pass in
/// already-loaded state (`ActionEngine` reads `SettingsStore`/`MemoryStore`/`AppRuleStore`
/// directly since they're all `@MainActor`, same actor `ActionEngine` runs on).
enum MemoryPromptBuilder {
    struct Result: Sendable {
        let block: String
        /// Notes dropped for being over the token budget — oldest (by `updatedAt`) first.
        let excludedCount: Int
    }

    /// ~600 tokens per the Stage 3.3 spec; ~4 chars/token is a rough but serviceable estimate
    /// for English prose (no tokenizer dependency needed for a soft budget like this).
    static let tokenBudget = 600
    private static let charsPerToken = 4

    static func build(profile: VoiceProfile, notes: [MemoryNote], appRule: AppRule?) -> Result {
        var profileLines: [String] = []
        func addIfPresent(_ label: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            profileLines.append("\(label): \(trimmed)")
        }
        addIfPresent("Writing style", profile.styleText)
        addIfPresent("Sign as", profile.signOffName)
        addIfPresent("Role", profile.role)
        addIfPresent("Company", profile.company)
        addIfPresent("Preferred greeting/sign-off", profile.greeting)
        if let appRule {
            addIfPresent("App-specific signature", appRule.signature ?? "")
            addIfPresent("App-specific instruction", appRule.customInstruction ?? "")
        }
        let profileBlock = profileLines.joined(separator: "\n")

        let budgetChars = tokenBudget * charsPerToken
        var remaining = max(0, budgetChars - profileBlock.count)

        // Prioritize the most recently updated notes when trimming to budget, then
        // present the kept notes oldest-first so the prompt reads chronologically.
        let enabledNewestFirst = notes.filter(\.enabled).sorted { $0.updatedAt > $1.updatedAt }
        var kept: [MemoryNote] = []
        var excludedCount = 0
        for note in enabledNewestFirst {
            let cost = note.text.count + 12
            if cost <= remaining {
                kept.append(note)
                remaining -= cost
            } else {
                excludedCount += 1
            }
        }
        let orderedKept = kept.sorted { $0.updatedAt < $1.updatedAt }

        var lines = profileLines
        for note in orderedKept {
            let label: String
            switch note.kind {
            case .style: label = "Style note"
            case .fact: label = "Fact"
            case .snippet: label = "Snippet"
            }
            lines.append("\(label): \(note.text)")
        }

        return Result(block: lines.joined(separator: "\n"), excludedCount: excludedCount)
    }
}
