import Foundation

/// Parses Prompt Builder's mutually exclusive `---CLARIFY---` or `---PROMPT---` response.
enum PromptBuilderOutputParser {
    static let promptDelimiter = "---PROMPT---"
    static let clarifyDelimiter = "---CLARIFY---"

    struct ClarifyQuestion: Sendable, Equatable, Identifiable {
        let id: String
        let text: String
        let suggestions: [String]
    }

    enum Result: Sendable, Equatable {
        case clarify([ClarifyQuestion])
        case prompt(String)
    }

    enum StreamingMode: Sendable, Equatable {
        case undetermined
        case clarify
        case prompt
    }

    struct StreamingSplit: Sendable, Equatable {
        let mode: StreamingMode
        let prompt: String
        let clarifyQuestions: [ClarifyQuestion]
        let rawClarifyBody: String
    }

    static func parse(_ raw: String) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .prompt("") }

        let mode = detectMode(in: trimmed)
        switch mode {
        case .clarify:
            let body = extractBody(after: clarifyDelimiter, in: trimmed)
            let questions = parseClarifyQuestions(body)
            if questions.isEmpty {
                return .prompt("")
            }
            return .clarify(questions)
        case .prompt:
            let body = extractBody(after: promptDelimiter, in: trimmed)
            return .prompt(body)
        case .undetermined:
            return .prompt(trimmed)
        }
    }

    /// Incremental parse for SSE — returns best-effort mode, prompt text, and partial clarify questions.
    static func splitStreaming(_ buffer: String) -> StreamingSplit {
        let mode = detectMode(in: buffer)
        switch mode {
        case .clarify:
            let body = extractBody(after: clarifyDelimiter, in: buffer)
            return StreamingSplit(
                mode: .clarify,
                prompt: "",
                clarifyQuestions: parseClarifyQuestions(body),
                rawClarifyBody: body
            )
        case .prompt:
            let body = extractBody(after: promptDelimiter, in: buffer)
            return StreamingSplit(
                mode: .prompt,
                prompt: body,
                clarifyQuestions: [],
                rawClarifyBody: ""
            )
        case .undetermined:
            return StreamingSplit(
                mode: .undetermined,
                prompt: buffer.trimmingCharacters(in: .whitespacesAndNewlines),
                clarifyQuestions: [],
                rawClarifyBody: ""
            )
        }
    }

    // MARK: - Mode detection

    private static func detectMode(in buffer: String) -> StreamingMode {
        let clarifyIndex = buffer.range(of: clarifyDelimiter)?.lowerBound
        let promptIndex = buffer.range(of: promptDelimiter)?.lowerBound

        switch (clarifyIndex, promptIndex) {
        case let (c?, p?):
            return c < p ? .clarify : .prompt
        case (.some, .none):
            return .clarify
        case (.none, .some):
            return .prompt
        case (.none, .none):
            return .undetermined
        }
    }

    private static func extractBody(after delimiter: String, in buffer: String) -> String {
        guard let range = buffer.range(of: delimiter) else { return "" }
        return String(buffer[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Clarify parsing

    static func parseClarifyQuestions(_ body: String) -> [ClarifyQuestion] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lowered = trimmed.lowercased()
        if lowered == "(none)" || lowered == "none" { return [] }

        var questions: [ClarifyQuestion] = []
        var currentText: String?
        var currentSuggestions: [String] = []
        var questionIndex = 0

        func flushQuestion() {
            guard let text = currentText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                currentText = nil
                currentSuggestions = []
                return
            }
            let suggestions = currentSuggestions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !suggestions.isEmpty {
                questions.append(
                    ClarifyQuestion(
                        id: "q\(questionIndex)",
                        text: text,
                        suggestions: suggestions
                    )
                )
                questionIndex += 1
            }
            currentText = nil
            currentSuggestions = []
        }

        for line in trimmed.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty else { continue }

            if let question = parseQuestionLine(stripped) {
                flushQuestion()
                currentText = question
            } else if let suggestion = parseSuggestionLine(stripped) {
                currentSuggestions.append(suggestion)
            }
        }

        flushQuestion()
        return questions
    }

    private static func parseQuestionLine(_ line: String) -> String? {
        let prefixes = ["Q:", "q:", "Question:", "question:"]
        for prefix in prefixes {
            if line.hasPrefix(prefix) {
                let text = String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
        }
        return nil
    }

    private static func parseSuggestionLine(_ line: String) -> String? {
        if line.hasPrefix("- ") {
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if line.hasPrefix("-") && line.count > 1 {
            let text = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if line.hasPrefix("• ") {
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return nil
    }
}
