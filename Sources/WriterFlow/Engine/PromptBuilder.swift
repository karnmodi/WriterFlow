import Foundation

enum PromptBuilder {
    enum Phase: Sendable {
        case analyze
        case finalize(answers: [(question: String, answer: String)])
    }

    struct BuiltPrompt: Sendable {
        let system: String
        let user: String
    }

    /// Stage 3.3 personalization — resolved once per action in `ActionEngine` (it's
    /// `@MainActor`, same as the stores) and threaded through so `PromptBuilder` itself
    /// stays a pure function of its arguments.
    struct PersonalizationContext: Sendable {
        let memoryBlock: String
        let toneOverride: String?

        static let none = PersonalizationContext(memoryBlock: "", toneOverride: nil)
    }

    static func build(
        action: WritingAction,
        snapshot: FieldSnapshot,
        conversationContext: String? = nil,
        customInstruction: String? = nil,
        promptBuilderPhase: Phase = .analyze,
        personalization: PersonalizationContext = .none,
        variantIndex: Int? = nil
    ) -> BuiltPrompt {
        let fieldText = snapshot.actionText
        let briefFromBox = customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let workingText: String
        if action == .promptBuilder,
           fieldText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !briefFromBox.isEmpty {
            workingText = briefFromBox
        } else {
            workingText = fieldText
        }

        let site = AppAdapterRegistry.siteLabel(
            bundleID: snapshot.appBundleID,
            windowTitle: snapshot.windowTitle
        )
        let toneBias = personalization.toneOverride ?? AppAdapterRegistry.adapter(for: snapshot.appBundleID).toneBias
        let conversationContext = Prompts.trimmedConversation(conversationContext, for: action)

        var system: String
        switch action {
        case .reply:
            system = Prompts.replySystemPreamble
        case .promptBuilder:
            system = Prompts.promptBuilderSystemPreamble
        default:
            system = Prompts.systemPreamble
        }
        if !personalization.memoryBlock.isEmpty {
            system += "\nVoice profile & memory:\n\(personalization.memoryBlock)"
        }
        system += "\nApp context: \(toneBias)"
        system += "\nAction instruction: \(Prompts.instruction(for: action))"
        if action == .fixGrammar {
            system += "\nStrict rule: change only clear errors in spelling, grammar, punctuation, or capitalization. Never rephrase."
        }
        if let variantIndex {
            system += "\n\(Prompts.variantInstruction(action: action, index: variantIndex))"
        }

        let contextual = Prompts.shouldApplyContextualTransform(
            action: action,
            conversationContext: conversationContext,
            site: site
        )
        let background = Prompts.shouldApplyBackgroundContext(
            action: action,
            conversationContext: conversationContext
        )
        if contextual {
            system += "\n\(Prompts.contextualTransformInstruction(site: site, action: action))"
        } else if background {
            system += "\n\(Prompts.backgroundContextInstruction(action: action))"
        }

        if action == .reply {
            system += "\nPlatform: \(site ?? "unknown")"
            system += "\n\(Prompts.replyInstruction(for: site))"
            if conversationContext == nil || conversationContext?.isEmpty == true {
                system += "\nNote: No conversation thread was captured — draft the best reply you can from MY DRAFT/INTENT alone."
            } else {
                system += "\nThe CONVERSATION block is the primary source of truth — the reply must reflect specific thread content, not just restate MY DRAFT/INTENT."
            }
            system += "\nMatch the conversation's language (e.g. Hindi/Hinglish input gets a Hindi/Hinglish reply)."
        }
        if action == .promptBuilder {
            let hasConversation = !(conversationContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let continuation = hasConversation || AppAdapterRegistry.isLLMChatSite(site)
            system += "\n\(Prompts.promptBuilderModeInstruction(continuation: continuation))"

            switch promptBuilderPhase {
            case .analyze:
                system += "\n\(Prompts.promptBuilderAnalyzeOutputFormat)"
            case .finalize:
                system += "\n\(Prompts.promptBuilderFinalizeInstruction)"
                system += "\n\(Prompts.promptBuilderFinalizeOutputFormat)"
            }

            if hasConversation {
                system += "\nCONVERSATION is prior chat above the compose field — use it to understand the thread; the ---PROMPT--- block should still follow BRIEF length and intent, not dump the whole thread."
            }
        }

        var user = "[ACTION=\(actionTag(action))]"
        if let conversationContext, !conversationContext.isEmpty {
            user += "\nCONVERSATION:\n\(conversationContext)"
        }
        if action == .custom, let customInstruction, !customInstruction.isEmpty {
            user += "\nINSTRUCTION: \(customInstruction)"
        }
        switch action {
        case .reply:
            user += "\nMY DRAFT/INTENT:\n\(workingText)"
        case .promptBuilder:
            user += "\nBRIEF:\n\(workingText)"
            if case .finalize(let answers) = promptBuilderPhase, !answers.isEmpty {
                user += "\nANSWERS:"
                for pair in answers {
                    user += "\nQ: \(pair.question)\nA: \(pair.answer)"
                }
            }
        case .custom:
            user += "\nDRAFT:\n\(workingText)"
        default:
            if background {
                user += "\nDRAFT:\n\(workingText)"
            } else {
                user += "\n\(workingText)"
            }
        }
        return BuiltPrompt(system: system, user: user)
    }

    private static func actionTag(_ action: WritingAction) -> String {
        switch action {
        case .elaborate: return "elaborate"
        case .formal: return "formal"
        case .casual: return "casual"
        case .fixGrammar: return "grammar"
        case .reply: return "reply"
        case .promptBuilder: return "prompt_builder"
        case .custom: return "custom"
        }
    }
}
