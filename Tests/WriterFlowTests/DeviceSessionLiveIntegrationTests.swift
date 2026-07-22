import XCTest
@testable import WriterFlow

/// Exercises `WriterFlowAPIClient`/`DeviceSessionStore` against a REAL
/// `services/api` dev server (`npm run dev --workspace services/api`,
/// pointed at real local Postgres) — not mocks. Mirrors how the backend's
/// own integration tests (services/api/test/integration/) skip cleanly
/// without Docker rather than failing `npm test`. Start the server with:
///
///   docker compose up -d postgres
///   DATABASE_URL=postgres://writerflow_app:writerflow_app_dev_only@localhost:5432/writerflow \
///     npm run dev --workspace services/api
///
/// then run this file specifically: `swift test --filter LiveIntegration`.
final class DeviceSessionLiveIntegrationTests: XCTestCase {
    private static let baseURL = URL(string: "http://localhost:8080")!

    private func serverReachable() async -> Bool {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("healthz"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    func testAuthorizeAndPollAgainstRealDevServer() async throws {
        guard await serverReachable() else {
            throw XCTSkip("services/api dev server not reachable at \(Self.baseURL) — start it per this file's header comment to run this test")
        }

        let config = WriterFlowAPIConfig(baseURL: Self.baseURL)
        let api = WriterFlowAPIClient(config: config, session: .shared, clientVersion: "2.0.0")
        let store = DeviceSessionStore(api: api, installID: "swift-test-\(UUID().uuidString)")

        let challenge = try await store.beginPairing()
        XCTAssertFalse(challenge.deviceCode.isEmpty)
        XCTAssertTrue(challenge.userCode.contains("-"), "user_code should be the AAAA-AAAA shape the real server generates")
        XCTAssertTrue(
            challenge.verificationURI.path.hasSuffix("/pair"),
            "verification URI should point at the /pair route, got \(challenge.verificationURI.absoluteString)"
        )

        // Nothing approves this device_code — the real server must report
        // authorization_pending, proving the full request/response round
        // trip (JSON encoding, real Postgres row insert, real JSON decode)
        // works end to end, not just against a mock.
        let result = try await api.pollToken(deviceCode: challenge.deviceCode, codeVerifier: "irrelevant-wrong-verifier-but-still-pending-first")
        switch result {
        case .pending(let status):
            XCTAssertEqual(status, "authorization_pending")
        case .issued:
            XCTFail("nothing approved this device_code — must not be issued")
        }
    }

    func testMalformedRequestIsRejectedByRealServerValidation() async throws {
        guard await serverReachable() else {
            throw XCTSkip("services/api dev server not reachable at \(Self.baseURL)")
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("device/authorize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        XCTAssertEqual(http?.statusCode, 400)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(body?["code"] as? String, "VALIDATION_FAILED")
    }
}
