import Foundation
import LocalAuthentication
import Security

/// API key storage for bring-your-own-key (BYO).
///
/// Public path: the user pastes their Azure OpenAI key in onboarding/Settings;
/// it lives only in the macOS Keychain. Never bundled, never written to a
/// shippable artifact.
///
/// Local-dev convenience only: `bootstrap(from:)` may seed Keychain from a
/// project `.env` / Application Support `secrets.env` so rebuilds don't force
/// re-pasting. That path must never ship a publisher key.
enum KeychainStore {
    private static let service = "com.karan.writerflow"
    private static let account = "azure-openai-api-key"
    #if DEBUG
    private static let secretsFileName = "secrets.env"
    #endif

    nonisolated(unsafe) private static var cachedKey: String?

    /// True when a key is already available without prompting. Release builds
    /// consult only the session cache and Keychain; debug builds may also use
    /// contributor-only local credential files.
    static func hasConfiguredAPIKey(envName: String = "API_KEY_GPT_5-4_Pro") -> Bool {
        if let cached = cachedKey, !cached.isEmpty { return true }
        if let key = readFromKeychain(interactive: false), !key.isEmpty {
            cachedKey = key
            return true
        }
        #if DEBUG
        if let key = readFromSecretsFile(envName: envName), !key.isEmpty {
            return true
        }
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        if let envFile = DotEnvLoader.findEnvFile(startingAt: exec.deletingLastPathComponent()),
           let env = DotEnvLoader.load(from: envFile),
           let key = env[envName], !key.isEmpty {
            return true
        }
        #endif
        return false
    }

    /// Resolve the API key once per session — avoids repeated keychain prompts.
    static func resolveAPIKey(env: [String: String], envName: String) -> String? {
        if let cached = cachedKey, !cached.isEmpty { return cached }

        if let key = readFromKeychain(interactive: false), !key.isEmpty {
            cachedKey = key
            return key
        }

        #if DEBUG
        if let key = env[envName], !key.isEmpty {
            cachedKey = key
            return key
        }

        if let key = readFromSecretsFile(envName: envName), !key.isEmpty {
            cachedKey = key
            return key
        }
        #endif

        // Last resort — may show the keychain dialog once.
        if let key = readFromKeychain(interactive: true), !key.isEmpty {
            cachedKey = key
            return key
        }

        return nil
    }

    /// Save a user-provided key from onboarding / Settings (BYO path).
    @discardableResult
    static func saveUserProvidedKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        cachedKey = trimmed
        return resetAndSaveAPIKey(trimmed)
    }

    /// Removes the Keychain item and session cache. Does not delete local-dev
    /// `secrets.env` — leave that for `scripts/install.sh` / rebuild workflows.
    static func clearUserProvidedKey() {
        cachedKey = nil
        deleteAPIKey()
    }

    #if DEBUG
    /// Seed Keychain + Application Support from `.env` on launch (local development only).
    /// Touches Keychain only when the item is missing or the stored value differs —
    /// rewriting an unchanged item every launch re-triggers ACL prompts.
    static func bootstrap(from env: [String: String], keyEnvName: String) {
        guard let key = env[keyEnvName], !key.isEmpty else { return }

        writeSecretsFile(env: env, keyEnvName: keyEnvName)

        if let existing = readFromKeychain(interactive: false), existing == key {
            cachedKey = key
            return
        }

        cachedKey = key
        if resetAndSaveAPIKey(key) {
            Log.store.info("Bootstrapped Azure API key (\(keyEnvName, privacy: .public))")
        }
    }
    #endif

    // MARK: - Keychain

    private static func readFromKeychain(interactive: Bool) -> String? {
        var query = baseQuery()
        if !interactive {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        guard let data = KeychainItem.read(query, label: "Azure API key").data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// Updates in place when the item exists. Deleting and re-adding replaced
    /// the item's ACL, throwing away the "Always Allow" the user had granted
    /// this build and making the next launch prompt all over again.
    @discardableResult
    private static func resetAndSaveAPIKey(_ key: String) -> Bool {
        KeychainItem.write(
            Data(key.utf8),
            baseQuery: baseQuery(),
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            label: "Azure API key"
        )
    }

    private static func deleteAPIKey() {
        KeychainItem.delete(baseQuery())
    }

    // MARK: - Application Support fallback

    #if DEBUG
    static var secretsFileURL: URL {
        AzureModelsConfig.appSupportURL.appendingPathComponent(secretsFileName)
    }

    private static func writeSecretsFile(env: [String: String], keyEnvName: String) {
        try? FileManager.default.createDirectory(
            at: AzureModelsConfig.appSupportURL,
            withIntermediateDirectories: true
        )

        // Preserve API base URL already synced by install.sh — rewriting only
        // Azure keys used to wipe it and send Account Sign In at production.
        let existing = DotEnvLoader.load(from: secretsFileURL) ?? [:]
        var lines: [String] = []
        for (key, value) in env where key.hasPrefix("API_KEY_") || key == keyEnvName || key == "TARGET_URI" {
            lines.append("\(key)=\(value)")
        }
        let apiBase = env["WRITERFLOW_API_BASE_URL"] ?? existing["WRITERFLOW_API_BASE_URL"]
        if let apiBase, !apiBase.isEmpty {
            lines.append("WRITERFLOW_API_BASE_URL=\(apiBase)")
        }
        guard !lines.isEmpty else { return }

        let body = lines.sorted().joined(separator: "\n") + "\n"
        try? body.write(to: secretsFileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: secretsFileURL.path
        )
    }

    private static func readFromSecretsFile(envName: String) -> String? {
        guard let env = DotEnvLoader.load(from: secretsFileURL) else { return nil }
        return env[envName]
    }
    #endif
}
