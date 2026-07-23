import Foundation

enum InferenceTransportError: Error, LocalizedError, Sendable {
    case unsupportedAction(WritingAction)

    var errorDescription: String? {
        switch self {
        case .unsupportedAction(let action):
            return "\(action.title) is not available through WriterFlow cloud yet."
        }
    }
}

/// Mirrors the explicit-action slice of `inference-request.schema.json`.
struct InferenceRequest: Sendable, Equatable {
    struct PromptBuilderTask: Sendable, Equatable {
        let phase: String
        let flowId: UUID
        let brief: String?
        let answers: [String]
    }

    let action: WritingAction
    let operationId: UUID
    let retryOf: UUID?
    let bundleId: String
    let site: String?
    let windowClass: String?
    /// "selection" | "field" | "empty_reply"
    let targetScope: String
    let draft: String
    let selectedText: String?
    let conversation: String?
    let hasSelection: Bool
    let hasVisibleThread: Bool
    let customInstruction: String?
    let promptBuilder: PromptBuilderTask?
    /// "replace" | "insert_before"
    let outputModeHint: String
}

enum InferenceStreamEvent: Sendable, Equatable {
    case requestAccepted(requestId: String)
    case decision(intent: String, route: String, outputMode: String)
    case delta(String)
    case usageSummary(usedUnits: Int, remainingUnits: Int)
    case completed(requestId: String, promptVersion: String)
}

/// Stage 5.4 transport abstraction. `ActionEngine` routes fixGrammar here when
/// the user is signed in and `TransportPreferences.useCloudInference` is on.
@preconcurrency protocol InferenceTransport: Sendable {
    func stream(_ request: InferenceRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
}

extension InferenceTransport {
    func streamFixGrammar(_ request: InferenceRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        stream(request)
    }
}

enum InferenceRequestBuilder {
    static func build(
        action: WritingAction,
        snapshot: FieldSnapshot,
        site: String?,
        conversation: String?,
        customInstruction: String? = nil,
        promptBuilder: InferenceRequest.PromptBuilderTask? = nil,
        operationId: UUID = UUID(),
        retryOf: UUID? = nil
    ) -> InferenceRequest {
        let hasSelection = !snapshot.selectedText.isEmpty
        return InferenceRequest(
            action: action,
            operationId: operationId,
            retryOf: retryOf,
            bundleId: snapshot.appBundleID ?? "unknown",
            site: site,
            windowClass: snapshot.role,
            targetScope: hasSelection ? "selection" : "field",
            draft: snapshot.fullText,
            selectedText: hasSelection ? snapshot.selectedText : nil,
            conversation: conversation,
            hasSelection: hasSelection,
            hasVisibleThread: !(conversation?.isEmpty ?? true),
            customInstruction: customInstruction,
            promptBuilder: promptBuilder,
            outputModeHint: outputMode(action: action, customInstruction: customInstruction)
        )
    }

    static func fixGrammar(
        snapshot: FieldSnapshot,
        site: String?,
        conversation: String?,
        operationId: UUID = UUID(),
        retryOf: UUID? = nil
    ) -> InferenceRequest {
        build(
            action: .fixGrammar,
            snapshot: snapshot,
            site: site,
            conversation: conversation,
            operationId: operationId,
            retryOf: retryOf
        )
    }

    private static func outputMode(action: WritingAction, customInstruction: String?) -> String {
        if action == .promptBuilder { return "insert_before" }
        guard action == .custom, let customInstruction else { return "replace" }
        let instruction = customInstruction.lowercased()
        let insertTerms = ["title", "headline", "subject line", "summary", "tl;dr", "caption"]
        return insertTerms.contains(where: instruction.contains) ? "insert_before" : "replace"
    }
}

func cloudInferenceEnabled(
    action: WritingAction,
    useCloudInference: Bool,
    sessionState: DeviceSessionState,
    hasTransport: Bool
) -> Bool {
    guard useCloudInference, hasTransport else { return false }
    if case .signedIn = sessionState { return true }
    return false
}
