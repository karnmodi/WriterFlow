import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsCoordinator

    var onOpenDashboard: () -> Void
    var onDone: () -> Void

    init(
        permissions: PermissionsCoordinator,
        onOpenDashboard: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.permissions = permissions
        self.onOpenDashboard = onOpenDashboard
        self.onDone = onDone
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
                    cloudServiceCard
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
        .onAppear {
            if !permissions.allGranted {
                permissions.startPolling()
            }
        }
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

    private var cloudServiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(.blue)
                    .font(.title2)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect your WriterFlow account")
                        .font(.headline)
                    Text("Open Dashboard → Account to sign in in your browser and approve this Mac. WriterFlow never receives your Microsoft password.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your draft is processed in WriterFlow's cloud only after you choose an action. History remains encrypted on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Open Account") { onOpenDashboard() }
                        .buttonStyle(.borderedProminent)
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
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to WriterFlow")
                .font(.system(size: 26, weight: .bold))
            Text("Grant two permissions, then connect your WriterFlow account in the Dashboard.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Password fields are never read. Account tokens stay in the macOS Keychain.", systemImage: "lock.shield")
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
                    Text(permissions.allGranted ? "Get started" : "Continue")
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
