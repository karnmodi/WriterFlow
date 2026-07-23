import Foundation

struct LegacyInferenceUsage: Sendable {
    let model: String
    let tokensIn: Int
    let tokensOut: Int
}

enum LegacyInferenceRollbackError: Error, LocalizedError {
    case disabled

    var errorDescription: String? {
        "Legacy Azure rollback is disabled for this account."
    }
}

protocol LegacyActionInferenceClient: Sendable {
    func stream(
        action: WritingAction,
        prompt: PromptBuilder.BuiltPrompt
    ) async -> AsyncThrowingStream<String, Error>

    func consumeLastUsage() async -> LegacyInferenceUsage?
}

protocol RecommendationClassifying: Sendable {
    func classifyAction(
        fieldText: String,
        hasVisibleThread: Bool,
        toneBias: String
    ) async throws -> WritingAction?
}

actor AzureLegacyActionInferenceAdapter: LegacyActionInferenceClient {
    private let client: AzureOpenAIClient

    init(config: AzureModelsConfig) {
        client = AzureOpenAIClient(config: config)
    }

    func stream(
        action: WritingAction,
        prompt: PromptBuilder.BuiltPrompt
    ) async -> AsyncThrowingStream<String, Error> {
        guard TransportPreferences.allowByoFallback else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LegacyInferenceRollbackError.disabled)
            }
        }
        return await client.stream(action: action, prompt: prompt)
    }

    func consumeLastUsage() async -> LegacyInferenceUsage? {
        guard let usage = await client.consumeLastUsage() else { return nil }
        return LegacyInferenceUsage(
            model: usage.model,
            tokensIn: usage.tokensIn,
            tokensOut: usage.tokensOut
        )
    }
}

actor AzureRecommendationAdapter: RecommendationClassifying {
    private let client: AzureOpenAIClient

    init(config: AzureModelsConfig) {
        client = AzureOpenAIClient(config: config)
    }

    func classifyAction(
        fieldText: String,
        hasVisibleThread: Bool,
        toneBias: String
    ) async throws -> WritingAction? {
        // Phase 6's server classifier is deliberately deferred. During the
        // private beta, recommendation must not bypass WriterFlow's API and
        // call a locally configured Azure resource unless the server has
        // explicitly enabled the legacy rollback cohort.
        guard TransportPreferences.allowByoFallback else { return nil }
        return try await client.classifyAction(
            fieldText: fieldText,
            hasVisibleThread: hasVisibleThread,
            toneBias: toneBias
        )
    }
}
