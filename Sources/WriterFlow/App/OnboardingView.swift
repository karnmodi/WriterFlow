import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsCoordinator
    var onOpenDashboard: () -> Void
    var onDone: () -> Void

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
        .frame(minWidth: 540, maxWidth: 540, maxHeight: .infinity, alignment: .top)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to WriterFlow")
                .font(.system(size: 26, weight: .bold))
            Text("Two quick permissions and the floating icon is fully live. The Dashboard works right now regardless — open it any time from the footer.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("WriterFlow only reads text on explicit action, and never for password fields.", systemImage: "lock.shield")
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
