import SwiftUI

/// Stage 5.2 "UI" checklist: Sign in / Account status, replacing the
/// `#if DEBUG` manual pairing menu item as the real entry point. Device
/// pairing (ADR-0011/0012) happens entirely browser-side — this view only
/// shows the `user_code`/deep link and reflects `DeviceSessionProviding`'s
/// state; it never becomes an OAuth client itself.
struct AccountView: View {
    @ObservedObject var viewModel: AccountViewModel

    var body: some View {
        DashboardFormContainer(
            header: DashboardPageHeader(
                title: "Account",
                subtitle: "Sign in to sync personalization across devices and use WriterFlow-hosted models."
            )
        ) {
            VStack(alignment: .leading, spacing: DashboardChrome.sectionSpacing) {
                accountCard
            }
        }
        .task { await viewModel.refresh() }
    }

    private var accountCard: some View {
        DashboardCard(
            title: "WriterFlow Account",
            icon: "person.crop.circle.badge.checkmark",
            iconTint: .blue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                content
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading account…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .signedOut:
            signedOutContent

        case .pairing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Starting sign-in…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .awaitingApproval(let challenge):
            awaitingApprovalContent(challenge)

        case .loaded(let snapshot):
            signedInContent(snapshot)

        case .needsRePair:
            VStack(alignment: .leading, spacing: 8) {
                StatusBanner(message: "Your session expired. Please sign in again.", tone: .warning)
                Button("Sign In Again") { Task { await viewModel.beginSignIn() } }
                    .buttonStyle(.borderedProminent)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                StatusBanner(message: message, tone: .error)
                Button("Retry") { Task { await viewModel.refresh() } }
            }
        }
    }

    private var signedOutContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not signed in. Sign in opens your browser to approve this device — WriterFlow never sees your password here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Sign In") { Task { await viewModel.beginSignIn() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func awaitingApprovalContent(_ challenge: PairingChallenge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval in your browser…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("Code:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(challenge.userCode)
                    .font(.callout.monospaced().weight(.semibold))
                    .textSelection(.enabled)
            }
            Text("If the browser didn't open, or you're pairing from another device, enter this code at writerflow.app/pair.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                Button("Open Browser Again", action: viewModel.reopenBrowser)
                Button("Cancel", role: .cancel) { Task { await viewModel.cancelSignIn() } }
            }
        }
    }

    private func signedInContent(_ snapshot: WriterFlowAPIClient.AccountSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(snapshot.device.label ?? "This Mac")
                    .font(.callout.weight(.medium))
                if snapshot.device.revoked {
                    Text("Revoked")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                StatTile(title: "Plan", value: snapshot.entitlement.plan.capitalized, subtitle: "Current subscription tier")
                StatTile(
                    title: "Monthly Units",
                    value: "\(snapshot.entitlement.monthlyUnitsUsed)/\(snapshot.entitlement.monthlyUnitsIncluded)",
                    subtitle: "Used this billing cycle"
                )
                StatTile(
                    title: "Sync",
                    value: snapshot.privacy.personalizationSyncEnabled ? "On" : "Off",
                    subtitle: "Personalization sync across devices"
                )
            }

            Text("Signed in as this device. Local history and personalization stay available even if you sign out.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 10) {
                Button("Sign Out") { Task { await viewModel.signOut() } }
                Button("Revoke This Device", role: .destructive) { Task { await viewModel.revokeDeviceAndSignOut() } }
            }
        }
    }
}
