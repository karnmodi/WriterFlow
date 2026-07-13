import Foundation

/// Suggests which writing action best fits the current field, via a small
/// classification call. Never blocks the popover from opening — runs
/// concurrently with it and reports back asynchronously.
@MainActor
final class RecommendationEngine {
    private let client: AzureOpenAIClient
    private var runningTask: Task<Void, Never>?

    /// Fired with the suggested action, tagged with the field it was computed for
    /// so callers can discard stale results if the focused field has since changed.
    var onRecommendation: ((WritingAction, FocusedField) -> Void)?

    init(config: AzureModelsConfig) {
        self.client = AzureOpenAIClient(config: config)
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
    }

    func recommend(field: FocusedField) {
        cancel()
        let target = field
        runningTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let snapshotTask = ContextExtractor.readFocusedField(
                    pid: target.appPID,
                    bundleID: target.appBundleID
                )
                async let threadTask = ConversationExtractor.hasVisibleConversation(pid: target.appPID)

                let snapshot = await snapshotTask
                let hasThread = await threadTask
                guard !Task.isCancelled else { return }

                let fieldText = snapshot?.actionText ?? ""
                let toneBias = AppAdapterRegistry.adapter(for: target.appBundleID).toneBias

                let action = try await client.classifyAction(
                    fieldText: fieldText,
                    hasVisibleThread: hasThread,
                    toneBias: toneBias
                )
                guard !Task.isCancelled else { return }
                guard let action else {
                    Log.engine.info("Recommendation: classify returned no parseable action")
                    return
                }

                Log.engine.info(
                    "Recommendation: \(action.title, privacy: .public) for pid=\(target.appPID, privacy: .public)"
                )
                onRecommendation?(action, target)
            } catch is CancellationError {
                // Expected when popover closes or a newer recommend starts.
            } catch {
                Log.engine.error(
                    "Recommendation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
