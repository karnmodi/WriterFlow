import XCTest
@testable import WriterFlow

@MainActor
final class AccountViewModelTests: XCTestCase {
    private let testConfig = WriterFlowAPIConfig(baseURL: URL(string: "https://test.invalid/v2")!)

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        KeychainTestIsolation.begin()
    }

    override func tearDown() {
        KeychainTestIsolation.end()
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeViewModel() -> AccountViewModel {
        // Both the pairing/refresh client and the account client must be the
        // SAME instance so MockURLProtocol's stubs are visible to both —
        // DeviceSessionStore and AccountService each hold their own
        // WriterFlowAPIClient reference (harmless in production, where both
        // resolve to the same real base URL/shared session, but a real gap
        // for tests unless wired explicitly).
        let api = WriterFlowAPIClient(config: testConfig, session: MockURLProtocol.session, clientVersion: "2.0.0")
        let session = DeviceSessionStore(api: api, installID: "test-install")
        let accountService = AccountService(session: session, api: api)
        return AccountViewModel(session: session, accountService: accountService)
    }

    private func snapshotJSON(deviceId: String = "device-1", label: String = "Test Mac", revoked: Bool = false) -> Data {
        Data("""
        {
          "userId": "user-1",
          "organizationId": "org-1",
          "displayName": "Karan Singh",
          "email": "karan@example.com",
          "device": {
            "id": "\(deviceId)",
            "label": "\(label)",
            "createdAt": "2026-07-20T00:00:00.000Z",
            "lastUsedAt": "2026-07-20T00:00:00.000Z",
            "revoked": \(revoked),
            "current": true
          },
          "entitlement": {
            "plan": "free",
            "monthlyUnitsIncluded": 500,
            "monthlyUnitsUsed": 3,
            "features": ["auto_write"]
          },
          "privacy": {
            "personalizationSyncEnabled": false,
            "consentVersion": "1"
          }
        }
        """.utf8)
    }

    private func seedSignedIn(deviceId: String = "device-1") {
        DeviceTokenKeychain.write(
            .init(deviceID: deviceId, accessToken: "valid-token", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r1")
        )
    }

    func testRefreshWhenSignedOutSetsSignedOutState() async {
        let viewModel = makeViewModel()
        await viewModel.refresh()

        guard case .signedOut = viewModel.loadState else {
            return XCTFail("expected .signedOut, got \(viewModel.loadState)")
        }
    }

    func testRefreshWhenSignedInLoadsSnapshot() async throws {
        seedSignedIn()
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON())
        let viewModel = makeViewModel()

        await viewModel.refresh()

        guard case .loaded(let snapshot) = viewModel.loadState else {
            return XCTFail("expected .loaded, got \(viewModel.loadState)")
        }
        XCTAssertEqual(snapshot.device.id, "device-1")
        XCTAssertEqual(snapshot.device.label, "Test Mac")
        XCTAssertEqual(snapshot.displayName, "Karan Singh")
        XCTAssertEqual(snapshot.email, "karan@example.com")
        XCTAssertEqual(snapshot.entitlement.monthlyUnitsUsed, 3)
    }

    func testRefreshWhenMeReturns401SetsNeedsRePair() async {
        seedSignedIn()
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 401, json: Data("{}".utf8))
        MockURLProtocol.stub(method: "POST", pathSuffix: "/token/refresh", statusCode: 401, json: Data("{}".utf8))
        let viewModel = makeViewModel()

        await viewModel.refresh()

        guard case .needsRePair = viewModel.loadState else {
            return XCTFail("expected .needsRePair after /me 401, got \(viewModel.loadState)")
        }
    }

    func testRefreshWhenTokenRefreshFailsSetsNeedsRePair() async {
        DeviceTokenKeychain.write(
            .init(deviceID: "device-1", accessToken: "stale", accessTokenExpiresAt: Date().addingTimeInterval(-10), refreshToken: "reused-or-revoked")
        )
        MockURLProtocol.stub(method: "POST", pathSuffix: "/token/refresh", statusCode: 401, json: Data("{}".utf8))
        let viewModel = makeViewModel()

        await viewModel.refresh()

        guard case .needsRePair = viewModel.loadState else {
            return XCTFail("expected .needsRePair, got \(viewModel.loadState)")
        }
    }

    func testSignOutClearsStateAndKeychain() async {
        seedSignedIn()
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON())
        let viewModel = makeViewModel()
        await viewModel.refresh()

        await viewModel.signOut()

        guard case .signedOut = viewModel.loadState else {
            return XCTFail("expected .signedOut after signOut(), got \(viewModel.loadState)")
        }
        XCTAssertNil(DeviceTokenKeychain.read())
    }

    func testRevokeDeviceAndSignOutCallsDeleteThenClearsLocalSession() async {
        seedSignedIn(deviceId: "device-to-revoke")
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON(deviceId: "device-to-revoke"))
        MockURLProtocol.stub(method: "DELETE", pathSuffix: "/devices/device-to-revoke", statusCode: 204, json: Data())
        let viewModel = makeViewModel()

        await viewModel.revokeDeviceAndSignOut()

        guard case .signedOut = viewModel.loadState else {
            return XCTFail("expected .signedOut, got \(viewModel.loadState)")
        }
        XCTAssertNil(DeviceTokenKeychain.read())
        XCTAssertFalse(viewModel.statusIsError)
        let deleteRequest = MockURLProtocol.requests().first { $0.httpMethod == "DELETE" }
        XCTAssertNotNil(deleteRequest, "revoke must actually call DELETE /devices/:id")
    }

    func testRevokeDeviceAndSignOutStillSignsOutLocallyWhenServerCallFails() async {
        seedSignedIn(deviceId: "device-1")
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON())
        MockURLProtocol.stub(method: "DELETE", pathSuffix: "/devices/device-1", statusCode: 500, json: Data("{}".utf8))
        let viewModel = makeViewModel()

        await viewModel.revokeDeviceAndSignOut()

        guard case .signedOut = viewModel.loadState else {
            return XCTFail("must still end up signed out locally even if the server call fails, got \(viewModel.loadState)")
        }
        XCTAssertNil(DeviceTokenKeychain.read())
        XCTAssertTrue(viewModel.statusIsError)
    }

    func testBeginSignInTransitionsThroughAwaitingApprovalToLoaded() async {
        let authorizeJSON = """
        {
          "deviceCode": "device-code-abc",
          "userCode": "ABCD-1234",
          "verificationUri": "https://writerflow.aviusolutions.com/pair",
          "verificationUriComplete": "https://writerflow.aviusolutions.com/pair?user_code=ABCD-1234",
          "interval": 0,
          "expiresIn": 900
        }
        """
        MockURLProtocol.stub(method: "POST", pathSuffix: "/device/authorize", statusCode: 200, json: Data(authorizeJSON.utf8))
        let tokenJSON = """
        {"accessToken":"access-1","refreshToken":"refresh-1","expiresIn":900,"deviceId":"device-1"}
        """
        MockURLProtocol.stub(method: "POST", pathSuffix: "/device/token", statusCode: 200, json: Data(tokenJSON.utf8))
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON())
        let viewModel = makeViewModel()

        await viewModel.beginSignIn()

        guard case .loaded(let snapshot) = viewModel.loadState else {
            return XCTFail("expected .loaded after successful pairing, got \(viewModel.loadState)")
        }
        XCTAssertEqual(snapshot.device.id, "device-1")
    }

    func testCancelSignInDuringAwaitingApprovalEndsSignedOut() async {
        let authorizeJSON = """
        {
          "deviceCode": "device-code-abc",
          "userCode": "ABCD-1234",
          "verificationUri": "https://writerflow.aviusolutions.com/pair",
          "verificationUriComplete": "https://writerflow.aviusolutions.com/pair?user_code=ABCD-1234",
          "interval": 5,
          "expiresIn": 900
        }
        """
        MockURLProtocol.stub(method: "POST", pathSuffix: "/device/authorize", statusCode: 200, json: Data(authorizeJSON.utf8))
        let viewModel = makeViewModel()

        async let signIn: Void = viewModel.beginSignIn()
        try? await Task.sleep(nanoseconds: 200_000_000)
        await viewModel.cancelSignIn()
        await signIn

        guard case .signedOut = viewModel.loadState else {
            return XCTFail("expected .signedOut after cancellation, got \(viewModel.loadState)")
        }
    }
}
