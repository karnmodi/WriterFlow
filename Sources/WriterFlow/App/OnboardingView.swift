import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsCoordinator
    @StateObject private var connection: SettingsViewModel
    @State private var defaultDeployment: String
    @State private var heavyDeployment: String
    @State private var useOneModel: Bool

    var onOpenDashboard: () -> Void
    var onDone: () -> Void

    init(
        permissions: PermissionsCoordinator,
        modelsConfig: AzureModelsConfig,
        onOpenDashboard: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.permissions = permissions
        self.onOpenDashboard = onOpenDashboard
        self.onDone = onDone
        _connection = StateObject(wrappedValue: SettingsViewModel(modelsConfig: modelsConfig))
        let d = modelsConfig.slots.default.deployment
        let h = modelsConfig.slots.heavy.deployment
        _defaultDeployment = State(initialValue: d)
        _heavyDeployment = State(initialValue: h)
        _useOneModel = State(initialValue: d == h && d == modelsConfig.slots.grammar.deployment)
    }

    private var azureReady: Bool {
        connection.hasSavedKey
            && AzureModelsConfig.isUsableResponsesURL(connection.endpointURL)
            && !connection.endpointURL.contains("YOUR-RESOURCE")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 14) {
                    accessibilityCard
                    inputMonitoringCard
                    azureCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
                .padding(.horizontal, 24)

            footer
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .frame(minWidth: 560, maxWidth: 560, maxHeight: .infinity, alignment: .top)
        .onAppear { permissions.startPolling() }
        .onDisappear {
            if permissions.allGranted { permissions.stopPolling() }
        }
    }

    @ViewBuilder
    private var accessibilityCard: some View {
        if permissions.accessibility {
            PermissionCard(
                title: "Accessibility",
                blurb: "Lets WriterFlow read the text field you're typing in and rewrite it in place. Password fields are always ignored.",
                granted: true,
                actionLabel: "Open System Settings",
                action: permissions.requestAccessibility
            )
        } else {
            PermissionCard(
                title: "Accessibility",
                blurb: "Lets WriterFlow read the text field you're typing in and rewrite it in place. Password fields are always ignored.",
                granted: false,
                actionLabel: "Open System Settings",
                action: permissions.requestAccessibility,
                footnote: "Already ON in Settings but still showing here? The app was rebuilt — use \"Repair Accessibility\".\nPath: \(permissions.appBundlePath)",
                secondaryLabel: "Repair Accessibility",
                secondaryAction: permissions.repairAccessibility
            )
        }
    }

    private var inputMonitoringCard: some View {
        PermissionCard(
            title: "Input Monitoring",
            blurb: "Used only as a local \"you are typing\" signal to show the floating icon. Key contents are never stored, logged, or sent anywhere.",
            granted: permissions.inputMonitoring,
            actionLabel: "Open System Settings",
            action: permissions.requestInputMonitoring,
            footnote: "Not in the list? Click + in System Settings, then use \"Reveal App in Finder\" and select WriterFlow.app.\nPath: \(permissions.appBundlePath)",
            secondaryLabel: "Reveal App in Finder",
            secondaryAction: permissions.revealAppInFinder
        )
    }

    private var azureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: azureReady ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(azureReady ? .green : .secondary, azureReady ? .green.opacity(0.2) : .clear)
                    .font(.title2)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your Azure OpenAI key")
                            .font(.headline)
                        if azureReady {
                            Text("Connected")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.green.opacity(0.12)))
                        }
                    }

                    Text("WriterFlow is bring-your-own-key: paste the endpoint and API key from your Azure OpenAI resource. Usage bills your Azure account — nothing is shared or bundled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !azureReady {
                        Group {
                            labeledField("Responses endpoint", text: $connection.endpointURL, mono: true)
                            labeledSecure("API key", text: $connection.apiKeyInput)
                            labeledField("Default deployment name", text: $defaultDeployment, mono: true)
                            Toggle("Use the same deployment for grammar + classifier", isOn: $useOneModel)
                                .font(.caption)
                            if !useOneModel {
                                labeledField("Heavy / classifier deployment", text: $heavyDeployment, mono: true)
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                saveAzureSetup()
                            } label: {
                                if connection.isValidating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Text("Validate & Save")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(connection.isValidating || connection.apiKeyInput.isEmpty)

                            Button("Open Dashboard Settings") { onOpenDashboard() }
                                .buttonStyle(.link)
                        }

                        if let message = connection.statusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(connection.statusIsError ? .red : .green)
                        }
                    } else {
                        Text("You can change endpoint, key, and deployments any time in Dashboard → Settings.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            azureReady ? Color.green.opacity(0.25) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(mono ? .system(.caption, design: .monospaced) : .callout)
                .disabled(connection.isValidating)
        }
    }

    private func labeledSecure(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(connection.isValidating)
        }
    }

    private func saveAzureSetup() {
        var config = AzureModelsConfig.loadFromDisk() ?? AzureModelsConfig.load()
        config.responsesURL = connection.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultName = defaultDeployment.trimmingCharacters(in: .whitespacesAndNewlines)
        let heavyName = useOneModel
            ? defaultName
            : heavyDeployment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !defaultName.isEmpty else {
            connection.statusIsError = true
            connection.statusMessage = "Enter a default deployment name."
            return
        }
        guard !heavyName.isEmpty else {
            connection.statusIsError = true
            connection.statusMessage = "Enter a heavy deployment name, or enable “same deployment”."
            return
        }
        config.slots.default.deployment = defaultName
        config.slots.grammar.deployment = defaultName
        config.slots.heavy.deployment = heavyName
        config.save()
        connection.validateAndSave(updatingDeploymentsFrom: config)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to WriterFlow")
                .font(.system(size: 26, weight: .bold))
            Text("Grant two permissions, then connect your Azure OpenAI key. The Dashboard works without a key — AI actions need one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Password fields are never read. Your key stays in the macOS Keychain.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if !permissions.accessibility {
                    Button("Quit & Reopen") {
                        permissions.quitAndRestart()
                    }
                    .buttonStyle(.bordered)
                }
                Button("Open Dashboard") { onOpenDashboard() }
                    .buttonStyle(.link)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Button("I'll do this later") { onDone() }
                    .buttonStyle(.bordered)
                Button(action: onDone) {
                    Text(permissions.allGranted && azureReady ? "Get started" : "Continue")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct PermissionCard: View {
    let title: String
    let blurb: String
    let granted: Bool
    let actionLabel: String
    let action: () -> Void
    var footnote: String?
    var secondaryLabel: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .symbolRenderingMode(.palette)
                .foregroundStyle(granted ? .green : .secondary, granted ? .green.opacity(0.2) : .clear)
                .font(.title2)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                    if granted {
                        Text("Granted")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.green.opacity(0.12)))
                    }
                }

                Text(blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote, !granted {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !granted {
                    HStack(spacing: 10) {
                        Button(actionLabel, action: action)
                            .buttonStyle(.bordered)
                        if let secondaryLabel, let secondaryAction {
                            Button(secondaryLabel, action: secondaryAction)
                                .buttonStyle(.link)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            granted ? Color.green.opacity(0.25) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                }
        }
    }
}
