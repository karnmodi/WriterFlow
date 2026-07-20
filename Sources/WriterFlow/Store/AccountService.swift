import Foundation

/// Thin composition of `DeviceSessionProviding` (token lifecycle) and
/// `WriterFlowAPIClient` (raw HTTP) for the Stage 5.2 Dashboard Account
/// card — GET /v2/me and DELETE /v2/devices/{id}. Kept separate from
/// `DeviceSessionProviding` itself, which is only about pairing/token state,
/// not account/entitlement data.
protocol AccountServiceProviding: Sendable {
    func fetchSnapshot() async throws -> WriterFlowAPIClient.AccountSnapshot

    /// Revokes the currently signed-in device server-side (which also kills
    /// its refresh-token family), then always clears the local Keychain
    /// item — regardless of whether the server call succeeded, since a
    /// device that just asked to be revoked should never keep behaving as
    /// signed in locally.
    func revokeCurrentDeviceAndSignOut() async throws
}

actor AccountService: AccountServiceProviding {
    private let session: DeviceSessionProviding
    private let api: WriterFlowAPIClient

    init(session: DeviceSessionProviding, api: WriterFlowAPIClient = WriterFlowAPIClient()) {
        self.session = session
        self.api = api
    }

    func fetchSnapshot() async throws -> WriterFlowAPIClient.AccountSnapshot {
        let token = try await session.accessToken()
        return try await api.me(accessToken: token)
    }

    func revokeCurrentDeviceAndSignOut() async throws {
        let token = try await session.accessToken()
        let snapshot = try await api.me(accessToken: token)
        do {
            try await api.revokeDevice(deviceId: snapshot.device.id, accessToken: token)
        } catch {
            await session.signOut()
            throw error
        }
        await session.signOut()
    }
}
