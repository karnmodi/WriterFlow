import SwiftUI

struct SettingsTabView: View {
    @StateObject private var viewModel: SettingsTabViewModel
    @StateObject private var apiKeyViewModel: SettingsViewModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var watchdog = AXWatchdog.shared
    @State private var compatibilitySnapshot: [String: CompatibilityMap.Entry] = [:]

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
        .task { compatibilitySnapshot = await CompatibilityMap.shared.snapshot() }
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

    // MARK: - Azure connection (BYO)

    private var apiKeyCard: some View {
        DashboardCard(
            title: "Azure OpenAI (your key)",
            subtitle: "Bring your own Azure resource — WriterFlow never ships a shared key.",
            icon: "key.fill",
            iconTint: .yellow
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if apiKeyViewModel.hasSavedKey {
                    Label("API key saved in Keychain", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Label("No API key yet — actions will fail until you add one", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }

                Text("Responses endpoint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(
                    "https://YOUR-RESOURCE.cognitiveservices.azure.com/openai/responses?api-version=…",
                    text: $apiKeyViewModel.endpointURL
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .disabled(apiKeyViewModel.isValidating)
                .onChange(of: apiKeyViewModel.endpointURL) { _, newValue in
                    viewModel.modelsConfig.responsesURL = newValue
                }

                Text("API key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(
                    apiKeyViewModel.hasSavedKey ? "Paste a new key to replace…" : "Paste your Azure OpenAI API key",
                    text: $apiKeyViewModel.apiKeyInput
                )
                .textFieldStyle(.roundedBorder)
                .disabled(apiKeyViewModel.isValidating)

                HStack(spacing: 10) {
                    Button {
                        apiKeyViewModel.validateAndSave(updatingDeploymentsFrom: viewModel.modelsConfig)
                    } label: {
                        if apiKeyViewModel.isValidating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(apiKeyViewModel.hasSavedKey ? "Re-validate & Save" : "Validate & Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        apiKeyViewModel.isValidating
                        || apiKeyViewModel.apiKeyInput.isEmpty
                        || apiKeyViewModel.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if apiKeyViewModel.hasSavedKey {
                        Button("Remove key") {
                            apiKeyViewModel.clearSavedKey()
                        }
                        .buttonStyle(.link)
                    }
                }

                if let message = apiKeyViewModel.statusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(apiKeyViewModel.statusIsError ? .red : .green)
                }

                DashboardSectionCaption(
                    text: "Create a key in Azure Portal → your OpenAI resource → Keys and Endpoint. WriterFlow validates with a 1-token ping, then stores the key only in the macOS Keychain — never in the app bundle, logs, or UserDefaults."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { apiKeyViewModel.sync(from: viewModel.modelsConfig) }
    }

    // MARK: - Models

    private var modelsCard: some View {
        DashboardCard(
            title: "Models",
            subtitle: "Exact Azure deployment names from your resource, plus optional cost estimates.",
            icon: "cpu",
            iconTint: .purple
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use one deployment for all actions", isOn: $viewModel.useOneModelForAll)
                DashboardSectionCaption(
                    text: "On: Default, Grammar, and Heavy all call the same deployment. Off: pick a cheaper model for grammar and a stronger one for the background classifier."
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        modelSlots
                    }
                    VStack(spacing: 10) {
                        modelSlots
                    }
                }
                DashboardSectionCaption(
                    text: "Names must match Azure Portal → Deployments exactly (e.g. gpt-5.4-mini). Changes save immediately and apply to the next action. Pricing only feeds the Usage tab estimate — WriterFlow never bills you."
                )

                Divider()
                TextField("Remote config URL (optional, advanced)", text: $settings.remoteConfigURL)
                    .textFieldStyle(.roundedBorder)
                DashboardSectionCaption(
                    text: "Leave blank (default). If set, WriterFlow may fetch maintainer-published fallback deployment names/pricing for brand-new installs only — never your key or your configured deployments."
                )
            }
        }
    }

    @ViewBuilder
    private var modelSlots: some View {
        ModelSlotCard(
            title: "Default",
            usageDescription: "Elaborate, Formal, Casual, Reply, Prompt Builder, Custom",
            deployment: Binding(
                get: { viewModel.modelsConfig.slots.default.deployment },
                set: { viewModel.setDefaultDeployment($0) }
            ),
            inputPrice: pricingBinding(for: viewModel.modelsConfig.slots.default.deployment, \.inputPerMillion),
            outputPrice: pricingBinding(for: viewModel.modelsConfig.slots.default.deployment, \.outputPerMillion),
            isEnabled: true
        )
        ModelSlotCard(
            title: "Grammar",
            usageDescription: "Fix Grammar",
            deployment: $viewModel.modelsConfig.slots.grammar.deployment,
            inputPrice: pricingBinding(for: viewModel.modelsConfig.slots.grammar.deployment, \.inputPerMillion),
            outputPrice: pricingBinding(for: viewModel.modelsConfig.slots.grammar.deployment, \.outputPerMillion),
            isEnabled: !viewModel.useOneModelForAll
        )
        ModelSlotCard(
            title: "Heavy",
            usageDescription: "Background recommended-action classifier (while typing).",
            deployment: $viewModel.modelsConfig.slots.heavy.deployment,
            inputPrice: pricingBinding(for: viewModel.modelsConfig.slots.heavy.deployment, \.inputPerMillion),
            outputPrice: pricingBinding(for: viewModel.modelsConfig.slots.heavy.deployment, \.outputPerMillion),
            isEnabled: !viewModel.useOneModelForAll
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

                if !compatibilitySnapshot.isEmpty {
                    Divider()
                    Text("Per-app reliability")
                        .font(.caption.bold())
                    ForEach(topCompatibilityRows, id: \.bundleID) { row in
                        HStack {
                            Text(AXWatchdog.displayName(forBundleID: row.bundleID))
                                .font(.caption)
                            Spacer()
                            Text("\(row.percent)% (\(row.total))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(row.percent >= 90 ? .secondary : Color.orange)
                        }
                    }
                    DashboardSectionCaption(
                        text: "Read/write success rate per app since install (PRD target: ≥90%). Below 90% is highlighted — the clipboard fallback still covers most failures, but consider filing what's glitching."
                    )
                }

                Divider()
                Button("Share Diagnostics…") {
                    DiagnosticsExporter.exportWithSavePanel()
                }
                .buttonStyle(.link)
                DashboardSectionCaption(
                    text: "Saves a local text file with your app/macOS version, per-app accessibility diagnostics (success/fail counts only, never field content), and any recent WriterFlow crash reports macOS already collected in its standard format. Nothing is uploaded automatically — you choose where to save it and whether to share it."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct CompatibilityRow {
        let bundleID: String
        let percent: Int
        let total: Int
    }

    /// Top 5 apps by activity, most-recently-relevant first — enough to spot-check the
    /// PRD §8 "≥90% AX success" target without turning this into a full diagnostics screen.
    private var topCompatibilityRows: [CompatibilityRow] {
        compatibilitySnapshot
            .map { bundleID, entry -> CompatibilityRow in
                let ok = entry.readOK + entry.writeOK
                let total = ok + entry.readFail + entry.writeFail
                let percent = total > 0 ? Int((Double(ok) / Double(total) * 100).rounded()) : 100
                return CompatibilityRow(bundleID: bundleID, percent: percent, total: total)
            }
            .filter { $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { $0 }
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
    var isEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextField("deployment name", text: $deployment)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.55)

            HStack(spacing: 8) {
                priceField(label: "Input $/1M", value: $inputPrice)
                priceField(label: "Output $/1M", value: $outputPrice)
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.55)

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
