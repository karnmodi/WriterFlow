import XCTest
@testable import WriterFlow

final class PromptBuilderBuildTests: XCTestCase {
    private let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    private let sampleConversation = """
    User: Fix the prompt builder in Prompts.swift
    Assistant: I updated the instruction block.
    """

    private func cursorSnapshot(text: String = "make this clearer") -> FieldSnapshot {
        FieldSnapshot(
            fullText: text,
            selectedText: "",
            selectedRange: NSRange(location: 0, length: 0),
            role: "AXTextArea",
            appBundleID: cursorBundleID,
            windowTitle: "WriterFlow — Prompts.swift"
        )
    }

    private func textEditSnapshot(text: String = "hello world") -> FieldSnapshot {
        FieldSnapshot(
            fullText: text,
            selectedText: "",
            selectedRange: NSRange(location: 0, length: 0),
            role: "AXTextArea",
            appBundleID: "com.apple.TextEdit",
            windowTitle: "Untitled"
        )
    }

    // MARK: - Context extraction policy

    func testShouldExtractConversationForAllActionsInCursor() {
        for action in WritingAction.allCases {
            XCTAssertTrue(
                Prompts.shouldExtractConversation(for: action, site: "cursor"),
                "Expected context extraction for \(action.title) in Cursor"
            )
        }
    }

    func testShouldExtractConversationOnlyForContextActionsOutsideLLMChat() {
        XCTAssertTrue(Prompts.shouldExtractConversation(for: .reply, site: nil))
        XCTAssertTrue(Prompts.shouldExtractConversation(for: .custom, site: "gmail"))
        XCTAssertTrue(Prompts.shouldExtractConversation(for: .promptBuilder, site: "notion"))

        XCTAssertFalse(Prompts.shouldExtractConversation(for: .elaborate, site: "gmail"))
        XCTAssertFalse(Prompts.shouldExtractConversation(for: .formal, site: nil))
        XCTAssertFalse(Prompts.shouldExtractConversation(for: .casual, site: "slack"))
        XCTAssertFalse(Prompts.shouldExtractConversation(for: .fixGrammar, site: "notion"))
    }

    func testContextualTransformIsReplyOnly() {
        XCTAssertTrue(
            Prompts.shouldApplyContextualTransform(
                action: .reply,
                conversationContext: sampleConversation,
                site: "gmail"
            )
        )
        XCTAssertTrue(
            Prompts.shouldApplyContextualTransform(
                action: .reply,
                conversationContext: nil,
                site: "cursor"
            )
        )
        XCTAssertFalse(
            Prompts.shouldApplyContextualTransform(
                action: .formal,
                conversationContext: sampleConversation,
                site: "cursor"
            )
        )
        XCTAssertFalse(
            Prompts.shouldApplyContextualTransform(
                action: .elaborate,
                conversationContext: sampleConversation,
                site: "gmail"
            )
        )
        XCTAssertFalse(
            Prompts.shouldApplyContextualTransform(
                action: .custom,
                conversationContext: sampleConversation,
                site: "cursor"
            )
        )
    }

    func testBackgroundContextAppliesToNonReplyWhenConversationPresent() {
        XCTAssertTrue(
            Prompts.shouldApplyBackgroundContext(
                action: .formal,
                conversationContext: sampleConversation
            )
        )
        XCTAssertTrue(
            Prompts.shouldApplyBackgroundContext(
                action: .custom,
                conversationContext: sampleConversation
            )
        )
        XCTAssertFalse(
            Prompts.shouldApplyBackgroundContext(
                action: .reply,
                conversationContext: sampleConversation
            )
        )
        XCTAssertFalse(
            Prompts.shouldApplyBackgroundContext(
                action: .formal,
                conversationContext: nil
            )
        )
    }

    // MARK: - Background context for rewrite actions

    func testFormalWithConversationUsesBackgroundOnlyNotContextualTransform() {
        let built = PromptBuilder.build(
            action: .formal,
            snapshot: cursorSnapshot(text: "please fix ActionEngine.swift"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Background context"))
        XCTAssertTrue(built.system.contains("not a reply to CONVERSATION"))
        XCTAssertTrue(built.system.contains("Change register only"))
        XCTAssertFalse(built.system.contains("Contextual transform"))
        XCTAssertFalse(built.system.contains("Adaptive structure"))
        XCTAssertFalse(built.system.contains("Treat DRAFT/NEXT MESSAGE"))
        XCTAssertTrue(built.user.contains("CONVERSATION:"))
        XCTAssertTrue(built.user.contains("DRAFT:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }

    func testCasualWithConversationUsesBackgroundOnly() {
        let built = PromptBuilder.build(
            action: .casual,
            snapshot: cursorSnapshot(text: "please fix ActionEngine.swift"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Background context"))
        XCTAssertFalse(built.system.contains("Contextual transform"))
        XCTAssertTrue(built.user.contains("DRAFT:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }

    func testFixGrammarWithConversationKeepsStrictNoRephraseAndBackgroundOnly() {
        let built = PromptBuilder.build(
            action: .fixGrammar,
            snapshot: cursorSnapshot(text: "fix teh prompt builder"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Background context"))
        XCTAssertTrue(built.system.contains("Grammar-only"))
        XCTAssertTrue(built.system.contains("Never rephrase"))
        XCTAssertFalse(built.system.contains("Contextual transform"))
        XCTAssertTrue(built.user.contains("DRAFT:"))
    }

    func testElaborateWithConversationUsesBackgroundNotNextMessageFraming() {
        let built = PromptBuilder.build(
            action: .elaborate,
            snapshot: cursorSnapshot(text: "add tests for prompt builder"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Background context"))
        XCTAssertFalse(built.system.contains("Contextual transform"))
        XCTAssertFalse(built.system.contains("Adaptive structure"))
        XCTAssertTrue(built.user.contains("DRAFT:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }

    func testReplyRetainsContextualTransformAndSpecializedLabels() {
        let built = PromptBuilder.build(
            action: .reply,
            snapshot: cursorSnapshot(text: "say tests are done"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.user.contains("MY DRAFT/INTENT:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.system.contains("Contextual transform"))
        XCTAssertTrue(built.system.contains("Adaptive structure"))
        XCTAssertFalse(built.system.contains("Background context (do not reply"))
    }

    func testCustomUsesBackgroundContextAndDraftLabel() {
        let built = PromptBuilder.build(
            action: .custom,
            snapshot: cursorSnapshot(text: "rewrite with bullets"),
            conversationContext: sampleConversation,
            customInstruction: "use three bullets max"
        )

        XCTAssertTrue(built.user.contains("INSTRUCTION: use three bullets max"))
        XCTAssertTrue(built.user.contains("DRAFT:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.system.contains("Background context"))
        XCTAssertFalse(built.system.contains("Contextual transform"))
    }

    func testPromptBuilderRetainsBriefLabelWithoutContextualTransform() {
        let built = PromptBuilder.build(
            action: .promptBuilder,
            snapshot: cursorSnapshot(text: "help me ask for a refactor plan"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.user.contains("BRIEF:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.system.contains("---CLARIFY---"))
        XCTAssertTrue(built.system.contains("---PROMPT---"))
        XCTAssertTrue(built.system.contains("Mode: CONTINUATION"))
        XCTAssertTrue(built.system.contains("Background context"))
        XCTAssertFalse(built.system.contains("Contextual transform"))
    }

    func testPromptBuilderFinalizeIncludesAnswersAndFinalizeInstruction() {
        let answers = [(question: "Tone?", answer: "Formal")]
        let built = PromptBuilder.build(
            action: .promptBuilder,
            snapshot: cursorSnapshot(text: "help me ask for a refactor plan"),
            conversationContext: sampleConversation,
            promptBuilderPhase: .finalize(answers: answers)
        )

        XCTAssertTrue(built.user.contains("ANSWERS:"))
        XCTAssertTrue(built.user.contains("Q: Tone?"))
        XCTAssertTrue(built.user.contains("A: Formal"))
        XCTAssertTrue(built.system.contains("Expand BRIEF into a send-ready LLM message"))
        XCTAssertTrue(built.system.contains("Do NOT re-ask questions or emit ---CLARIFY---"))
    }

    // MARK: - Non-LLM sites

    func testElaborateInTextEditDoesNotUseContextualFraming() {
        let built = PromptBuilder.build(
            action: .elaborate,
            snapshot: textEditSnapshot(text: "short note"),
            conversationContext: nil
        )

        XCTAssertFalse(built.system.contains("Contextual transform"))
        XCTAssertFalse(built.system.contains("Background context"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.user.contains("short note"))
    }

    func testFormalInTextEditDoesNotUseContextualFraming() {
        let built = PromptBuilder.build(
            action: .formal,
            snapshot: textEditSnapshot(text: "hey team"),
            conversationContext: nil
        )

        XCTAssertFalse(built.system.contains("Contextual transform"))
        XCTAssertFalse(built.system.contains("Background context"))
        XCTAssertFalse(built.user.contains("DRAFT:"))
    }
}
