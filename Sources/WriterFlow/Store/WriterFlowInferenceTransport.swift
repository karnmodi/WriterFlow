import Foundation

enum WriterFlowInferenceError: Error, LocalizedError, Sendable {
    case notSignedIn
    case httpError(Int)
    case server(code: String, message: String)
    case malformedStream
    case invalidOrder

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to use WriterFlow's cloud models."
        case .httpError(let code): return "WriterFlow request failed (\(code))."
        case .server(_, let message): return message
        case .malformedStream: return "WriterFlow's response stream ended unexpectedly."
        case .invalidOrder: return "WriterFlow's response stream was out of order."
        }
    }
}

/// Stage 5.4 "Native transport": a standalone SSE client for
/// `POST /v2/inference/stream` (services/api/src/routes/inference.ts),
/// following Docs/contracts/inference-stream.md's canonical event order and
/// wire shape exactly — same `session.bytes(for:)` + `data:` line-parsing
/// pattern `AzureOpenAIClient.streamOnce` already uses, so this isn't a new
/// parsing approach in the codebase, just a new endpoint.
///
/// Deliberately **not yet wired into `ActionEngine`**. The reason is a real
/// interchange-shape mismatch, not caution for its own sake:
/// `AzureOpenAIClient.stream(action:prompt:)` takes a client-rendered
/// `PromptBuilder.BuiltPrompt` (a system/user string pair) because v1 builds
/// the prompt locally and sends finished text to Azure. This endpoint wants
/// the opposite — raw `content.draft`/`selectedText`/`conversation` and
/// `signals`, because the SERVER compiles the prompt (Stage 5.4's "Compile
/// prompts from server resources" checklist item, itself still open). A
/// single `InferenceTransport` protocol covering both shapes would have to
/// either stringify-and-reparse a built prompt back into raw fields (fragile
/// and wrong) or take raw fields and have `AzureOpenAIClient` build its own
/// prompt from them (a bigger, separate change to v1's working code path).
/// Deciding that interchange shape belongs with the person who reviews
/// `ActionEngine`'s wiring, not as a side effect of adding this file — so
/// this proves the client-side half of the SSE contract in isolation
/// instead.
actor WriterFlowInferenceTransport {
    private let config: WriterFlowAPIConfig
    private let session: URLSession
    private let clientVersion: String
    private let deviceSession: any DeviceSessionProviding

    init(
        deviceSession: any DeviceSessionProviding,
        config: WriterFlowAPIConfig = .resolved(),
        session: URLSession = .shared,
        clientVersion: String = "2.0.0"
    ) {
        self.deviceSession = deviceSession
        self.config = config
        self.session = session
        self.clientVersion = clientVersion
    }

    /// Mirrors `inference-request.schema.json`'s fields for exactly the
    /// fixGrammar vertical slice — not the full envelope (no Custom/Prompt
    /// Builder fields yet, matching what the server actually implements).
    struct FixGrammarRequest: Sendable {
        let operationId: UUID
        let retryOf: UUID?
        let bundleId: String
        let site: String?
        let windowClass: String?
        /// "selection" | "field" | "empty_reply" — `TargetScopeSchema`.
        let targetScope: String
        let draft: String
        let selectedText: String?
        let conversation: String?
        let hasSelection: Bool
        let hasVisibleThread: Bool
        /// "replace" | "insert_before" — `OutputModeHintSchema`.
        let outputModeHint: String
    }

    /// A lightweight local mirror of `InferenceStreamEvent`
    /// (services/shared/src/schemas/sse-events.ts) — kept separate rather
    /// than shared cross-language, since Swift and TypeScript don't share a
    /// type system here.
    enum StreamEvent: Sendable, Equatable {
        case requestAccepted(requestId: String)
        case decision(intent: String, route: String, outputMode: String)
        case delta(String)
        case usageSummary(usedUnits: Int, remainingUnits: Int)
        case completed(requestId: String, promptVersion: String)
    }

    func streamFixGrammar(_ request: FixGrammarRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Tracks which once-only events have been seen, so canonical-order
    /// violations (Docs/contracts/inference-stream.md) are rejected instead
    /// of silently accepted. A class, not a struct — `handle(json:...)`
    /// mutates it across repeated calls in the line loop below.
    private final class OrderTracker {
        var gotDecision = false
        var gotUsageSummary = false
    }

    private func run(
        _ request: FixGrammarRequest,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        let accessToken = try await deviceSession.accessToken()
        guard case .signedIn(let deviceId) = await deviceSession.state else {
            throw WriterFlowInferenceError.notSignedIn
        }

        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("inference/stream"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        urlRequest.setValue(clientVersion, forHTTPHeaderField: "X-WriterFlow-Version")
        urlRequest.setValue(deviceId, forHTTPHeaderField: "X-WriterFlow-Device")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: request))

        let (bytes, response) = try await session.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw WriterFlowInferenceError.httpError(http.statusCode)
        }

        let order = OrderTracker()
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }

            if try handle(type: type, json: json, order: order, continuation: continuation) {
                return // terminal event already sent
            }
        }
        // Stream ended without a terminal `completed`/`error` event.
        throw WriterFlowInferenceError.malformedStream
    }

    /// Returns `true` once a terminal event (`completed`) has been yielded
    /// and the caller should stop reading lines.
    private func handle(
        type: String,
        json: [String: Any],
        order: OrderTracker,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) throws -> Bool {
        switch type {
        case "request.accepted":
            continuation.yield(.requestAccepted(requestId: json["requestId"] as? String ?? ""))

        case "decision":
            if order.gotDecision { throw WriterFlowInferenceError.invalidOrder }
            order.gotDecision = true
            continuation.yield(.decision(
                intent: json["intent"] as? String ?? "",
                route: json["route"] as? String ?? "",
                outputMode: json["outputMode"] as? String ?? "replace"
            ))

        case "output.delta":
            // Canonical order: decision always precedes any delta.
            guard order.gotDecision else { throw WriterFlowInferenceError.invalidOrder }
            if let delta = json["delta"] as? String {
                continuation.yield(.delta(delta))
            }

        case "usage.summary":
            if order.gotUsageSummary { throw WriterFlowInferenceError.invalidOrder }
            order.gotUsageSummary = true
            continuation.yield(.usageSummary(
                usedUnits: json["usedUnits"] as? Int ?? 0,
                remainingUnits: json["remainingUnits"] as? Int ?? 0
            ))

        case "completed":
            continuation.yield(.completed(
                requestId: json["requestId"] as? String ?? "",
                promptVersion: json["promptVersion"] as? String ?? ""
            ))
            continuation.finish()
            return true

        case "error":
            throw WriterFlowInferenceError.server(
                code: json["code"] as? String ?? "INTERNAL_ERROR",
                message: json["message"] as? String ?? "Something went wrong. Please try again."
            )

        default:
            // Docs/contracts/inference-stream.md: an event type the client
            // doesn't recognize invalidates the stream — never guess at
            // forward-compatible handling for a closed enum like this one.
            throw WriterFlowInferenceError.malformedStream
        }
        return false
    }

    private static func body(for request: FixGrammarRequest) -> [String: Any] {
        [
            "operationId": request.operationId.uuidString.lowercased(),
            "retryOf": request.retryOf?.uuidString.lowercased() as Any,
            "mode": "explicit",
            "task": [
                "requestedAction": "fixGrammar",
                "customInstruction": NSNull(),
                "promptBuilder": NSNull(),
                "outputModeHint": request.outputModeHint
            ],
            "target": [
                "bundleId": request.bundleId,
                "site": request.site as Any,
                "windowClass": request.windowClass as Any,
                "fieldRevision": NSNull()
            ],
            "content": [
                "targetScope": request.targetScope,
                "draft": request.draft,
                "selectedText": request.selectedText as Any,
                "conversation": request.conversation as Any
            ],
            "signals": [
                "hasSelection": request.hasSelection,
                "hasVisibleThread": request.hasVisibleThread,
                "inputLength": request.draft.count,
                "appTone": NSNull()
            ],
            "personalization": NSNull()
        ]
    }
}
