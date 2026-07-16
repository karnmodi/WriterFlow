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

    /// When on, Default / Grammar / Heavy all share the Default deployment name.
    @Published var useOneModelForAll: Bool = false {
        didSet {
            guard useOneModelForAll else { return }
            applyOneModelForAll()
        }
    }

    init(modelsConfig: AzureModelsConfig) {
        self.modelsConfig = modelsConfig
        let d = modelsConfig.slots.default.deployment
        self.useOneModelForAll =
            modelsConfig.slots.grammar.deployment == d
            && modelsConfig.slots.heavy.deployment == d
    }

    func applyOneModelForAll() {
        let name = modelsConfig.slots.default.deployment
        modelsConfig.slots.grammar.deployment = name
        modelsConfig.slots.heavy.deployment = name
    }

    func setDefaultDeployment(_ name: String) {
        modelsConfig.slots.default.deployment = name
        if useOneModelForAll {
            applyOneModelForAll()
        }
    }
}
