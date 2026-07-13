import Foundation

enum AzureOpenAIError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidURL(String)
    case httpError(Int, String)
    case apiError(String)
    case timeout
    case emptyResponse
    case streamEnded

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Azure API key not configured. Add it in Settings."
        case .invalidURL(let u): return "Invalid Azure endpoint: \(u)"
        case .httpError(let code, let body): return "Azure API error \(code): \(body)"
        case .apiError(let msg): return msg
        case .timeout: return "Request timed out. Check your connection and try again."
        case .emptyResponse: return "Azure returned an empty response."
        case .streamEnded: return "Stream ended unexpectedly."
        }
    }
}

/// Azure OpenAI Responses API client with SSE streaming.
actor AzureOpenAIClient {
    private let config: AzureModelsConfig
    private let session: URLSession
    private let env: [String: String]

    init(config: AzureModelsConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        let envFile = DotEnvLoader.findEnvFile(startingAt: exec.deletingLastPathComponent())
        self.env = DotEnvLoader.loadMerged(fileURL: envFile)
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
        try validateHTTP(response: response, data: data)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["output_text"] as? String {
            return text
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Non-streaming classification call for the Recommendation Engine — one word
    /// out of elaborate/formal/casual/grammar/reply, or nil if it doesn't parse.
    func classifyAction(fieldText: String, hasVisibleThread: Bool, toneBias: String) async throws -> WritingAction? {
        let slot = config.slots.grammar
        let apiKey = try resolveAPIKey(for: slot)
        let url = try resolveURL()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 8

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
            "max_output_tokens": 5
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = Self.extractOutputText(from: json)
        else { return nil }

        return Self.parseAction(text)
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
        guard let url = URL(string: config.responsesURL) else {
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
                var errData = Data()
                for try await chunk in bytes { errData.append(chunk) }
                let msg = String(data: errData, encoding: .utf8) ?? "unknown"
                if (500...599).contains(http.statusCode), attempt < 1 {
                    try await streamOnce(
                        url: url, apiKey: apiKey, deployment: deployment,
                        prompt: prompt, continuation: continuation, attempt: attempt + 1
                    )
                    return
                }
                throw AzureOpenAIError.httpError(http.statusCode, msg)
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
                if let err = json["error"] as? [String: Any],
                   let message = err["message"] as? String {
                    throw AzureOpenAIError.apiError(message)
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

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw AzureOpenAIError.httpError(http.statusCode, msg)
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if case AzureOpenAIError.httpError(let code, _) = error {
            return (500...599).contains(code)
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        }
        return false
    }
}
