import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsCoordinator
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if permissions.accessibility {
                PermissionRow(
                    title: "Accessibility",
                    blurb: "Lets WriterFlow read the text field you're typing in and rewrite it in place. Password fields are always ignored.",
                    granted: true,
                    actionLabel: "Open System Settings",
                    action: permissions.requestAccessibility
                )
            } else {
                PermissionRow(
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

            PermissionRow(
                title: "Input Monitoring",
                blurb: "Used only as a local \"you are typing\" signal to show the floating icon. Key contents are never stored, logged, or sent anywhere.",
                granted: permissions.inputMonitoring,
                actionLabel: "Open System Settings",
                action: permissions.requestInputMonitoring,
                footnote: "Not in the list? Click + in System Settings, then use \"Reveal App in Finder\" and select WriterFlow.app.\nPath: \(permissions.appBundlePath)",
                secondaryLabel: "Reveal App in Finder",
                secondaryAction: permissions.revealAppInFinder
            )

            Spacer(minLength: 8)

            HStack {
                if !permissions.accessibility {
                    Button("Quit & Reopen") {
                        permissions.quitAndRestart()
                    }
                }
                Spacer()
                Button(action: onDone) {
                    Text(permissions.allGranted ? "Get started" : "I'll do this later")
                        .frame(minWidth: 120)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520, height: 500)
        .onAppear { permissions.startPolling() }
        .onDisappear {
            if permissions.allGranted { permissions.stopPolling() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to WriterFlow")
                .font(.title2).bold()
            Text("Two quick permissions and you're set. WriterFlow only reads text on explicit action, and never for password fields.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
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
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let footnote, !granted {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if !granted {
                    HStack(spacing: 12) {
                        Button(actionLabel, action: action)
                        if let secondaryLabel, let secondaryAction {
                            Button(secondaryLabel, action: secondaryAction)
                                .buttonStyle(.link)
                        }
                    }
                    .padding(.top, 4)
                } else {
                    Text("Granted")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }
            }
        }
    }
}
