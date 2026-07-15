import XCTest
@testable import WriterFlow

final class ActionEngineVariantTests: XCTestCase {
    private func snapshot(text: String = "make this clearer") -> FieldSnapshot {
        FieldSnapshot(
            fullText: text,
            selectedText: "",
            selectedRange: NSRange(location: 0, length: 0),
            role: "AXTextArea",
            appBundleID: "com.apple.TextEdit",
            windowTitle: "Untitled"
        )
    }

    func testRewriteActionsIncludeVariantInstruction() {
        let snap = snapshot()
        for action in [WritingAction.elaborate, .formal, .casual, .fixGrammar, .reply, .custom] {
            for index in 0..<PreviewVariants.count {
                let built = PromptBuilder.build(
                    action: action,
                    snapshot: snap,
                    variantIndex: index
                )
                XCTAssertTrue(
                    built.system.contains("Variant generation (\(index + 1) of \(PreviewVariants.count))"),
                    "Expected variant instruction for \(action.title) index \(index)"
                )
            }
        }
    }

    func testPromptBuilderOmitsVariantInstruction() {
        let built = PromptBuilder.build(
            action: .promptBuilder,
            snapshot: snapshot(),
            promptBuilderPhase: .analyze
        )
        XCTAssertFalse(built.system.contains("Variant generation"))
    }

    func testVariantInstructionsDifferByIndex() {
        let snap = snapshot()
        let a = PromptBuilder.build(action: .elaborate, snapshot: snap, variantIndex: 0).system
        let b = PromptBuilder.build(action: .elaborate, snapshot: snap, variantIndex: 1).system
        let c = PromptBuilder.build(action: .elaborate, snapshot: snap, variantIndex: 2).system
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
    }
}
