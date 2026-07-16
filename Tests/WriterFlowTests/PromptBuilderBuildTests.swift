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

    func testShouldApplyContextualTransformWithConversationOrLLMSite() {
        XCTAssertTrue(
            Prompts.shouldApplyContextualTransform(
                action: .elaborate,
                conversationContext: sampleConversation,
                site: "gmail"
            )
        )
        XCTAssertTrue(
            Prompts.shouldApplyContextualTransform(
                action: .formal,
                conversationContext: nil,
                site: "cursor"
            )
        )
        XCTAssertFalse(
            Prompts.shouldApplyContextualTransform(
                action: .elaborate,
                conversationContext: nil,
                site: "gmail"
            )
        )
    }

    // MARK: - Cursor contextual transforms

    func testElaborateInCursorIncludesContextualPolicyAndDraftLabel() {
        let built = PromptBuilder.build(
            action: .elaborate,
            snapshot: cursorSnapshot(text: "add tests for prompt builder"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Contextual transform"))
        XCTAssertTrue(built.system.contains("Adaptive structure"))
        XCTAssertTrue(built.system.contains("Cursor IDE agent chat"))
        XCTAssertTrue(built.system.contains("do NOT add new requirements or facts"))
        XCTAssertTrue(built.user.contains("CONVERSATION:"))
        XCTAssertTrue(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.user.contains("add tests for prompt builder"))
    }

    func testFormalInCursorPreservesConstraintsGuidance() {
        let built = PromptBuilder.build(
            action: .formal,
            snapshot: cursorSnapshot(text: "please fix ActionEngine.swift"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Change register only"))
        XCTAssertTrue(built.system.contains("Tone override"))
        XCTAssertTrue(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }

    func testCasualInCursorPreservesConstraintsGuidance() {
        let built = PromptBuilder.build(
            action: .casual,
            snapshot: cursorSnapshot(text: "please fix ActionEngine.swift"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Change register only"))
        XCTAssertTrue(built.system.contains("Tone override"))
        XCTAssertTrue(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }

    func testFixGrammarInCursorKeepsStrictNoRephraseRule() {
        let built = PromptBuilder.build(
            action: .fixGrammar,
            snapshot: cursorSnapshot(text: "fix teh prompt builder"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.system.contains("Grammar-only override"))
        XCTAssertTrue(built.system.contains("Do NOT expand, restructure, or change tone"))
        XCTAssertTrue(built.system.contains("Never rephrase"))
        XCTAssertTrue(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }

    func testReplyRetainsSpecializedLabels() {
        let built = PromptBuilder.build(
            action: .reply,
            snapshot: cursorSnapshot(text: "say tests are done"),
            conversationContext: sampleConversation
        )

        XCTAssertTrue(built.user.contains("MY DRAFT/INTENT:"))
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.system.contains("Contextual transform"))
    }

    func testCustomRetainsInstructionAndDraftLabel() {
        let built = PromptBuilder.build(
            action: .custom,
            snapshot: cursorSnapshot(text: "rewrite with bullets"),
            conversationContext: sampleConversation,
            customInstruction: "use three bullets max"
        )

        XCTAssertTrue(built.user.contains("INSTRUCTION: use three bullets max"))
        XCTAssertTrue(built.user.contains("DRAFT/NEXT MESSAGE:"))
        XCTAssertTrue(built.system.contains("Contextual transform"))
    }

    func testPromptBuilderRetainsBriefLabelAndDelimiterContract() {
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
        XCTAssertTrue(built.system.contains("Contextual transform"))
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
        XCTAssertFalse(built.user.contains("DRAFT/NEXT MESSAGE:"))
    }
}
