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

/// Mirrors the strict explicit/auto/adjust union in `inference-request.schema.json`.
struct InferenceRequest: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case explicit
        case auto(directive: String?)
        case adjust(parentOperationId: UUID, instruction: String, priorOutput: String)
    }

    struct PromptBuilderTask: Sendable, Equatable {
        let phase: String
        let flowId: UUID
        let brief: String?
        let answers: [String]
    }

    let action: WritingAction
    let mode: Mode
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
    let appCategory: String
    let destinationKind: String
    let composeSurface: String
    let draftState: String
    let contentShape: String
    let constraintCount: Int
    let appTone: String
    let languageHint: String?
    let fieldRevision: String?
    let customInstruction: String?
    let promptBuilder: PromptBuilderTask?
    /// "replace" | "insert_before"
    let outputModeHint: String
}

enum InferenceStreamEvent: Sendable, Equatable {
    case requestAccepted(requestId: String)
    case decision(intent: String, route: String, outputMode: String)
    case skillDecision(
        skillId: String,
        skillVersion: String,
        label: String,
        confidence: Double,
        route: String,
        outputMode: String,
        reasonCode: String?,
        executionMode: String
    )
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
        let trimmedConversation = Prompts.trimmedConversation(conversation, for: action)
        return InferenceRequest(
            action: action,
            mode: .explicit,
            operationId: operationId,
            retryOf: retryOf,
            bundleId: snapshot.appBundleID ?? "unknown",
            site: site,
            windowClass: snapshot.role,
            targetScope: hasSelection ? "selection" : "field",
            draft: snapshot.fullText,
            selectedText: hasSelection ? snapshot.selectedText : nil,
            conversation: trimmedConversation,
            hasSelection: hasSelection,
            hasVisibleThread: !(trimmedConversation?.isEmpty ?? true),
            appCategory: ContextSignalBuilder.appCategory(site: site),
            destinationKind: ContextSignalBuilder.destinationKind(site: site, hasThread: !(trimmedConversation?.isEmpty ?? true)),
            composeSurface: ContextSignalBuilder.composeSurface(hasThread: !(trimmedConversation?.isEmpty ?? true)),
            draftState: ContextSignalBuilder.draftState(text: snapshot.actionText),
            contentShape: ContextSignalBuilder.contentShape(text: snapshot.actionText, site: site),
            constraintCount: ContextSignalBuilder.constraintCount(text: customInstruction ?? snapshot.actionText),
            appTone: ContextSignalBuilder.appTone(site: site),
            languageHint: ContextSignalBuilder.languageHint(text: snapshot.actionText),
            fieldRevision: TargetFingerprint.contentRevision(snapshot: snapshot),
            customInstruction: customInstruction,
            promptBuilder: promptBuilder,
            outputModeHint: outputMode(action: action, customInstruction: customInstruction)
        )
    }

    static func auto(
        capsule: ContextCapsule,
        directive: String? = nil,
        operationId: UUID = UUID(),
        retryOf: UUID? = nil
    ) -> InferenceRequest {
        let snapshot = capsule.snapshot
        let signals = capsule.signals
        return InferenceRequest(
            action: .custom,
            mode: .auto(directive: directive.map { String($0.prefix(2_000)) }),
            operationId: operationId,
            retryOf: retryOf,
            bundleId: snapshot.appBundleID ?? "unknown",
            site: capsule.site,
            windowClass: snapshot.role,
            targetScope: signals.targetScope,
            draft: snapshot.fullText,
            selectedText: signals.hasSelection ? snapshot.selectedText : nil,
            conversation: capsule.conversation,
            hasSelection: signals.hasSelection,
            hasVisibleThread: signals.hasVisibleThread,
            appCategory: signals.appCategory,
            destinationKind: signals.destinationKind,
            composeSurface: signals.composeSurface,
            draftState: signals.draftState,
            contentShape: signals.contentShape,
            constraintCount: signals.constraintCount,
            appTone: signals.appTone,
            languageHint: signals.languageHint,
            fieldRevision: capsule.fingerprint.contentRevision,
            customInstruction: nil,
            promptBuilder: nil,
            outputModeHint: "replace"
        )
    }

    static func adjust(
        capsule: ContextCapsule,
        parentOperationId: UUID,
        instruction: String,
        priorOutput: String,
        operationId: UUID = UUID()
    ) -> InferenceRequest {
        var request = auto(capsule: capsule, operationId: operationId)
        request = InferenceRequest(
            action: .custom,
            mode: .adjust(
                parentOperationId: parentOperationId,
                instruction: String(instruction.prefix(2_000)),
                priorOutput: String(priorOutput.prefix(8_000))
            ),
            operationId: request.operationId,
            retryOf: nil,
            bundleId: request.bundleId,
            site: request.site,
            windowClass: request.windowClass,
            targetScope: request.targetScope,
            draft: request.draft,
            selectedText: request.selectedText,
            conversation: request.conversation,
            hasSelection: request.hasSelection,
            hasVisibleThread: request.hasVisibleThread,
            appCategory: request.appCategory,
            destinationKind: request.destinationKind,
            composeSurface: request.composeSurface,
            draftState: request.draftState,
            contentShape: request.contentShape,
            constraintCount: request.constraintCount,
            appTone: request.appTone,
            languageHint: request.languageHint,
            fieldRevision: request.fieldRevision,
            customInstruction: nil,
            promptBuilder: nil,
            outputModeHint: "replace"
        )
        return request
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

/// Keeps transport rollout state distinct from authentication state. The
/// auto path previously collapsed every failed precondition into "Sign in",
/// even when the user had a valid session and only the cohort's cloud switch
/// was off.
func automaticWritingUnavailableMessage(
    useCloudInference: Bool,
    sessionState: DeviceSessionState,
    hasTransport: Bool
) -> String? {
    guard useCloudInference else {
        return "Automatic writing is not enabled for this cohort."
    }
    guard hasTransport else {
        return "WriterFlow's automatic writing service is unavailable. Try again shortly."
    }
    switch sessionState {
    case .signedIn:
        return nil
    case .pairing:
        return "Finish signing in before using automatic writing."
    case .needsRePair:
        return "Your session expired. Open Dashboard → Account and sign in again."
    case .signedOut:
        return "Sign in to use WriterFlow's automatic writing skills."
    }
}
