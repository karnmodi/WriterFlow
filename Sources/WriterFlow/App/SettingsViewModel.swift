import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiKeyInput: String = ""
    @Published var isValidating = false
    @Published var statusMessage: String?
    @Published var statusIsError = false

    private let modelsConfig: AzureModelsConfig

    init(modelsConfig: AzureModelsConfig) {
        self.modelsConfig = modelsConfig
    }

    func validateAndSave() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            statusIsError = true
            statusMessage = "Enter an API key first."
            return
        }

        isValidating = true
        statusMessage = nil

        Task {
            let client = AzureOpenAIClient(config: modelsConfig)
            do {
                _ = try await client.ping(deployment: modelsConfig.slots.default.deployment, apiKeyOverride: key)
                KeychainStore.saveUserProvidedKey(key)
                isValidating = false
                statusIsError = false
                statusMessage = "Validated ✓ — key saved."
            } catch {
                isValidating = false
                statusIsError = true
                statusMessage = Self.friendlyMessage(for: error)
            }
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        if case AzureOpenAIError.httpError(let code, _) = error {
            switch code {
            case 401, 403: return "Invalid API key."
            case 429: return "Rate limited — try again in a moment."
            default: return "Azure returned an error (\(code))."
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Validation failed. Try again."
    }
}
