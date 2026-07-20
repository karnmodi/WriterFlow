import XCTest
@testable import WriterFlow

final class WriterFlowAPIClientAccountTests: XCTestCase {
    private let testConfig = WriterFlowAPIConfig(baseURL: URL(string: "https://test.invalid/v2")!)

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeClient() -> WriterFlowAPIClient {
        WriterFlowAPIClient(config: testConfig, session: MockURLProtocol.session, clientVersion: "2.0.0")
    }

    private func snapshotJSON() -> Data {
        Data("""
        {
          "userId": "user-1",
          "organizationId": "org-1",
          "device": {
            "id": "device-1",
            "label": "Test Mac",
            "createdAt": "2026-07-20T00:00:00.000Z",
            "lastUsedAt": "2026-07-20T00:00:00.000Z",
            "revoked": false,
            "current": true
          },
          "entitlement": {
            "plan": "free",
            "monthlyUnitsIncluded": 500,
            "monthlyUnitsUsed": 0,
            "features": ["auto_write"]
          },
          "privacy": {
            "personalizationSyncEnabled": false,
            "consentVersion": "1"
          }
        }
        """.utf8)
    }

    // MARK: - me()

    func testMeDecodesAccountSnapshot() async throws {
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON())
        let client = makeClient()

        let snapshot = try await client.me(accessToken: "access-token-1")

        XCTAssertEqual(snapshot.userId, "user-1")
        XCTAssertEqual(snapshot.organizationId, "org-1")
        XCTAssertEqual(snapshot.device.id, "device-1")
        XCTAssertEqual(snapshot.device.label, "Test Mac")
        XCTAssertFalse(snapshot.device.revoked)
        XCTAssertTrue(snapshot.device.current)
        XCTAssertEqual(snapshot.entitlement.plan, "free")
        XCTAssertEqual(snapshot.entitlement.monthlyUnitsIncluded, 500)
        XCTAssertFalse(snapshot.privacy.personalizationSyncEnabled)
    }

    func testMeSendsBearerAuthorizationHeaderAndGetMethod() async throws {
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 200, json: snapshotJSON())
        let client = makeClient()

        _ = try await client.me(accessToken: "secret-access-token")

        let request = try XCTUnwrap(MockURLProtocol.requests().first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-access-token")
        XCTAssertNil(request.httpBody, "GET /me must never send a body")
    }

    func testMeWithUnauthorizedThrowsHTTPError() async throws {
        MockURLProtocol.stub(method: "GET", pathSuffix: "/me", statusCode: 401, json: Data("{}".utf8))
        let client = makeClient()

        do {
            _ = try await client.me(accessToken: "expired")
            XCTFail("expected httpError(401)")
        } catch DeviceSessionError.httpError(let code) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: - revokeDevice()

    func testRevokeDeviceSucceedsOn204() async throws {
        MockURLProtocol.stub(method: "DELETE", pathSuffix: "/devices/device-1", statusCode: 204, json: Data())
        let client = makeClient()

        try await client.revokeDevice(deviceId: "device-1", accessToken: "access-token-1")

        let request = try XCTUnwrap(MockURLProtocol.requests().first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/v2/devices/device-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token-1")
    }

    func testRevokeDeviceWithNotFoundThrowsHTTPError() async throws {
        MockURLProtocol.stub(method: "DELETE", pathSuffix: "/devices/someone-elses-device", statusCode: 404, json: Data("{}".utf8))
        let client = makeClient()

        do {
            try await client.revokeDevice(deviceId: "someone-elses-device", accessToken: "access-token-1")
            XCTFail("expected httpError(404)")
        } catch DeviceSessionError.httpError(let code) {
            XCTAssertEqual(code, 404)
        }
    }
}
