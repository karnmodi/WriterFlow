import SwiftUI

struct SettingsTabView: View {
    @StateObject private var viewModel: SettingsTabViewModel
    @StateObject private var apiKeyViewModel: SettingsViewModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var watchdog = AXWatchdog.shared

    init(modelsConfig: AzureModelsConfig) {
        _viewModel = StateObject(wrappedValue: SettingsTabViewModel(modelsConfig: modelsConfig))
        _apiKeyViewModel = StateObject(wrappedValue: SettingsViewModel(modelsConfig: modelsConfig))
    }

    var body: some View {
        DashboardFormContainer(
            header: DashboardPageHeader(
                title: "Settings",
                subtitle: "Shortcuts, models, reliability, and general preferences. Changes apply immediately without restarting."
            )
        ) {
            VStack(alignment: .leading, spacing: DashboardChrome.sectionSpacing) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    hotkeyCard
                    iconBehaviorCard
                    apiKeyCard
                    reliabilityCard
                    generalCard
                }

                modelsCard
            }
        }
    }

    // MARK: - Hotkey

    private var hotkeyCard: some View {
        DashboardCard(
            title: "Global Hotkey",
            subtitle: "Opens the action menu from anywhere",
            icon: "command",
            iconTint: .blue
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HotkeyRecorderView(combo: $settings.hotkeyCombo)

                Button("Reset to Default (⌃⌥Space)") {
                    settings.hotkeyCombo = .default
                }
                .buttonStyle(.link)

                if let message = settings.hotkeyStatusMessage {
                    StatusBanner(message: message, isError: settings.hotkeyStatusIsError)
                }

                DashboardSectionCaption(
                    text: "Click the shortcut field, then press your preferred key combo. WriterFlow registers it immediately. If another app already owns that combo, WriterFlow reverts automatically and shows an error above."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Icon behavior

    private var iconBehaviorCard: some View {
        DashboardCard(
            title: "Floating Icon",
            icon: "cursorarrow.rays",
            iconTint: .orange
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Show icon", selection: $settings.iconMode) {
                    Text("While typing").tag(IconMode.onTyping)
                    Text("On field focus").tag(IconMode.alwaysOnFocus)
                    Text("Hotkey only").tag(IconMode.hotkeyOnly)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                DashboardSectionCaption(text: iconModeExplanation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconModeExplanation: String {
        switch settings.iconMode {
        case .onTyping:
            return "Icon appears near the caret while you're actively typing, and hides a moment after you stop. The default — icon shows up only when you're likely to want it."
        case .alwaysOnFocus:
            return "Icon appears the instant any text field gets focus, even before you type a single character."
        case .hotkeyOnly:
            return "No floating icon at all — actions only open via the global hotkey. Best for a fully quiet menu bar experience."
        }
    }

    // MARK: - API key

    private var apiKeyCard: some View {
        DashboardCard(
            title: "Azure OpenAI API Key",
            icon: "key.fill",
            iconTint: .yellow
        ) {
            VStack(alignment: .leading, spacing: 8) {
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

                DashboardSectionCaption(
                    text: "Validated with a 1-token test call, then stored in the macOS Keychain — never in logs, UserDefaults, or any file WriterFlow writes."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Models

    private var modelsCard: some View {
        DashboardCard(
            title: "Models",
            subtitle: "Deployment name and estimated $/1M-token pricing per action class.",
            icon: "cpu",
            iconTint: .purple
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        modelSlots
                    }
                    VStack(spacing: 10) {
                        modelSlots
                    }
                }
                DashboardSectionCaption(
                    text: "Changes save to models.json immediately and apply to the very next action — no restart needed. Pricing feeds the Usage tab's estimated cost."
                )
            }
        }
    }

    @ViewBuilder
    private var modelSlots: some View {
        ModelSlotCard(
            title: "Default",
            usageDescription: "Elaborate, Formal, Casual, Reply, Prompt Builder, Custom",
            deployment: $viewModel.modelsConfig.slots.default.deployment,
            inputPrice: pricingBinding(for: viewModel.modelsConfig.slots.default.deployment, \.inputPerMillion),
            outputPrice: pricingBinding(for: viewModel.modelsConfig.slots.default.deployment, \.outputPerMillion)
        )
        ModelSlotCard(
            title: "Grammar",
            usageDescription: "Fix Grammar",
            deployment: $viewModel.modelsConfig.slots.grammar.deployment,
            inputPrice: pricingBinding(for: viewModel.modelsConfig.slots.grammar.deployment, \.inputPerMillion),
            outputPrice: pricingBinding(for: viewModel.modelsConfig.slots.grammar.deployment, \.outputPerMillion)
        )
        ModelSlotCard(
            title: "Heavy",
            usageDescription: "The recommended-action classifier — starts running in the background as soon as you begin typing.",
            deployment: $viewModel.modelsConfig.slots.heavy.deployment,
            inputPrice: pricingBinding(for: viewModel.modelsConfig.slots.heavy.deployment, \.inputPerMillion),
            outputPrice: pricingBinding(for: viewModel.modelsConfig.slots.heavy.deployment, \.outputPerMillion)
        )
    }

    /// Pricing is keyed by deployment name (see `AzureModelsConfig.pricing`), not by slot —
    /// this binding reads/writes the entry for whatever deployment name is currently in that
    /// slot, seeding from `.fallback` the first time a given deployment is priced.
    private func pricingBinding(
        for deployment: String,
        _ keyPath: WritableKeyPath<AzureModelsConfig.Pricing, Double>
    ) -> Binding<Double> {
        Binding(
            get: { viewModel.modelsConfig.pricing[deployment, default: .fallback][keyPath: keyPath] },
            set: { newValue in
                var pricing = viewModel.modelsConfig.pricing[deployment] ?? .fallback
                pricing[keyPath: keyPath] = newValue
                viewModel.modelsConfig.pricing[deployment] = pricing
            }
        )
    }

    // MARK: - Reliability

    private var reliabilityCard: some View {
        DashboardCard(
            title: "Reliability",
            icon: "arrow.triangle.2.circlepath",
            iconTint: .teal
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Always paste via clipboard", isOn: $settings.forceClipboardFallback)
                DashboardSectionCaption(
                    text: "WriterFlow normally writes the rewritten text directly into the field, falling back to a clipboard paste only if that fails. Turn this on to always use the clipboard paste — useful if direct writes visibly glitch in a particular app."
                )

                if !watchdog.disabledBundleIDs.isEmpty {
                    Divider()
                    Text("Paused this session")
                        .font(.caption.bold())
                    ForEach(Array(watchdog.disabledBundleIDs).sorted(), id: \.self) { bundleID in
                        HStack {
                            Text(AXWatchdog.displayName(forBundleID: bundleID))
                                .font(.caption)
                            Spacer()
                            Button("Re-enable") {
                                watchdog.reenable(bundleID: bundleID)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    DashboardSectionCaption(
                        text: "WriterFlow automatically pauses itself for an app after 3 consecutive accessibility failures, rather than repeatedly failing silently. This resets on relaunch, or re-enable it above."
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - General

    private var generalCard: some View {
        DashboardCard(
            title: "General",
            icon: "gearshape.2",
            iconTint: .gray
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                Picker("Keep history for", selection: $settings.historyRetention) {
                    ForEach(RetentionPeriod.allCases, id: \.self) { period in
                        Text(period.label).tag(period)
                    }
                }

                DashboardSectionCaption(
                    text: "Conversions older than the retention period are deleted automatically. Switching to a shorter window purges older entries right away."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModelSlotCard: View {
    let title: String
    let usageDescription: String
    @Binding var deployment: String
    @Binding var inputPrice: Double
    @Binding var outputPrice: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextField("deployment name", text: $deployment)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))

            HStack(spacing: 8) {
                priceField(label: "Input $/1M", value: $inputPrice)
                priceField(label: "Output $/1M", value: $outputPrice)
            }

            Text(usageDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                }
        }
    }

    private func priceField(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
        }
    }
}
