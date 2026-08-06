import XCTest
@testable import WriterFlow

final class PreviewStreamingStatusTests: XCTestCase {
    func testBeforeFirstDeltaShowsActiveComposingState() {
        XCTAssertEqual(
            PreviewStreamingStatus.subtitle(text: "", promptBuilderPhase: nil),
            "Composing the first words…"
        )
    }

    func testPromptBuilderAnalyzeShowsActiveBriefState() {
        XCTAssertEqual(
            PreviewStreamingStatus.subtitle(text: "", promptBuilderPhase: .analyzing),
            "Reading your brief and composing…"
        )
    }

    func testStatusAdvancesAsWordsStreamIn() {
        XCTAssertEqual(
            PreviewStreamingStatus.subtitle(text: "Hello", promptBuilderPhase: nil),
            "1 word written, continuing…"
        )
        XCTAssertEqual(
            PreviewStreamingStatus.subtitle(text: "Hello from WriterFlow", promptBuilderPhase: nil),
            "3 words written, continuing…"
        )
    }

    func testStatusContainsNoPassiveOrStaticGenerationCopy() {
        let statuses = [
            PreviewStreamingStatus.subtitle(text: "", promptBuilderPhase: nil),
            PreviewStreamingStatus.subtitle(text: "One streamed word", promptBuilderPhase: .prompt)
        ]
        for status in statuses {
            XCTAssertFalse(status.localizedCaseInsensitiveContains("waiting"))
            XCTAssertFalse(status.localizedCaseInsensitiveContains("generating"))
        }
    }
}
