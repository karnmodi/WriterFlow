import Foundation

/// Stage 4.5 launch checklist: "model config remotely updatable... so OpenAI model
/// retirements don't brick the app" (PRD §9 risk mitigation). Scope is deliberately
/// narrow and safe: this can only ever (a) seed the *fallback* deployment names used
/// when bootstrapping a brand-new install whose `.env` doesn't specify one, and
/// (b) fill in pricing for deployments that don't already have a pricing entry. It
/// never touches an existing user's configured deployment names or API keys, and never
/// overwrites a pricing entry the user has already edited — a fetch failure, an empty
/// `SettingsStore.remoteConfigURL` (the default), or a malformed manifest all degrade
/// to exactly today's behavior, nothing more.
///
/// No manifest is hosted yet — this is the client-side mechanism, ready for whenever a
/// maintainer publishes one (see README "Releasing"). Unlike Sparkle auto-updates, this
/// has no security implications either way: worst case is a stale fallback string,
/// which is what happens today with no remote config at all.
enum RemoteConfigFetcher {
    struct RemoteDefaults: Codable, Sendable {
        var recommendedMiniDeployment: String?
        var recommendedProDeployment: String?
        var pricing: [String: AzureModelsConfig.Pricing]?
    }

    private static let cacheFileName = "remote-defaults.json"
    private static var cacheURL: URL {
        AzureModelsConfig.appSupportURL.appendingPathComponent(cacheFileName)
    }

    /// Synchronous read of whatever was cached by the last successful `refreshInBackground`
    /// call — used at bootstrap time, which must stay synchronous and never block on network.
    static func cached() -> RemoteDefaults? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(RemoteDefaults.self, from: data)
    }

    /// Fetches and caches for *next* launch — deliberately does not mutate anything in the
    /// current session, so a live-running app never has model routing change under it
    /// mid-session from a background fetch. Silently gives up on any error: no URL
    /// configured, network failure, non-200, or malformed JSON.
    static func refreshInBackground(urlString: String) async {
        guard !urlString.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: urlString)
        else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                Log.store.info("RemoteConfigFetcher: non-2xx response, keeping existing cache")
                return
            }
            let decoded = try JSONDecoder().decode(RemoteDefaults.self, from: data)
            try FileManager.default.createDirectory(
                at: AzureModelsConfig.appSupportURL,
                withIntermediateDirectories: true
            )
            let encoded = try JSONEncoder().encode(decoded)
            try encoded.write(to: cacheURL, options: .atomic)
            Log.store.info("RemoteConfigFetcher: cached fresh remote defaults for next launch")
        } catch {
            Log.store.info("RemoteConfigFetcher: fetch failed, keeping existing cache: \(String(describing: error), privacy: .public)")
        }
    }
}
