import XCTest
@testable import WriterFlow

final class PromptBuilderOutputParserTests: XCTestCase {
    func testParseDirectPrompt() {
        let raw = """
        ---PROMPT---
        Write a concise product update email for the Q2 launch.
        """

        let result = PromptBuilderOutputParser.parse(raw)
        guard case .prompt(let text) = result else {
            return XCTFail("Expected prompt result")
        }
        XCTAssertTrue(text.contains("product update email"))
    }

    func testParseClarifyQuestions() {
        let raw = """
        ---CLARIFY---
        Q: Who is the audience?
        - Engineering team
        - Executive leadership
        - External customers
        Q: What tone should it use?
        - Formal
        - Casual
        - Technical
        """

        let result = PromptBuilderOutputParser.parse(raw)
        guard case .clarify(let questions) = result else {
            return XCTFail("Expected clarify result")
        }
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions[0].text, "Who is the audience?")
        XCTAssertEqual(questions[0].suggestions, ["Engineering team", "Executive leadership", "External customers"])
        XCTAssertEqual(questions[1].text, "What tone should it use?")
        XCTAssertEqual(questions[1].suggestions.count, 3)
    }

    func testParseClarifyNoneReturnsEmptyPrompt() {
        let raw = """
        ---CLARIFY---
        (none)
        """

        let result = PromptBuilderOutputParser.parse(raw)
        guard case .prompt = result else {
            return XCTFail("Expected empty prompt when clarify is none")
        }
    }

    func testParsePrefersFirstDelimiterWhenBothPresent() {
        let raw = """
        ---CLARIFY---
        Q: Scope?
        - Small
        - Large
        ---PROMPT---
        Should not appear
        """

        let result = PromptBuilderOutputParser.parse(raw)
        guard case .clarify(let questions) = result else {
            return XCTFail("Expected clarify when ---CLARIFY--- appears first")
        }
        XCTAssertEqual(questions.count, 1)
    }

    func testSplitStreamingPromptMode() {
        let buffer = """
        ---PROMPT---
        Draft a
        """

        let split = PromptBuilderOutputParser.splitStreaming(buffer)
        XCTAssertEqual(split.mode, .prompt)
        XCTAssertEqual(split.prompt, "Draft a")
        XCTAssertTrue(split.clarifyQuestions.isEmpty)
    }

    func testSplitStreamingClarifyMode() {
        let buffer = """
        ---CLARIFY---
        Q: Format?
        - Bullets
        - Paragraph
        """

        let split = PromptBuilderOutputParser.splitStreaming(buffer)
        XCTAssertEqual(split.mode, .clarify)
        XCTAssertTrue(split.prompt.isEmpty)
        XCTAssertEqual(split.clarifyQuestions.count, 1)
        XCTAssertEqual(split.clarifyQuestions[0].suggestions, ["Bullets", "Paragraph"])
    }

    func testParseClarifyQuestionsStandalone() {
        let body = """
        Q: Deadline?
        - Friday
        - Next week
        """

        let questions = PromptBuilderOutputParser.parseClarifyQuestions(body)
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions[0].id, "q0")
        XCTAssertEqual(questions[0].suggestions, ["Friday", "Next week"])
    }
}
