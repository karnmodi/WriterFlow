import Foundation

/// Orchestrates AX read → Azure OpenAI stream → ConversionEvent logging.
@MainActor
final class ActionEngine {
    typealias StreamHandler = (String) -> Void

    private let client: AzureOpenAIClient
    private var runningTask: Task<Void, Never>?

    var onStreamDelta: StreamHandler?
    var onCompleted: ((WritingAction, String) -> Void)?

    init(config: AzureModelsConfig) {
        self.client = AzureOpenAIClient(config: config)
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
    }

    func run(action: WritingAction, field: FocusedField) {
        runningTask?.cancel()
        runningTask = Task {
            await execute(action: action, field: field)
        }
    }

    private func execute(action: WritingAction, field: FocusedField) async {
        guard !Task.isCancelled else { return }

        guard let snapshot = await ContextExtractor.readFocusedField(
            pid: field.appPID,
            bundleID: field.appBundleID
        ) else {
            await MainActor.run {
                ErrorToast.show("Couldn't read the text field. Try again.")
            }
            return
        }

        let inputText = snapshot.actionText
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ErrorToast.show("Nothing to rewrite — type or select some text first.")
            return
        }

        let prompt = PromptBuilder.build(action: action, snapshot: snapshot)
        var event = ConversionEvent(
            appBundleID: field.appBundleID,
            action: action,
            input: inputText
        )

        Log.engine.info("ActionEngine start action=\(action.title, privacy: .public) chars=\(inputText.count, privacy: .public)")

        var output = ""
        let started = ContinuousClock.now

        do {
            let stream = await client.stream(action: action, prompt: prompt)
            for try await delta in stream {
                if Task.isCancelled { return }
                output += delta
                onStreamDelta?(delta)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ErrorToast.show(message)
            Log.engine.error("ActionEngine failed: \(message, privacy: .public)")
            return
        }

        let elapsed = started.duration(to: .now)
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        Log.engine.info(
            "ActionEngine done action=\(action.title, privacy: .public) outChars=\(output.count, privacy: .public) ms=\(ms, privacy: .public)"
        )

        event.output = output
        await ConversionEventStore.shared.append(event)
        onCompleted?(action, output)
    }
}
