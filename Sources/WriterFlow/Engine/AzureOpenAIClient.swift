import Foundation

enum AzureOpenAIError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidURL(String)
    case httpError(Int)
    case apiError
    case timeout
    case emptyResponse
    case streamEnded

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Azure API key not configured. Add it in Setup or Dashboard → Settings."
        case .invalidURL(let u): return "Invalid Azure endpoint: \(u)"
        case .httpError(let code): return "Azure API request failed (\(code)). Check your endpoint, deployment, and Azure access."
        case .apiError: return "Azure ended the request with an error. Check your deployment and try again."
        case .timeout: return "Request timed out. Check your connection and try again."
        case .emptyResponse: return "Azure returned an empty response."
        case .streamEnded: return "Stream ended unexpectedly."
        }
    }
}

/// Azure OpenAI Responses API client with SSE streaming.
actor AzureOpenAIClient {
    /// Fallback used only if `models.json` is momentarily unreadable — normal reads go
    /// through `config`, which re-reads the file fresh every call so Stage 3.4's Settings
    /// tab model-deployment edits and pricing edits live-apply without a restart.
    private let initialConfig: AzureModelsConfig
    private var config: AzureModelsConfig { AzureModelsConfig.loadFromDisk() ?? initialConfig }
    private let session: URLSession
    private let env: [String: String]

    /// Model + token usage from the most recently completed `stream()` call,
    /// for Stage 3.1 conversion logging. Cleared once read.
    private var lastUsage: (model: String, tokensIn: Int, tokensOut: Int)?

    func consumeLastUsage() -> (model: String, tokensIn: Int, tokensOut: Int)? {
        defer { lastUsage = nil }
        return lastUsage
    }

    init(config: AzureModelsConfig, session: URLSession = .shared) {
        self.initialConfig = config
        self.session = session
        #if DEBUG
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        let envFile = DotEnvLoader.findEnvFile(startingAt: exec.deletingLastPathComponent())
        self.env = DotEnvLoader.loadMerged(fileURL: envFile)
        #else
        self.env = [:]
        #endif
    }

    /// Stream text deltas for a writing action.
    func stream(
        action: WritingAction,
        prompt: PromptBuilder.BuiltPrompt,
        useHeavy: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let slot = config.slot(for: action, useHeavy: useHeavy)
                    let apiKey = try resolveAPIKey(for: slot)
                    let url = try resolveURL()
                    try await self.streamOnce(
                        url: url,
                        apiKey: apiKey,
                        deployment: slot.deployment,
                        prompt: prompt,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Non-streaming validation call (1-token ping for Settings in Phase 1.5).
    /// `apiKeyOverride` lets Settings validate a freshly pasted key before it's saved.
    func ping(deployment: String, apiKeyOverride: String? = nil) async throws -> String {
        let slot = AzureModelsConfig.Slot(deployment: deployment)
        let apiKey = try apiKeyOverride ?? resolveAPIKey(for: slot)
        let url = try resolveURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": deployment,
            "input": "ping",
            "stream": false,
            "max_output_tokens": 5
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["output_text"] as? String {
            return text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Classification call made only after the user explicitly opens the action popover.
    func classifyAction(fieldText: String, hasVisibleThread: Bool, toneBias: String) async throws -> WritingAction? {
        // Uses the heavy/reasoning slot; the user may route this to the same deployment
        // as other actions from Settings.
        let slot = config.slots.heavy
        let apiKey = try resolveAPIKey(for: slot)
        let url = try resolveURL()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 25

        let threadNote = hasVisibleThread ? "A conversation thread is visible above this field." : "No conversation thread is visible."
        let user = "App context: \(toneBias)\n\(threadNote)\nCurrent text:\n\(fieldText.isEmpty ? "(empty)" : fieldText)"
        let input: [[String: Any]] = [
            ["role": "system", "content": Prompts.recommendationSystem],
            ["role": "user", "content": user]
        ]
        let body: [String: Any] = [
            "model": slot.deployment,
            "input": input,
            "stream": false,
            // Deployments here are GPT-5-family reasoning models — a few output tokens get
            // spent on hidden reasoning before the visible word. The heavy slot is a more
            // deliberate model than the mini one this used to hit, so it may spend more of
            // that hidden budget — 60 leaves headroom while staying a fast, cheap call.
            "max_output_tokens": 60
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = Self.extractOutputText(from: json)
        else { return nil }

        return Self.parseAction(text)
    }

    /// Stage 3.3's explicit "Analyze my writing style" button — one user-triggered pass over
    /// recent accepted outputs. `samples` should already be capped by the caller (dashboard
    /// UI); this just sends them and returns a proposed style-note string for approve/reject.
    func analyzeWritingStyle(samples: [String]) async throws -> String {
        guard !samples.isEmpty else { throw AzureOpenAIError.emptyResponse }
        let slot = config.slots.grammar
        let apiKey = try resolveAPIKey(for: slot)
        let url = try resolveURL()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 20

        let joined = samples.enumerated().map { "Sample \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n")
        let input: [[String: Any]] = [
            ["role": "system", "content": Prompts.styleAnalysisSystem],
            ["role": "user", "content": joined]
        ]
        let body: [String: Any] = [
            "model": slot.deployment,
            "input": input,
            "stream": false,
            "max_output_tokens": 300
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = Self.extractOutputText(from: json),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AzureOpenAIError.emptyResponse }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractOutputText(from json: [String: Any]) -> String? {
        if let text = json["output_text"] as? String, !text.isEmpty {
            return text
        }
        guard let output = json["output"] as? [[String: Any]] else { return nil }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if let text = part["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private static func parseAction(_ text: String) -> WritingAction? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "," || $0 == ":" || $0 == "\"" })
            .first
            .map(String.init) ?? ""
        switch cleaned {
        case "elaborate": return .elaborate
        case "formal": return .formal
        case "casual": return .casual
        case "grammar", "fixgrammar", "fix_grammar": return .fixGrammar
        case "reply": return .reply
        default: return nil
        }
    }

    // MARK: - Private

    private func resolveURL() throws -> URL {
        let raw = config.responsesURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AzureModelsConfig.isUsableResponsesURL(raw),
              let url = URL(string: raw)
        else {
            throw AzureOpenAIError.invalidURL(config.responsesURL)
        }
        return url
    }

    private func resolveAPIKey(for slot: AzureModelsConfig.Slot) throws -> String {
        let envName = config.apiKeyEnv(for: slot)
        if let key = KeychainStore.resolveAPIKey(env: env, envName: envName), !key.isEmpty {
            return key
        }
        throw AzureOpenAIError.missingAPIKey
    }

    private func streamOnce(
        url: URL,
        apiKey: String,
        deployment: String,
        prompt: PromptBuilder.BuiltPrompt,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        attempt: Int = 0
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 15

        let input: [[String: Any]] = [
            ["role": "system", "content": prompt.system],
            ["role": "user", "content": prompt.user]
        ]
        let body: [String: Any] = [
            "model": deployment,
            "input": input,
            "stream": true,
            "max_output_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                if (500...599).contains(http.statusCode), attempt < 1 {
                    try await streamOnce(
                        url: url, apiKey: apiKey, deployment: deployment,
                        prompt: prompt, continuation: continuation, attempt: attempt + 1
                    )
                    return
                }
                throw AzureOpenAIError.httpError(http.statusCode)
            }

            var gotDelta = false
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                if let type = json["type"] as? String, type == "response.output_text.delta",
                   let delta = json["delta"] as? String, !delta.isEmpty {
                    gotDelta = true
                    continuation.yield(delta)
                }
                if let type = json["type"] as? String, type == "response.completed",
                   let response = json["response"] as? [String: Any],
                   let usage = response["usage"] as? [String: Any] {
                    let tokensIn = usage["input_tokens"] as? Int ?? 0
                    let tokensOut = usage["output_tokens"] as? Int ?? 0
                    lastUsage = (model: deployment, tokensIn: tokensIn, tokensOut: tokensOut)
                }
                if json["error"] != nil {
                    throw AzureOpenAIError.apiError
                }
            }
            if !gotDelta { throw AzureOpenAIError.emptyResponse }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch let error as URLError where error.code == .timedOut {
            if attempt < 1 {
                try await streamOnce(
                    url: url, apiKey: apiKey, deployment: deployment,
                    prompt: prompt, continuation: continuation, attempt: attempt + 1
                )
            } else {
                continuation.finish(throwing: AzureOpenAIError.timeout)
            }
        } catch {
            if attempt < 1, shouldRetry(error) {
                try await streamOnce(
                    url: url, apiKey: apiKey, deployment: deployment,
                    prompt: prompt, continuation: continuation, attempt: attempt + 1
                )
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    private func validateHTTP(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw AzureOpenAIError.httpError(http.statusCode)
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if case AzureOpenAIError.httpError(let code) = error {
            return (500...599).contains(code)
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        }
        return false
    }
}
