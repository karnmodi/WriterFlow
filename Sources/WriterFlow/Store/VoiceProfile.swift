import Foundation

/// Manual voice profile — free-text style description plus structured
/// signature fields. Persisted as JSON in `SettingsStore` (single record,
/// not a list, so it doesn't need its own GRDB table).
struct VoiceProfile: Codable, Sendable, Equatable {
    var styleText: String = ""
    var signOffName: String = ""
    var role: String = ""
    var company: String = ""
    var greeting: String = ""

    var isEmpty: Bool {
        [styleText, signOffName, role, company, greeting].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
