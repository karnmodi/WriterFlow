import Foundation

enum Prompts {
    static func instruction(for action: WritingAction) -> String {
        switch action {
        case .elaborate:
            return """
            Expand the text into fuller, clearer writing. Keep the original intent and tone. \
            Add useful detail but do not invent facts.
            """
        case .formal:
            return """
            Rewrite in a professional, formal register suitable for email or business communication. \
            Keep the meaning; improve clarity and polish.
            """
        case .casual:
            return """
            Rewrite in a friendly, natural, casual register suitable for chat or messaging. \
            Keep it concise and human.
            """
        case .fixGrammar:
            return """
            Fix grammar, spelling, and punctuation only. Make minimal wording changes. \
            Preserve the author's voice and meaning.
            """
        case .reply, .custom:
            return ""
        }
    }

    static let systemPreamble = """
    You are a writing assistant embedded in macOS. Rewrite the user's text per the action instruction. \
    Output ONLY the rewritten text — no quotes, labels, explanations, or markdown fences. \
    Match the input language.
    """
}
