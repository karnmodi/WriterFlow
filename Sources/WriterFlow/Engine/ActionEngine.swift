import Foundation

private extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

/// Orchestrates AX read → Azure OpenAI stream → ConversionEvent logging.
@MainActor
final class ActionEngine {
    typealias StreamHandler = (String) -> Void
    typealias VariantStreamHandler = (_ index: Int, _ delta: String) -> Void
    typealias VariantCompletedHandler = (_ index: Int) -> Void
    typealias PromptBuilderStreamHandler = (_ prompt: String) -> Void
    typealias PromptBuilderClarifyHandler = (_ questions: [PromptBuilderOutputParser.ClarifyQuestion]) -> Void
    typealias CompletedHandler = (
        _ action: WritingAction,
        _ variants: PreviewVariants,
        _ snapshot: FieldSnapshot,
        _ event: ConversionEvent
    ) -> Void

    private struct PromptBuilderSession: Sendable {
        let field: FocusedField
        let snapshot: FieldSnapshot
        let conversationContext: String?
        let customInstruction: String?
        let site: String?
    }

    private let client: AzureOpenAIClient
    private let inferenceTransport: (any InferenceTransport)?
    private let deviceSession: (any DeviceSessionProviding)?
    private var runningTask: Task<Void, Never>?
    private var promptBuilderSession: PromptBuilderSession?

    var onStreamDelta: StreamHandler?
    var onStreamVariantDelta: VariantStreamHandler?
    var onVariantStreamCompleted: VariantCompletedHandler?
    var onStreamPromptBuilder: PromptBuilderStreamHandler?
    var onPromptBuilderClarify: PromptBuilderClarifyHandler?
    var onCompleted: CompletedHandler?
    var onFailed: ((String) -> Void)?

    init(
        config: AzureModelsConfig,
        inferenceTransport: (any InferenceTransport)? = nil,
        deviceSession: (any DeviceSessionProviding)? = nil
    ) {
        self.client = AzureOpenAIClient(config: config)
        self.inferenceTransport = inferenceTransport
        self.deviceSession = deviceSession
    }

    /// Resolves Stage 3.3 personalization for a given app/site — synchronous because
    /// `ActionEngine`, `SettingsStore`, `MemoryStore`, and `AppRuleStore` all run on `@MainActor`.
    private func personalizationContext(bundleID: String?, site: String?) -> PromptBuilder.PersonalizationContext {
        let rule = AppRuleStore.shared.rule(forBundleID: bundleID, site: site)
        let result = MemoryPromptBuilder.build(
            profile: SettingsStore.shared.voiceProfile,
            notes: MemoryStore.shared.notes,
            appRule: rule
        )
        if result.excludedCount > 0 {
            Log.engine.info("Memory prompt budget exceeded — excluded \(result.excludedCount, privacy: .public) oldest note(s)")
        }
        return PromptBuilder.PersonalizationContext(memoryBlock: result.block, toneOverride: rule?.tone)
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

        let site = AppAdapterRegistry.siteLabel(
            bundleID: snapshot.appBundleID,
            windowTitle: snapshot.windowTitle
        )

        if Prompts.shouldExtractConversation(for: action, site: site) {
            conversationContext = await ConversationExtractor.extractConversation(
                pid: field.appPID,
                excludingDraft: snapshot.actionText
            )
            await CompatibilityMap.shared.recordContext(bundleID: field.appBundleID, ok: conversationContext != nil)
            await CompatibilityMap.shared.recordIdentity(bundleID: field.appBundleID, site: site)
        }

        guard !Task.isCancelled else { return }

        if action == .promptBuilder {
            promptBuilderSession = PromptBuilderSession(
                field: field,
                snapshot: snapshot,
                conversationContext: conversationContext,
                customInstruction: customInstruction,
                site: site
            )
            await executePromptBuilderAnalyze(
                field: field,
                snapshot: snapshot,
                conversationContext: conversationContext,
                customInstruction: customInstruction,
                inputText: inputText,
                trimmedInput: trimmedInput,
                trimmedNote: trimmedNote,
                site: site
            )
            return
        }

        let personalization = personalizationContext(bundleID: field.appBundleID, site: site)

        if await shouldUseCloudInference(for: action),
           let transport = inferenceTransport {
            await executeCloudFixGrammar(
                field: field,
                snapshot: snapshot,
                conversationContext: conversationContext,
                inputText: inputText,
                trimmedInput: trimmedInput,
                trimmedNote: trimmedNote,
                site: site,
                transport: transport
            )
            return
        }

        if action.usesMultiVariantPreview {
            await executeMultiVariant(
                action: action,
                field: field,
                snapshot: snapshot,
                conversationContext: conversationContext,
                customInstruction: customInstruction,
                inputText: inputText,
                trimmedInput: trimmedInput,
                trimmedNote: trimmedNote,
                site: site,
                personalization: personalization
            )
            return
        }

        let prompt = PromptBuilder.build(
            action: action,
            snapshot: snapshot,
            conversationContext: conversationContext,
            customInstruction: customInstruction,
            personalization: personalization
        )
        var event = ConversionEvent(
            appBundleID: field.appBundleID,
            site: site,
            action: action,
            input: trimmedInput.isEmpty ? trimmedNote : inputText
        )

        Log.engine.info(
            "ActionEngine start action=\(action.title, privacy: .public) chars=\(inputText.count, privacy: .public) contextChars=\(conversationContext?.count ?? 0, privacy: .public)"
        )

        var rawOutput = ""
        let started = ContinuousClock.now
        var firstTokenLogged = false

        do {
            let stream = await client.stream(action: action, prompt: prompt)
            for try await delta in stream {
                if Task.isCancelled { return }
                if !firstTokenLogged {
                    firstTokenLogged = true
                    // PRD §8 success metric: first streamed token < 800ms.
                    let firstTokenMs = started.duration(to: .now).milliseconds
                    Log.engine.info("ActionEngine firstTokenMs=\(firstTokenMs, privacy: .public)")
                }
                let clean = OutputSanitizer.sanitize(delta)
                rawOutput += clean
                onStreamDelta?(clean)
            }
        } catch {
            let message = Self.userFacingMessage(for: error)
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine failed: \(message, privacy: .public)")
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = elapsed.milliseconds
        let finalOutput = OutputSanitizer.sanitize(rawOutput)
        Log.engine.info(
            "ActionEngine done action=\(action.title, privacy: .public) outChars=\(finalOutput.count, privacy: .public) ms=\(ms, privacy: .public)"
        )

        let usage = await client.consumeLastUsage()
        event.output = finalOutput
        event.model = usage?.model
        event.tokensIn = usage?.tokensIn
        event.tokensOut = usage?.tokensOut
        event.latencyMs = ms
        onCompleted?(action, .single(finalOutput), snapshot, event)
    }

    private func shouldUseCloudInference(for action: WritingAction) async -> Bool {
        guard let deviceSession else { return false }
        let sessionState = await deviceSession.state
        return cloudInferenceEnabled(
            action: action,
            useCloudInference: TransportPreferences.useCloudInference,
            sessionState: sessionState,
            hasTransport: inferenceTransport != nil
        )
    }

    private func executeCloudFixGrammar(
        field: FocusedField,
        snapshot: FieldSnapshot,
        conversationContext: String?,
        inputText: String,
        trimmedInput: String,
        trimmedNote: String,
        site: String?,
        transport: any InferenceTransport
    ) async {
        var event = ConversionEvent(
            appBundleID: field.appBundleID,
            site: site,
            action: .fixGrammar,
            input: trimmedInput.isEmpty ? trimmedNote : inputText
        )

        let request = InferenceRequestBuilder.fixGrammar(
            snapshot: snapshot,
            site: site,
            conversation: conversationContext
        )

        Log.engine.info(
            "ActionEngine start action=Fix Grammar transport=cloud chars=\(inputText.count, privacy: .public) contextChars=\(conversationContext?.count ?? 0, privacy: .public)"
        )

        var rawOutput = ""
        var promptVersion: String?
        let started = ContinuousClock.now
        var firstTokenLogged = false

        do {
            let stream = transport.streamFixGrammar(request)
            for try await streamEvent in stream {
                if Task.isCancelled { return }
                switch streamEvent {
                case .delta(let delta):
                    if !firstTokenLogged {
                        firstTokenLogged = true
                        let firstTokenMs = started.duration(to: .now).milliseconds
                        Log.engine.info("ActionEngine firstTokenMs=\(firstTokenMs, privacy: .public)")
                    }
                    let clean = OutputSanitizer.sanitize(delta)
                    rawOutput += clean
                    onStreamDelta?(clean)
                case .completed(_, let version):
                    promptVersion = version
                case .requestAccepted, .decision, .usageSummary:
                    break
                }
            }
        } catch {
            let message = Self.userFacingMessage(for: error)
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine cloud failed: \(message, privacy: .public)")
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = elapsed.milliseconds
        let finalOutput = OutputSanitizer.sanitize(rawOutput)
        Log.engine.info(
            "ActionEngine done action=Fix Grammar transport=cloud outChars=\(finalOutput.count, privacy: .public) ms=\(ms, privacy: .public)"
        )

        event.output = finalOutput
        event.model = promptVersion
        event.latencyMs = ms
        onCompleted?(.fixGrammar, .single(finalOutput), snapshot, event)
    }

    private func executeMultiVariant(
        action: WritingAction,
        field: FocusedField,
        snapshot: FieldSnapshot,
        conversationContext: String?,
        customInstruction: String?,
        inputText: String,
        trimmedInput: String,
        trimmedNote: String,
        site: String?,
        personalization: PromptBuilder.PersonalizationContext
    ) async {
        var event = ConversionEvent(
            appBundleID: field.appBundleID,
            site: site,
            action: action,
            input: trimmedInput.isEmpty ? trimmedNote : inputText
        )

        Log.engine.info(
            "ActionEngine start action=\(action.title, privacy: .public) variants=\(PreviewVariants.count, privacy: .public) chars=\(inputText.count, privacy: .public) contextChars=\(conversationContext?.count ?? 0, privacy: .public)"
        )

        var texts = Array(repeating: "", count: PreviewVariants.count)
        var completed = Set<Int>()
        var errors: [Error] = []
        var totalTokensIn = 0
        var totalTokensOut = 0
        var modelName: String?
        let started = ContinuousClock.now

        await withTaskGroup(of: (Int, Result<(String, (model: String, tokensIn: Int, tokensOut: Int)?), Error>).self) { group in
            for index in 0..<PreviewVariants.count {
                group.addTask {
                    let prompt = PromptBuilder.build(
                        action: action,
                        snapshot: snapshot,
                        conversationContext: conversationContext,
                        customInstruction: customInstruction,
                        personalization: personalization,
                        variantIndex: index
                    )
                    var rawOutput = ""
                    do {
                        let stream = await self.client.stream(action: action, prompt: prompt)
                        for try await delta in stream {
                            if Task.isCancelled { return (index, .failure(CancellationError())) }
                            let clean = OutputSanitizer.sanitize(delta)
                            rawOutput += clean
                            await MainActor.run {
                                self.onStreamVariantDelta?(index, clean)
                            }
                        }
                        let finalOutput = OutputSanitizer.sanitize(rawOutput)
                        let usage = await self.client.consumeLastUsage()
                        await MainActor.run {
                            self.onVariantStreamCompleted?(index)
                        }
                        return (index, .success((finalOutput, usage)))
                    } catch {
                        Log.engine.error(
                            "ActionEngine variant \(index, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                        )
                        return (index, .failure(error))
                    }
                }
            }

            for await (index, result) in group {
                switch result {
                case .success(let payload):
                    texts[index] = payload.0
                    completed.insert(index)
                    if let usage = payload.1 {
                        totalTokensIn += usage.tokensIn
                        totalTokensOut += usage.tokensOut
                        modelName = usage.model
                    }
                case .failure(let error):
                    if error is CancellationError { continue }
                    errors.append(error)
                }
            }
        }

        guard !Task.isCancelled else { return }

        let hasOutput = texts.contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !hasOutput {
            let message = errors.first.map(Self.userFacingMessage(for:))
                ?? "Couldn't generate variants. Try again."
            onFailed?(message)
            ErrorToast.show(message)
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = elapsed.milliseconds
        let variants = PreviewVariants(texts: texts, selectedIndex: 0, completedIndices: completed)
        let selectedOutput = variants.selectedText

        Log.engine.info(
            "ActionEngine done action=\(action.title, privacy: .public) variants=\(completed.count, privacy: .public)/\(PreviewVariants.count, privacy: .public) outChars=\(selectedOutput.count, privacy: .public) ms=\(ms, privacy: .public)"
        )

        event.output = selectedOutput
        event.model = modelName
        event.tokensIn = totalTokensIn > 0 ? totalTokensIn : nil
        event.tokensOut = totalTokensOut > 0 ? totalTokensOut : nil
        event.latencyMs = ms
        onCompleted?(action, variants, snapshot, event)
    }

    private func executePromptBuilderAnalyze(
        field: FocusedField,
        snapshot: FieldSnapshot,
        conversationContext: String?,
        customInstruction: String?,
        inputText: String,
        trimmedInput: String,
        trimmedNote: String,
        site: String?
    ) async {
        let prompt = PromptBuilder.build(
            action: .promptBuilder,
            snapshot: snapshot,
            conversationContext: conversationContext,
            customInstruction: customInstruction,
            promptBuilderPhase: .analyze,
            personalization: personalizationContext(bundleID: field.appBundleID, site: site)
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
            let message = Self.userFacingMessage(for: error)
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine failed: \(message, privacy: .public)")
            promptBuilderSession = nil
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = elapsed.milliseconds
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
            let usage = await client.consumeLastUsage()
            var event = ConversionEvent(
                appBundleID: field.appBundleID,
                site: site,
                action: .promptBuilder,
                input: trimmedInput.isEmpty ? trimmedNote : inputText
            )
            event.output = finalOutput
            event.model = usage?.model
            event.tokensIn = usage?.tokensIn
            event.tokensOut = usage?.tokensOut
            event.latencyMs = ms
            promptBuilderSession = nil
            onCompleted?(.promptBuilder, .single(finalOutput), snapshot, event)
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
            promptBuilderPhase: .finalize(answers: answers),
            personalization: personalizationContext(bundleID: session.field.appBundleID, site: session.site)
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
            let message = Self.userFacingMessage(for: error)
            onFailed?(message)
            ErrorToast.show(message)
            Log.engine.error("ActionEngine finalize failed: \(message, privacy: .public)")
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = elapsed.milliseconds
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

        let usage = await client.consumeLastUsage()
        var event = ConversionEvent(
            appBundleID: session.field.appBundleID,
            site: session.site,
            action: .promptBuilder,
            input: trimmedInput.isEmpty ? trimmedNote : inputText
        )
        event.output = finalOutput
        event.model = usage?.model
        event.tokensIn = usage?.tokensIn
        event.tokensOut = usage?.tokensOut
        event.latencyMs = ms
        promptBuilderSession = nil
        onCompleted?(.promptBuilder, .single(finalOutput), session.snapshot, event)
    }

    /// Stage 4.3 offline-mode requirement: a clear, WriterFlow-specific message instead of
    /// a raw `URLError` description — no queuing/retry-later, the failed action is just gone.
    private static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You're offline — try again once you're connected."
            case .timedOut:
                return "Request timed out — try again."
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
