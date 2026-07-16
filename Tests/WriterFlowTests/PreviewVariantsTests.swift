import XCTest
@testable import WriterFlow

final class PreviewVariantsTests: XCTestCase {
    func testEmptyDefaults() {
        let variants = PreviewVariants.empty()
        XCTAssertEqual(variants.texts.count, PreviewVariants.count)
        XCTAssertTrue(variants.texts.allSatisfy(\.isEmpty))
        XCTAssertEqual(variants.selectedIndex, 0)
        XCTAssertTrue(variants.completedIndices.isEmpty)
        XCTAssertFalse(variants.canReplace)
        XCTAssertTrue(variants.isStreaming)
    }

    func testSingleFactory() {
        let variants = PreviewVariants.single("Hello")
        XCTAssertEqual(variants.selectedText, "Hello")
        XCTAssertEqual(variants.completedIndices, Set(0..<PreviewVariants.count))
        XCTAssertTrue(variants.canReplace)
        XCTAssertFalse(variants.isStreaming)
    }

    func testAppendAndSelect() {
        var variants = PreviewVariants.empty()
        variants.append(to: 1, delta: "Hi")
        variants.append(to: 1, delta: " there")
        XCTAssertEqual(variants.texts[1], "Hi there")

        variants.select(2)
        XCTAssertEqual(variants.selectedIndex, 2)
        XCTAssertFalse(variants.canReplace)
    }

    func testMarkCompletedStopsStreaming() {
        var variants = PreviewVariants.empty()
        variants.markCompleted(0)
        variants.markCompleted(1)
        variants.markCompleted(2)
        XCTAssertFalse(variants.isStreaming)
    }

    func testV1ActionsUseOneProviderRequest() {
        XCTAssertFalse(WritingAction.elaborate.usesMultiVariantPreview)
        XCTAssertFalse(WritingAction.formal.usesMultiVariantPreview)
        XCTAssertFalse(WritingAction.casual.usesMultiVariantPreview)
        XCTAssertFalse(WritingAction.fixGrammar.usesMultiVariantPreview)
        XCTAssertFalse(WritingAction.reply.usesMultiVariantPreview)
        XCTAssertFalse(WritingAction.custom.usesMultiVariantPreview)
        XCTAssertFalse(WritingAction.promptBuilder.usesMultiVariantPreview)
    }
}
