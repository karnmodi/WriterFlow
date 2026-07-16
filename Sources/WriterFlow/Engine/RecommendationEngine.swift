import Foundation

/// Suggests which writing action best fits the current field after the user
/// explicitly opens the action popover. Never runs from passive typing signals.
@MainActor
final class RecommendationEngine {
    private let client: AzureOpenAIClient
    private var runningTask: Task<Void, Never>?
    private var runningTaskField: FocusedField?
    /// Identifies which `recommend()` call is the current one — a stale (superseded) task's
    /// deferred cleanup checks this before touching `runningTask`/`runningTaskField`, so it
    /// can't clobber a newer task's state after a genuine field switch cancels it out from
    /// under itself mid-flight.
    private var currentGeneration = UUID()

    /// Last successful classification for the same field during the current interaction.
    private var cachedRecommendation: (field: FocusedField, action: WritingAction)?

    /// Fired with the suggested action, tagged with the field it was computed for
    /// so callers can discard stale results if the focused field has since changed.
    var onRecommendation: ((WritingAction, FocusedField) -> Void)?

    init(config: AzureModelsConfig) {
        self.client = AzureOpenAIClient(config: config)
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
        runningTaskField = nil
    }

    /// Synchronous cache lookup — nil if nothing cached yet, or if the cached result was
    /// computed for a different field (different app/bundle/role; frame/caret movement within
    /// the same field doesn't count, matching `FocusedField.matchesRecommendationTarget`).
    func recommendation(for field: FocusedField) -> WritingAction? {
        guard let cached = cachedRecommendation, cached.field.matchesRecommendationTarget(field) else {
            return nil
        }
        return cached.action
    }

    func recommend(field: FocusedField) {
        // If a classify for this same field is already in flight, let it run to completion
        // instead of restarting it. A reasoning-capable model call can easily take longer than
        // the ~0.7s typing-pause interval that triggers this — always cancelling-and-restarting
        // on every pause meant a slow call could get killed and reborn forever, never once
        // completing, which is exactly why suggestions never showed up. Only a genuine field
        // change (or an explicit `cancel()`) interrupts an in-flight call now.
        if runningTask != nil, let inFlight = runningTaskField, inFlight.matchesRecommendationTarget(field) {
            return
        }
        cancel()
        let target = field
        let generation = UUID()
        currentGeneration = generation
        runningTaskField = target
        runningTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.currentGeneration == generation {
                    self.runningTask = nil
                    self.runningTaskField = nil
                }
            }
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
                cachedRecommendation = (target, action)
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
