import SwiftUI

struct SettingsTabView: View {
    @StateObject private var viewModel: SettingsTabViewModel
    @StateObject private var apiKeyViewModel: SettingsViewModel
    @ObservedObject private var settings = SettingsStore.shared

    init(modelsConfig: AzureModelsConfig) {
        _viewModel = StateObject(wrappedValue: SettingsTabViewModel(modelsConfig: modelsConfig))
        _apiKeyViewModel = StateObject(wrappedValue: SettingsViewModel(modelsConfig: modelsConfig))
    }

    var body: some View {
        Form {
            hotkeySection
            iconBehaviorSection
            apiKeySection
            modelsSection
            reliabilitySection
            generalSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
        Section("Global Hotkey") {
            HStack(spacing: 12) {
                HotkeyRecorderView(combo: $settings.hotkeyCombo)
                Button("Reset to Default (⌃⌥Space)") {
                    settings.hotkeyCombo = .default
                }
                .buttonStyle(.link)
            }
            Text("Click, then press the key combo you want. It takes effect immediately — no restart. If another app already owns that combo, WriterFlow reverts automatically and tells you below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = settings.hotkeyStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(settings.hotkeyStatusIsError ? .red : .green)
            }
        }
    }

    // MARK: - Icon behavior

    private var iconBehaviorSection: some View {
        Section("Floating Icon") {
            Picker("Show icon", selection: $settings.iconMode) {
                Text("While typing").tag(IconMode.onTyping)
                Text("On field focus").tag(IconMode.alwaysOnFocus)
                Text("Hotkey only").tag(IconMode.hotkeyOnly)
            }
            .pickerStyle(.radioGroup)
            Text(iconModeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iconModeExplanation: String {
        switch settings.iconMode {
        case .onTyping:
            return "Icon appears near the caret while you're actively typing, and hides a moment after you stop. The default — icon shows up only when you're likely to want it."
        case .alwaysOnFocus:
            return "Icon appears the instant any text field gets focus, even before you type a single character."
        case .hotkeyOnly:
            return "No floating icon at all — actions only open via the hotkey below. Best for a fully quiet menu bar experience."
        }
    }

    // MARK: - API key

    private var apiKeySection: some View {
        Section("Azure OpenAI API Key") {
            SecureField("API key", text: $apiKeyViewModel.apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .disabled(apiKeyViewModel.isValidating)
            HStack(spacing: 10) {
                Button {
                    apiKeyViewModel.validateAndSave()
                } label: {
                    if apiKeyViewModel.isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Validate & Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyViewModel.isValidating || apiKeyViewModel.apiKeyInput.isEmpty)

                if let message = apiKeyViewModel.statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(apiKeyViewModel.statusIsError ? .red : .green)
                }
            }
            Text("Validated with a 1-token test call, then stored in the macOS Keychain — never in logs, UserDefaults, or any file WriterFlow writes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        Section("Models") {
            LabeledContent("Default") {
                TextField("deployment name", text: $viewModel.modelsConfig.slots.default.deployment)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            Text("Used for Elaborate, Formal, Casual, Reply, Prompt Builder, Custom.")
                .font(.caption2).foregroundStyle(.tertiary)

            LabeledContent("Grammar") {
                TextField("deployment name", text: $viewModel.modelsConfig.slots.grammar.deployment)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            Text("Used for Fix Grammar and the background tone recommender.")
                .font(.caption2).foregroundStyle(.tertiary)

            LabeledContent("Heavy") {
                TextField("deployment name", text: $viewModel.modelsConfig.slots.heavy.deployment)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
            Text("Reserved for a future higher-quality pass — not yet wired to any action.")
                .font(.caption2).foregroundStyle(.tertiary)

            Text("Changes save to models.json immediately and apply to the very next action — no restart needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reliability

    private var reliabilitySection: some View {
        Section("Reliability") {
            Toggle("Always paste via clipboard", isOn: $settings.forceClipboardFallback)
            Text("WriterFlow normally writes the rewritten text directly into the field, falling back to a clipboard paste only if that fails. Turn this on to always use the clipboard paste — useful if direct writes visibly glitch in a particular app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)

            Picker("Keep history for", selection: $settings.historyRetention) {
                ForEach(RetentionPeriod.allCases, id: \.self) { period in
                    Text(period.label).tag(period)
                }
            }
            Text("Conversions older than this are deleted automatically. Applies immediately — switching to a shorter window purges older entries right away.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
