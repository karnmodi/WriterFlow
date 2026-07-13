import Foundation

/// Orchestrates AX read → Azure OpenAI stream → ConversionEvent logging.
@MainActor
final class ActionEngine {
    typealias StreamHandler = (String) -> Void
    typealias PromptBuilderStreamHandler = (_ prompt: String) -> Void
    typealias PromptBuilderClarifyHandler = (_ questions: [PromptBuilderOutputParser.ClarifyQuestion]) -> Void
    typealias CompletedHandler = (
        _ action: WritingAction,
        _ output: String,
        _ snapshot: FieldSnapshot,
        _ event: ConversionEvent
    ) -> Void

    private struct PromptBuilderSession: Sendable {
        let field: FocusedField
        let snapshot: FieldSnapshot
        let conversationContext: String?
        let customInstruction: String?
    }

    private let client: AzureOpenAIClient
    private var runningTask: Task<Void, Never>?
    private var promptBuilderSession: PromptBuilderSession?

    var onStreamDelta: StreamHandler?
    var onStreamPromptBuilder: PromptBuilderStreamHandler?
    var onPromptBuilderClarify: PromptBuilderClarifyHandler?
    var onCompleted: CompletedHandler?
    var onFailed: ((String) -> Void)?

    init(config: AzureModelsConfig) {
        self.client = AzureOpenAIClient(config: config)
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
        promptBuilderSession = nil
    }

    func run(action: WritingAction, field: FocusedField, customInstruction: String? = nil) {
        runningTask?.cancel()
        promptBuilderSession = nil
        runningTask = Task {
            await execute(action: action, field: field, customInstruction: customInstruction)
        }
    }

    func finalizePromptBuilder(
        answers: [(question: String, answer: String)],
        field: FocusedField
    ) {
        guard let session = promptBuilderSession,
              session.field.matchesRecommendationTarget(field) else {
            let msg = "Prompt Builder session expired. Try again."
            onFailed?(msg)
            ErrorToast.show(msg)
            return
        }

        runningTask?.cancel()
        runningTask = Task {
            await executePromptBuilderFinalize(session: session, answers: answers)
        }
    }

    private func execute(action: WritingAction, field: FocusedField, customInstruction: String? = nil) async {
        guard !Task.isCancelled else { return }

        guard let snapshot = await ContextExtractor.readFocusedField(
            pid: field.appPID,
            bundleID: field.appBundleID
        ) else {
            let msg = "Couldn't read the text field. Try again."
            onFailed?(msg)
            ErrorToast.show(msg)
            return
        }

        let inputText = snapshot.actionText
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let hasUsableInput: Bool
        switch action {
        case .reply:
            hasUsableInput = true
        case .promptBuilder:
            hasUsableInput = !trimmedInput.isEmpty || !trimmedNote.isEmpty
        default:
            hasUsableInput = !trimmedInput.isEmpty
        }

        if !hasUsableInput {
            let msg = action == .promptBuilder
                ? "Describe the prompt you need first."
                : "Nothing to rewrite — type or select some text first."
            onFailed?(msg)
            ErrorToast.show(msg)
            return
        }

        var conversationContext: String?
        if action == .reply || action == .custom || action == .promptBuilder {
            conversationContext = await ConversationExtractor.extractConversation(
                pid: field.appPID,
                excludingDraft: snapshot.actionText
            )
            await CompatibilityMap.shared.recordContext(bundleID: field.appBundleID, ok: conversationContext != nil)
        }

        let site = AppAdapterRegistry.siteLabel(
            bundleID: snapshot.appBundleID,
            windowTitle: snapshot.windowTitle
        )
        if action == .reply || action == .custom || action == .promptBuilder {
            await CompatibilityMap.shared.recordIdentity(bundleID: field.appBundleID, site: site)
        }
        guard !Task.isCancelled else { return }

        if action == .promptBuilder {
            promptBuilderSession = PromptBuilderSession(
                field: field,
                snapshot: snapshot,
                conversationContext: conversationContext,
                customInstruction: customInstruction
            )
            await executePromptBuilderAnalyze(
                field: field,
                snapshot: snapshot,
                conversationContext: conversationContext,
                customInstruction: customInstruction,
                inputText: inputText,
                trimmedInput: trimmedInput,
                trimmedNote: trimmedNote
            )
            return
        }

        let prompt = PromptBuilder.build(
            action: action,
            snapshot: snapshot,
            conversationContext: conversationContext,
            customInstruction: customInstruction
        )
        var event = ConversionEvent(
            appBundleID: field.appBundleID,
            action: action,
            input: trimmedInput.isEmpty ? trimmedNote : inputText
        )

        Log.engine.info(
            "ActionEngine start action=\(action.title, privacy: .public) chars=\(inputText.count, privacy: .public) contextChars=\(conversationContext?.count ?? 0, privacy: .public)"
        )

        var rawOutput = ""
        let started = ContinuousClock.now

        do {
            let stream = await client.stream(action: action, prompt: prompt)
            for try await delta in stream {
                if Task.isCancelled { return }
                let clean = OutputSanitizer.sanitize(delta)
                rawOutput += clean
                onStreamDelta?(clean)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine failed: \(message, privacy: .public)")
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let finalOutput = OutputSanitizer.sanitize(rawOutput)
        Log.engine.info(
            "ActionEngine done action=\(action.title, privacy: .public) outChars=\(finalOutput.count, privacy: .public) ms=\(ms, privacy: .public)"
        )

        event.output = finalOutput
        onCompleted?(action, finalOutput, snapshot, event)
    }

    private func executePromptBuilderAnalyze(
        field: FocusedField,
        snapshot: FieldSnapshot,
        conversationContext: String?,
        customInstruction: String?,
        inputText: String,
        trimmedInput: String,
        trimmedNote: String
    ) async {
        let prompt = PromptBuilder.build(
            action: .promptBuilder,
            snapshot: snapshot,
            conversationContext: conversationContext,
            customInstruction: customInstruction,
            promptBuilderPhase: .analyze
        )

        Log.engine.info(
            "ActionEngine start action=Prompt Builder analyze chars=\(inputText.count, privacy: .public) contextChars=\(conversationContext?.count ?? 0, privacy: .public)"
        )

        var rawOutput = ""
        let started = ContinuousClock.now

        do {
            let stream = await client.stream(action: .promptBuilder, prompt: prompt)
            for try await delta in stream {
                if Task.isCancelled { return }
                let clean = OutputSanitizer.sanitize(delta)
                rawOutput += clean

                let split = PromptBuilderOutputParser.splitStreaming(rawOutput)
                switch split.mode {
                case .prompt:
                    onStreamPromptBuilder?(split.prompt)
                case .clarify, .undetermined:
                    break
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine failed: \(message, privacy: .public)")
            promptBuilderSession = nil
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let parsed = PromptBuilderOutputParser.parse(rawOutput)

        switch parsed {
        case .clarify(let questions):
            Log.engine.info(
                "ActionEngine clarify action=Prompt Builder questions=\(questions.count, privacy: .public) ms=\(ms, privacy: .public)"
            )
            onPromptBuilderClarify?(questions)

        case .prompt(let text):
            let finalOutput = OutputSanitizer.sanitize(text)
            Log.engine.info(
                "ActionEngine done action=Prompt Builder outChars=\(finalOutput.count, privacy: .public) ms=\(ms, privacy: .public)"
            )
            var event = ConversionEvent(
                appBundleID: field.appBundleID,
                action: .promptBuilder,
                input: trimmedInput.isEmpty ? trimmedNote : inputText
            )
            event.output = finalOutput
            promptBuilderSession = nil
            onCompleted?(.promptBuilder, finalOutput, snapshot, event)
        }
    }

    private func executePromptBuilderFinalize(
        session: PromptBuilderSession,
        answers: [(question: String, answer: String)]
    ) async {
        guard !Task.isCancelled else { return }

        let prompt = PromptBuilder.build(
            action: .promptBuilder,
            snapshot: session.snapshot,
            conversationContext: session.conversationContext,
            customInstruction: session.customInstruction,
            promptBuilderPhase: .finalize(answers: answers)
        )

        let inputText = session.snapshot.actionText
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = session.customInstruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        Log.engine.info(
            "ActionEngine start action=Prompt Builder finalize answers=\(answers.count, privacy: .public)"
        )

        var rawOutput = ""
        let started = ContinuousClock.now

        do {
            let stream = await client.stream(action: .promptBuilder, prompt: prompt)
            for try await delta in stream {
                if Task.isCancelled { return }
                let clean = OutputSanitizer.sanitize(delta)
                rawOutput += clean

                let split = PromptBuilderOutputParser.splitStreaming(rawOutput)
                if split.mode == .prompt || split.mode == .undetermined {
                    onStreamPromptBuilder?(split.prompt)
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine finalize failed: \(message, privacy: .public)")
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let parsed = PromptBuilderOutputParser.parse(rawOutput)
        let finalOutput: String
        switch parsed {
        case .prompt(let text):
            finalOutput = OutputSanitizer.sanitize(text)
        case .clarify:
            finalOutput = OutputSanitizer.sanitize(rawOutput)
        }

        Log.engine.info(
            "ActionEngine done action=Prompt Builder finalize outChars=\(finalOutput.count, privacy: .public) ms=\(ms, privacy: .public)"
        )

        var event = ConversionEvent(
            appBundleID: session.field.appBundleID,
            action: .promptBuilder,
            input: trimmedInput.isEmpty ? trimmedNote : inputText
        )
        event.output = finalOutput
        promptBuilderSession = nil
        onCompleted?(.promptBuilder, finalOutput, session.snapshot, event)
    }
}
