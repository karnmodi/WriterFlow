import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsCoordinator
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            PermissionRow(
                title: "Accessibility",
                blurb: "Lets WriterFlow read the text field you're typing in and rewrite it in place. Password fields are always ignored.",
                granted: permissions.accessibility,
                actionLabel: "Open System Settings",
                action: permissions.requestAccessibility
            )

            PermissionRow(
                title: "Input Monitoring",
                blurb: "Used only as a local \"you are typing\" signal to show the floating icon. Key contents are never stored, logged, or sent anywhere.",
                granted: permissions.inputMonitoring,
                actionLabel: "Open System Settings",
                action: permissions.requestInputMonitoring
            )

            Spacer(minLength: 8)

            HStack {
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
        .frame(width: 520, height: 420)
        .onAppear { permissions.startPolling() }
        .onDisappear { permissions.stopPolling() }
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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(blurb).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button(actionLabel, action: action)
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
