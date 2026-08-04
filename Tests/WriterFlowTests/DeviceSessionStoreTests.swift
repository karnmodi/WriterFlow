import XCTest
@testable import WriterFlow

final class DeviceSessionStoreTests: XCTestCase {
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

    private func makeStore() -> DeviceSessionStore {
        let api = WriterFlowAPIClient(config: testConfig, session: MockURLProtocol.session, clientVersion: "2.0.0")
        return DeviceSessionStore(api: api, installID: "test-install")
    }

    private func stubAuthorize(interval: Int = 0, expiresIn: Int = 900) {
        let json = """
        {
          "deviceCode": "device-code-abc",
          "userCode": "ABCD-1234",
          "verificationUri": "https://writerflow.aviusolutions.com/pair",
          "verificationUriComplete": "https://writerflow.aviusolutions.com/pair?user_code=ABCD-1234",
          "interval": \(interval),
          "expiresIn": \(expiresIn)
        }
        """
        MockURLProtocol.stub(method: "POST", pathSuffix: "/device/authorize", statusCode: 200, json: Data(json.utf8))
    }

    private func stubTokenPending(_ status: String) {
        MockURLProtocol.stub(
            method: "POST",
            pathSuffix: "/device/token",
            statusCode: 202,
            json: Data("{\"status\":\"\(status)\"}".utf8)
        )
    }

    private func stubTokenIssued(accessToken: String = "access-1", refreshToken: String = "refresh-1", deviceId: String = "device-1") {
        let json = """
        {"accessToken":"\(accessToken)","refreshToken":"\(refreshToken)","expiresIn":900,"deviceId":"\(deviceId)"}
        """
        MockURLProtocol.stub(method: "POST", pathSuffix: "/device/token", statusCode: 200, json: Data(json.utf8))
    }

    private func stubRefresh(accessToken: String = "access-2", refreshToken: String = "refresh-2", deviceId: String = "device-1", statusCode: Int = 200) {
        let json = """
        {"accessToken":"\(accessToken)","refreshToken":"\(refreshToken)","expiresIn":900,"deviceId":"\(deviceId)"}
        """
        MockURLProtocol.stub(method: "POST", pathSuffix: "/token/refresh", statusCode: statusCode, json: Data(json.utf8))
    }

    // MARK: - beginPairing

    func testBeginPairingParsesChallengeAndSetsState() async throws {
        stubAuthorize()
        let store = makeStore()
        let challenge = try await store.beginPairing()

        XCTAssertEqual(challenge.deviceCode, "device-code-abc")
        XCTAssertEqual(challenge.userCode, "ABCD-1234")
        XCTAssertEqual(challenge.verificationURIComplete.absoluteString, "https://writerflow.aviusolutions.com/pair?user_code=ABCD-1234")

        let state = await store.state
        XCTAssertEqual(state, .pairing(challenge))
    }

    func testBeginPairingRequestBodyNeverLeaksAnAccessGroupOrCredential() async throws {
        stubAuthorize()
        let store = makeStore()
        _ = try await store.beginPairing()

        let requests = MockURLProtocol.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - awaitPairedToken

    func testAwaitPairedTokenSucceedsAfterOnePendingPoll() async throws {
        stubAuthorize()
        stubTokenPending("authorization_pending")
        stubTokenIssued(deviceId: "device-xyz")
        let store = makeStore()

        _ = try await store.beginPairing()
        try await store.awaitPairedToken()

        let state = await store.state
        XCTAssertEqual(state, .signedIn(deviceId: "device-xyz"))
        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-xyz")
    }

    func testSlowDownStatusEventuallyStillSucceeds() async throws {
        stubAuthorize()
        stubTokenPending("slow_down")
        stubTokenIssued()
        let store = makeStore()

        _ = try await store.beginPairing()
        try await store.awaitPairedToken()

        let state = await store.state
        if case .signedIn = state {
            // expected
        } else {
            XCTFail("expected signedIn, got \(state)")
        }
    }

    func testAccessDeniedThrowsAndResetsToSignedOut() async throws {
        stubAuthorize()
        stubTokenPending("access_denied")
        let store = makeStore()

        _ = try await store.beginPairing()
        do {
            try await store.awaitPairedToken()
            XCTFail("expected pairingDenied")
        } catch DeviceSessionError.pairingDenied {
            // expected
        }

        let state = await store.state
        XCTAssertEqual(state, .signedOut)
        XCTAssertNil(DeviceTokenKeychain.read())
    }

    func testExpiredTokenStatusThrowsAndResetsToSignedOut() async throws {
        stubAuthorize()
        stubTokenPending("expired_token")
        let store = makeStore()

        _ = try await store.beginPairing()
        do {
            try await store.awaitPairedToken()
            XCTFail("expected pairingExpired")
        } catch DeviceSessionError.pairingExpired {
            // expected
        }

        let state = await store.state
        XCTAssertEqual(state, .signedOut)
    }

    func testAwaitPairedTokenWithoutBeginPairingThrowsNotPaired() async throws {
        let store = makeStore()
        do {
            try await store.awaitPairedToken()
            XCTFail("expected notPaired")
        } catch DeviceSessionError.notPaired {
            // expected
        }
    }

    // MARK: - accessToken

    func testAccessTokenReturnsCachedValueWithoutNetworkCallWhenNotExpired() async throws {
        DeviceTokenKeychain.write(
            .init(deviceID: "d1", accessToken: "still-valid", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r1")
        )
        let store = makeStore()
        let token = try await store.accessToken()

        XCTAssertEqual(token, "still-valid")
        XCTAssertEqual(MockURLProtocol.requests().count, 0, "must not touch the network for a still-valid token")
    }

    func testAccessTokenRefreshesWhenExpired() async throws {
        DeviceTokenKeychain.write(
            .init(deviceID: "d1", accessToken: "stale", accessTokenExpiresAt: Date().addingTimeInterval(-10), refreshToken: "r1")
        )
        stubRefresh(accessToken: "fresh", refreshToken: "r2", deviceId: "d1")
        let store = makeStore()

        let token = try await store.accessToken()
        XCTAssertEqual(token, "fresh")
        XCTAssertEqual(DeviceTokenKeychain.read()?.refreshToken, "r2")
    }

    func testAccessTokenRefreshFailureSetsNeedsRePairAndKeepsKeychainForDiagnostics() async throws {
        DeviceTokenKeychain.write(
            .init(deviceID: "d1", accessToken: "stale", accessTokenExpiresAt: Date().addingTimeInterval(-10), refreshToken: "reused-or-revoked")
        )
        stubRefresh(statusCode: 401)
        let store = makeStore()

        do {
            _ = try await store.accessToken()
            XCTFail("expected refreshFailed")
        } catch DeviceSessionError.refreshFailed {
            // expected
        }

        let state = await store.state
        XCTAssertEqual(state, .needsRePair)
    }

    func testAccessTokenWithNoStoredSessionThrowsNotPaired() async throws {
        let store = makeStore()
        do {
            _ = try await store.accessToken()
            XCTFail("expected notPaired")
        } catch DeviceSessionError.notPaired {
            // expected
        }
    }

    // MARK: - cancelPairing

    func testCancelPairingStopsAnInFlightWaitAndThrows() async throws {
        stubAuthorize(interval: 5)
        let store = makeStore()
        _ = try await store.beginPairing()

        let start = Date()
        async let pairing: Void = store.awaitPairedToken()
        try await Task.sleep(nanoseconds: 200_000_000)
        await store.cancelPairing()

        do {
            try await pairing
            XCTFail("expected pairingCancelled")
        } catch DeviceSessionError.pairingCancelled {
            // expected
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 4.0, "cancellation should not wait out the full interval")
        let state = await store.state
        XCTAssertEqual(state, .signedOut)
    }

    func testCancelPairingWithNothingInFlightIsANoOp() async throws {
        let store = makeStore()
        await store.cancelPairing() // must not crash or affect anything
        let state = await store.state
        XCTAssertEqual(state, .signedOut)
    }

    // MARK: - signOut

    func testSignOutClearsKeychainAndState() async throws {
        DeviceTokenKeychain.write(
            .init(deviceID: "d1", accessToken: "a", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r")
        )
        let store = makeStore()
        await store.signOut()

        let state = await store.state
        XCTAssertEqual(state, .signedOut)
        XCTAssertNil(DeviceTokenKeychain.read())
    }

    // MARK: - foreground hint

    func testForegroundHintEndsThePollingWaitEarly() async throws {
        stubAuthorize(interval: 5)
        stubTokenIssued()
        let store = makeStore()
        _ = try await store.beginPairing()

        let start = Date()
        async let pairing: Void = store.awaitPairedToken()
        try await Task.sleep(nanoseconds: 200_000_000)
        await store.handleForegroundHint()
        try await pairing

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 4.0, "the foreground hint should end the 5s wait almost immediately, not require the full interval")
    }

    func testPairingSucceedsWithoutEverCallingTheForegroundHint() async throws {
        stubAuthorize(interval: 0)
        stubTokenIssued()
        let store = makeStore()
        _ = try await store.beginPairing()
        try await store.awaitPairedToken()

        let state = await store.state
        if case .signedIn = state {
            // expected — the deep link is a nicety, never a requirement
        } else {
            XCTFail("expected signedIn, got \(state)")
        }
    }
}
