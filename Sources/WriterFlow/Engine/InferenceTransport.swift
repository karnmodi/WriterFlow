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

/// Mirrors `inference-request.schema.json`'s fixGrammar slice and
/// `InferenceStreamEvent` from the server SSE contract.
struct InferenceFixGrammarRequest: Sendable, Equatable {
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
    func streamFixGrammar(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func streamElaborate(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func streamFormal(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func streamCasual(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func streamReply(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func streamCustom(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
    func streamPromptBuilder(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error>
}

extension InferenceTransport {
    func streamElaborate(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        Self.unsupportedStream(.elaborate)
    }

    func streamFormal(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        Self.unsupportedStream(.formal)
    }

    func streamCasual(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        Self.unsupportedStream(.casual)
    }

    func streamReply(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        Self.unsupportedStream(.reply)
    }

    func streamCustom(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        Self.unsupportedStream(.custom)
    }

    func streamPromptBuilder(_ request: InferenceFixGrammarRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        Self.unsupportedStream(.promptBuilder)
    }

    private static func unsupportedStream(_ action: WritingAction) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: InferenceTransportError.unsupportedAction(action))
        }
    }
}

enum InferenceRequestBuilder {
    static func fixGrammar(
        snapshot: FieldSnapshot,
        site: String?,
        conversation: String?,
        operationId: UUID = UUID(),
        retryOf: UUID? = nil
    ) -> InferenceFixGrammarRequest {
        let hasSelection = !snapshot.selectedText.isEmpty
        return InferenceFixGrammarRequest(
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
            outputModeHint: "replace"
        )
    }
}

func cloudInferenceEnabled(
    action: WritingAction,
    useCloudInference: Bool,
    sessionState: DeviceSessionState,
    hasTransport: Bool
) -> Bool {
    guard action == .fixGrammar, useCloudInference, hasTransport else { return false }
    if case .signedIn = sessionState { return true }
    return false
}
