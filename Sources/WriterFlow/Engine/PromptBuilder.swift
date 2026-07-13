import Foundation

enum PromptBuilder {
    struct BuiltPrompt: Sendable {
        let system: String
        let user: String
    }

    static func build(action: WritingAction, snapshot: FieldSnapshot) -> BuiltPrompt {
        let workingText = snapshot.actionText
        let toneBias = toneBias(for: snapshot.appBundleID)
        let voicePlaceholder = "" // Phase 3 injects voice profile here.

        var system = Prompts.systemPreamble
        if !voicePlaceholder.isEmpty {
            system += "\nVoice profile: \(voicePlaceholder)"
        }
        if let toneBias {
            system += "\nApp context: \(toneBias)"
        }
        system += "\nAction instruction: \(Prompts.instruction(for: action))"

        let user = "[ACTION=\(actionTag(action))]\n\(workingText)"
        return BuiltPrompt(system: system, user: user)
    }

    private static func actionTag(_ action: WritingAction) -> String {
        switch action {
        case .elaborate: return "elaborate"
        case .formal: return "formal"
        case .casual: return "casual"
        case .fixGrammar: return "grammar"
        case .reply: return "reply"
        case .custom: return "custom"
        }
    }

    private static func toneBias(for bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        let id = bundleID.lowercased()
        if id.contains("mail") || id.contains("chrome") || id.contains("safari") {
            return "Email/web compose — lean slightly formal unless the draft is clearly casual."
        }
        if id.contains("slack") || id.contains("whatsapp") || id.contains("telegram") {
            return "Chat app — lean casual and concise."
        }
        return "General text field — match the draft's register."
    }
}
