import Foundation

/// Hot-swappable Azure OpenAI model routing. Lives in Application Support;
/// bootstrapped from `.env` on first launch.
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

    struct Slots: Codable, Sendable, Equatable {
        var `default`: Slot
        var grammar: Slot
        var heavy: Slot
    }

    func slot(for action: WritingAction, useHeavy: Bool = false) -> Slot {
        if useHeavy { return slots.heavy }
        if action == .fixGrammar { return slots.grammar }
        return slots.default
    }

    func apiKeyEnv(for slot: Slot) -> String {
        slot.apiKeyEnv ?? defaultApiKeyEnv
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
            Log.store.info("Bootstrapped models.json from .env")
        }
        return bootstrapped
    }

    static func loadFromDisk() -> AzureModelsConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(AzureModelsConfig.self, from: data)
    }

    private static func bootstrapFromEnv() -> AzureModelsConfig {
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        let envFile = DotEnvLoader.findEnvFile(startingAt: exec.deletingLastPathComponent())
        let env = DotEnvLoader.loadMerged(fileURL: envFile)

        let responsesURL = env["TARGET_URI"]
            ?? "https://YOUR-RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=2025-04-01-preview"

        let defaultKeyEnv = env.keys.first(where: { $0.hasPrefix("API_KEY_") }) ?? "API_KEY_GPT_5-4_Pro"

        func deployment(_ key: String, fallback: String) -> String {
            env[key] ?? fallback
        }

        return AzureModelsConfig(
            responsesURL: responsesURL,
            defaultApiKeyEnv: defaultKeyEnv,
            slots: Slots(
                default: Slot(
                    deployment: deployment("AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini", fallback: "gpt-5.4-mini")
                ),
                grammar: Slot(
                    deployment: deployment("AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini", fallback: "gpt-5.4-mini")
                ),
                heavy: Slot(
                    deployment: deployment("AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Pro", fallback: "gpt-5.4-pro"),
                    apiKeyEnv: env[defaultKeyEnv] != nil ? defaultKeyEnv : nil
                )
            )
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
