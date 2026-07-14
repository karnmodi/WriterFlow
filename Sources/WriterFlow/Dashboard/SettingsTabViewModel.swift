import Foundation

/// Editable copy of the hot-swappable `models.json` — every change writes straight to disk
/// via `AzureModelsConfig.save()`, and `AzureOpenAIClient` re-reads the file fresh on every
/// request, so edits here apply to the very next action with no restart.
@MainActor
final class SettingsTabViewModel: ObservableObject {
    @Published var modelsConfig: AzureModelsConfig {
        didSet {
            guard modelsConfig != oldValue else { return }
            modelsConfig.save()
        }
    }

    init(modelsConfig: AzureModelsConfig) {
        self.modelsConfig = modelsConfig
    }
}
