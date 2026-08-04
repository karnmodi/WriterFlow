import Foundation

enum WriterFlowInferenceError: Error, LocalizedError, Sendable {
    case notSignedIn
    case httpError(Int)
    case server(code: String, message: String)
    case malformedStream
    case invalidOrder
    case firstTokenTimeout
    case rateLimited
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in to use WriterFlow's cloud models."
        case .httpError(let code): return "WriterFlow request failed (\(code))."
        case .server(_, let message): return message
        case .malformedStream: return "WriterFlow's response stream ended unexpectedly."
        case .invalidOrder: return "WriterFlow's response stream was out of order."
        case .firstTokenTimeout:
            return "The model took too long to start — it may be overloaded. Please try again."
        case .rateLimited:
            return "The writing model is at capacity. Please try again in a moment."
        case .modelUnavailable:
            return "The writing model is temporarily unavailable. Please try again."
        }
    }
}

/// Stage 5.4 native transport: SSE client for `POST /v2/inference/stream`
/// (services/api/src/routes/inference.ts), following
/// Docs/contracts/inference-stream.md's canonical event order.
actor WriterFlowInferenceTransport: InferenceTransport {
    private let config: WriterFlowAPIConfig
    private let session: URLSession
    private let clientVersion: String
    private let deviceSession: any DeviceSessionProviding
    private let firstTokenTimeout: Duration

    init(
        deviceSession: any DeviceSessionProviding,
        config: WriterFlowAPIConfig = .resolved(),
        session: URLSession = .shared,
        clientVersion: String = "2.0.0",
        firstTokenTimeout: Duration = WriterFlowInferenceTransport.defaultFirstTokenTimeout
    ) {
        self.deviceSession = deviceSession
        self.config = config
        self.session = session
        self.clientVersion = clientVersion
        self.firstTokenTimeout = firstTokenTimeout
    }

    nonisolated func stream(_ request: InferenceRequest) -> AsyncThrowingStream<InferenceStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.run(request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                // `run` only finishes the continuation on a terminal `completed`
                // event, and `finish()` is a no-op once already finished. Calling
                // it on every non-throwing exit makes it structurally impossible
                // for a returned-but-unfinished producer to leave the consumer's
                // `for try await` suspended forever — the preview card renders
                // that as a spinner nothing can clear.
                continuation.finish()
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

    /// Deadline for the *first* piece of visible content. Deliberately not a
    /// budget for the whole response — Prompt Builder and Elaborate routinely
    /// generate for longer than this. Injectable so tests can exercise the
    /// watchdog without waiting out the production value.
    static let defaultFirstTokenTimeout = Duration.seconds(15)

    /// Which child of the streaming task group reported back. The watchdog
    /// retiring is not a reason to stop reading, so the two cases have to be
    /// distinguishable.
    private enum StreamChild: Sendable {
        case consumerFinished
        case watchdogRetired
    }

    private func run(
        _ request: InferenceRequest,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) async throws {
        let accessToken = try await deviceSession.accessToken()
        guard case .signedIn(let deviceId) = await deviceSession.state else {
            throw WriterFlowInferenceError.notSignedIn
        }
        try await runAttempt(
            request,
            accessToken: accessToken,
            deviceId: deviceId,
            idempotencyKey: UUID().uuidString,
            mayRefresh: true,
            continuation: continuation
        )
    }

    private func runAttempt(
        _ request: InferenceRequest,
        accessToken: String,
        deviceId: String,
        idempotencyKey: String,
        mayRefresh: Bool,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) async throws {
        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("inference/stream"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        urlRequest.setValue(clientVersion, forHTTPHeaderField: "X-WriterFlow-Version")
        urlRequest.setValue(deviceId, forHTTPHeaderField: "X-WriterFlow-Device")
        // URLSession inactivity budget — the timer resets on every received
        // chunk, so it guards a stalled connection, not total response length.
        // The watchdog below adds a stricter deadline on the *first* token so
        // SSE keepalives alone cannot keep a spinner alive.
        urlRequest.timeoutInterval = 45
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: request))

        let (bytes, response) = try await session.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 401, mayRefresh {
                let refreshed = try await deviceSession.forceRefreshAccessToken()
                try await runAttempt(
                    request,
                    accessToken: refreshed,
                    deviceId: deviceId,
                    idempotencyKey: idempotencyKey,
                    mayRefresh: false,
                    continuation: continuation
                )
                return
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                await deviceSession.markSessionInvalid()
                throw WriterFlowInferenceError.notSignedIn
            }
            let bodyMessage = await Self.errorMessage(from: bytes)
            if http.statusCode == 429 {
                throw WriterFlowInferenceError.server(
                    code: "RATE_LIMITED",
                    message: bodyMessage ?? WriterFlowInferenceError.rateLimited.errorDescription!
                )
            }
            if http.statusCode == 503 {
                throw WriterFlowInferenceError.server(
                    code: "MODEL_UNAVAILABLE",
                    message: bodyMessage ?? WriterFlowInferenceError.modelUnavailable.errorDescription!
                )
            }
            if let message = bodyMessage {
                throw WriterFlowInferenceError.server(code: "HTTP_\(http.statusCode)", message: message)
            }
            throw WriterFlowInferenceError.httpError(http.statusCode)
        }

        let firstTokenGate = FirstTokenGate()
        try await withThrowingTaskGroup(of: StreamChild.self) { group in
            let firstTokenTimeout = self.firstTokenTimeout
            group.addTask {
                try await Task.sleep(for: firstTokenTimeout)
                if await firstTokenGate.stillWaiting {
                    throw WriterFlowInferenceError.firstTokenTimeout
                }
                return .watchdogRetired
            }
            group.addTask {
                try await self.consumeSSE(
                    bytes: bytes,
                    firstTokenGate: firstTokenGate,
                    continuation: continuation
                )
                return .consumerFinished
            }

            // Drain until the SSE reader itself finishes. Taking whichever child
            // completed first meant that once content had arrived the retiring
            // watchdog won the race at exactly `firstTokenTimeout` and the
            // following `cancelAll()` tore down a perfectly healthy stream —
            // which is why every generation longer than that hung or failed.
            while let child = try await group.next() {
                if case .consumerFinished = child { break }
            }
            group.cancelAll()
        }
    }

    private func consumeSSE(
        bytes: URLSession.AsyncBytes,
        firstTokenGate: FirstTokenGate,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
    ) async throws {
        // Owned by this one reader task rather than passed in from the actor,
        // so nothing outside the task can reach its mutable state.
        let order = OrderTracker()
        for try await line in bytes.lines {
            // Throws rather than returns: a silent return here would unwind all
            // the way out of `run` without finishing the continuation.
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }

            if type == "output.delta" {
                await firstTokenGate.markArrived()
            }
            if try handle(type: type, json: json, order: order, continuation: continuation) {
                await firstTokenGate.markArrived()
                return
            }
        }
        // Stream ended without a terminal `completed`/`error` event.
        throw WriterFlowInferenceError.malformedStream
    }

    /// Tracks whether any visible rewrite content (or a terminal event) has
    /// arrived — used so a concurrent watchdog can fail hung silent reasoning.
    private actor FirstTokenGate {
        private(set) var stillWaiting = true

        func markArrived() {
            stillWaiting = false
        }
    }

    /// Returns `true` once a terminal event (`completed`) has been yielded
    /// and the caller should stop reading lines.
    private func handle(
        type: String,
        json: [String: Any],
        order: OrderTracker,
        continuation: AsyncThrowingStream<InferenceStreamEvent, Error>.Continuation
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
            let code = (json["code"] as? String ?? "INTERNAL_ERROR").uppercased()
            let message = json["message"] as? String
            switch code {
            case "RATE_LIMITED":
                throw WriterFlowInferenceError.server(
                    code: code,
                    message: message ?? WriterFlowInferenceError.rateLimited.errorDescription!
                )
            case "MODEL_UNAVAILABLE":
                throw WriterFlowInferenceError.server(
                    code: code,
                    message: message ?? WriterFlowInferenceError.modelUnavailable.errorDescription!
                )
            default:
                throw WriterFlowInferenceError.server(
                    code: code,
                    message: message ?? "Something went wrong. Please try again."
                )
            }

        default:
            // Docs/contracts/inference-stream.md: an event type the client
            // doesn't recognize invalidates the stream — never guess at
            // forward-compatible handling for a closed enum like this one.
            throw WriterFlowInferenceError.malformedStream
        }
        return false
    }

    private static func body(for request: InferenceRequest) -> [String: Any] {
        // Omit optional UUID fields when unset. JSON null for `retryOf` fails
        // the server's Zod envelope (`z.uuid().optional()` is not nullable).
        var body: [String: Any] = [
            "operationId": request.operationId.uuidString.lowercased(),
            "mode": "explicit",
            "task": [
                "requestedAction": request.action.apiValue,
                "customInstruction": request.customInstruction as Any,
                "promptBuilder": promptBuilderBody(request.promptBuilder),
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
                "appTone": appTone(for: request.site)
            ],
            // Local history, memory notes, and app-rule instructions are
            // intentionally never uploaded. Only the reviewed closed-enum
            // appTone signal above crosses the boundary in private beta.
            "personalization": NSNull()
        ]
        if let retryOf = request.retryOf {
            body["retryOf"] = retryOf.uuidString.lowercased()
        }
        return body
    }

    private static func errorMessage(from bytes: URLSession.AsyncBytes) async -> String? {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4_096 { break }
            }
        } catch {
            return nil
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? String,
            !message.isEmpty
        else {
            return nil
        }
        return message
    }

    private static func appTone(for site: String?) -> Any {
        switch site {
        case "gmail", "outlook", "linkedin":
            return "formal"
        case "slack", "whatsapp-web", "whatsapp-desktop", "telegram":
            return "casual"
        default:
            return "neutral"
        }
    }

    private static func promptBuilderBody(_ task: InferenceRequest.PromptBuilderTask?) -> Any {
        guard let task else { return NSNull() }
        return [
            "phase": task.phase,
            "flowId": task.flowId.uuidString.lowercased(),
            "brief": task.brief as Any,
            "answers": task.answers
        ]
    }
}
