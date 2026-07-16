import Foundation

/// Hot-swappable Azure OpenAI model routing in Application Support. Release
/// installs start with non-secret placeholders completed in Setup; debug builds
/// may bootstrap contributor values from a local `.env`.
struct AzureModelsConfig: Codable, Sendable, Equatable {
    struct Slot: Codable, Sendable, Equatable {
        var deployment: String
        /// Optional per-slot API key env var name; falls back to `defaultApiKeyEnv`.
        var apiKeyEnv: String?
    }

    /// Full Responses API URL (including `api-version` query param).
    var responsesURL: String
    /// Env var name for the default API key (e.g. `API_KEY_GPT_5-4_Pro`).
    var defaultApiKeyEnv: String
    var slots: Slots
    /// Per-deployment $/1M-token pricing for the Usage tab's cost estimate (Stage 3.5).
    /// Keyed by deployment name so it stays correct across slot reassignment; missing
    /// entries fall back to `Pricing.fallback` rather than silently showing $0.
    var pricing: [String: Pricing] = [:]

    struct Slots: Codable, Sendable, Equatable {
        var `default`: Slot
        var grammar: Slot
        var heavy: Slot
    }

    struct Pricing: Codable, Sendable, Equatable {
        var inputPerMillion: Double
        var outputPerMillion: Double

        /// Rough placeholder used when a deployment has no pricing entry yet — better to
        /// show an approximate, clearly-estimated cost than to silently show $0.
        static let fallback = Pricing(inputPerMillion: 0.15, outputPerMillion: 0.60)
    }

    func slot(for action: WritingAction, useHeavy: Bool = false) -> Slot {
        if useHeavy { return slots.heavy }
        if action == .fixGrammar { return slots.grammar }
        return slots.default
    }

    func apiKeyEnv(for slot: Slot) -> String {
        slot.apiKeyEnv ?? defaultApiKeyEnv
    }

    func pricing(for deployment: String) -> Pricing {
        pricing[deployment] ?? .fallback
    }

    /// Placeholder endpoint left by a fresh install before the user pastes theirs.
    var hasPlaceholderEndpoint: Bool {
        responsesURL.contains("YOUR-RESOURCE") || responsesURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Endpoint looks like a usable HTTPS Azure Responses URL.
    var hasUsableEndpoint: Bool {
        Self.isUsableResponsesURL(responsesURL) && !hasPlaceholderEndpoint
    }

    static func isUsableResponsesURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.localizedCaseInsensitiveContains("YOUR-RESOURCE"),
              let components = URLComponents(
                  string: trimmed
              ),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              (
                  host.hasSuffix(".cognitiveservices.azure.com")
                      || host.hasSuffix(".openai.azure.com")
              ),
              components.path == "/openai/responses",
              components.queryItems?.contains(where: {
                  $0.name == "api-version" && !($0.value ?? "").isEmpty
              }) == true
        else { return false }
        return true
    }

    /// Writes to `models.json` immediately — the hot-swappable config `AzureOpenAIClient`
    /// re-reads on every call, so this is how the Settings tab's model fields live-apply.
    func save() {
        try? FileManager.default.createDirectory(at: Self.appSupportURL, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.pretty.encode(self) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    // MARK: - Persistence

    static let fileName = "models.json"

    static var appSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("WriterFlow", isDirectory: true)
    }

    static var configURL: URL {
        appSupportURL.appendingPathComponent(fileName)
    }

    static func load() -> AzureModelsConfig {
        if let existing = loadFromDisk() {
            return existing
        }
        let bootstrapped = bootstrapFromEnv()
        try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.pretty.encode(bootstrapped) {
            try? data.write(to: configURL, options: .atomic)
            Log.store.info("Created initial models.json")
        }
        return bootstrapped
    }

    static func loadFromDisk() -> AzureModelsConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(AzureModelsConfig.self, from: data)
    }

    private static func bootstrapFromEnv() -> AzureModelsConfig {
        #if DEBUG
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        let envFile = DotEnvLoader.findEnvFile(startingAt: exec.deletingLastPathComponent())
        let env = DotEnvLoader.loadMerged(fileURL: envFile)
        #else
        let env: [String: String] = [:]
        #endif

        let responsesURL = env["TARGET_URI"]
            ?? "https://YOUR-RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview"

        let defaultKeyEnv = env.keys.first(where: { $0.hasPrefix("API_KEY_") }) ?? "API_KEY_GPT_5-4_Pro"

        func deployment(_ key: String, fallback: String) -> String {
            env[key] ?? fallback
        }

        let miniFallback = "gpt-5.4-mini"
        let proFallback = "gpt-5.4-pro"
        let miniDeployment = deployment("AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini", fallback: miniFallback)
        let proDeployment = deployment("AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro", fallback: proFallback)

        return AzureModelsConfig(
            responsesURL: responsesURL,
            defaultApiKeyEnv: defaultKeyEnv,
            slots: Slots(
                default: Slot(deployment: miniDeployment),
                grammar: Slot(deployment: miniDeployment),
                heavy: Slot(
                    deployment: proDeployment,
                    apiKeyEnv: env[defaultKeyEnv] != nil ? defaultKeyEnv : nil
                )
            ),
            // Editable estimates for the user's own Azure account; WriterFlow does not bill.
            pricing: [
                miniDeployment: Pricing(inputPerMillion: 0.15, outputPerMillion: 0.60),
                proDeployment: Pricing(inputPerMillion: 2.00, outputPerMillion: 8.00)
            ]
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}
