import Foundation

/// BYO Azure OpenAI connection: endpoint + API key validation.
/// Deployment names live on `SettingsTabViewModel.modelsConfig` / onboarding fields
/// and are written to `models.json` before ping so the live client picks them up.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiKeyInput: String = ""
    @Published var endpointURL: String
    @Published var isValidating = false
    @Published var statusMessage: String?
    @Published var statusIsError = false
    @Published var hasSavedKey: Bool

    private var modelsConfig: AzureModelsConfig

    init(modelsConfig: AzureModelsConfig) {
        self.modelsConfig = modelsConfig
        self.endpointURL = modelsConfig.responsesURL
        self.hasSavedKey = KeychainStore.hasConfiguredAPIKey(envName: modelsConfig.defaultApiKeyEnv)
    }

    /// Keep endpoint in sync when Settings edits `models.json` elsewhere.
    func sync(from config: AzureModelsConfig) {
        modelsConfig = config
        if endpointURL != config.responsesURL {
            endpointURL = config.responsesURL
        }
        hasSavedKey = KeychainStore.hasConfiguredAPIKey(envName: config.defaultApiKeyEnv)
    }

    func validateAndSave(updatingDeploymentsFrom config: AzureModelsConfig? = nil) {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !endpoint.isEmpty else {
            statusIsError = true
            statusMessage = "Enter your Azure Responses endpoint URL."
            return
        }
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.host != nil else {
            statusIsError = true
            statusMessage = "Endpoint must be an https:// URL."
            return
        }
        guard !endpoint.contains("YOUR-RESOURCE") else {
            statusIsError = true
            statusMessage = "Replace YOUR-RESOURCE with your Azure resource hostname."
            return
        }
        guard AzureModelsConfig.isUsableResponsesURL(endpoint) else {
            statusIsError = true
            statusMessage = "Use an Azure Responses endpoint on *.openai.azure.com or *.cognitiveservices.azure.com, including ?api-version=…"
            return
        }
        guard !key.isEmpty else {
            statusIsError = true
            statusMessage = "Enter an API key first."
            return
        }

        var next = config ?? modelsConfig
        next.responsesURL = endpoint
        next.save()
        modelsConfig = next

        isValidating = true
        statusMessage = nil

        Task {
            let client = AzureOpenAIClient(config: next)
            do {
                _ = try await client.ping(
                    deployment: next.slots.default.deployment,
                    apiKeyOverride: key
                )
                KeychainStore.saveUserProvidedKey(key)
                apiKeyInput = ""
                isValidating = false
                statusIsError = false
                hasSavedKey = true
                statusMessage = "Validated ✓ — key saved in Keychain."
            } catch {
                isValidating = false
                statusIsError = true
                statusMessage = Self.friendlyMessage(for: error)
            }
        }
    }

    func clearSavedKey() {
        KeychainStore.clearUserProvidedKey()
        hasSavedKey = false
        statusIsError = false
        statusMessage = "API key removed from Keychain."
    }

    private static func friendlyMessage(for error: Error) -> String {
        if case AzureOpenAIError.httpError(let code) = error {
            switch code {
            case 401, 403: return "Invalid API key (or key lacks access to this endpoint)."
            case 404: return "Endpoint or deployment not found — check the URL and deployment name."
            case 429: return "Rate limited — try again in a moment."
            default: return "Azure returned an error (\(code))."
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Validation failed. Try again."
    }
}
