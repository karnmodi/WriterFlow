import Foundation

/// Non-secret WriterFlow API endpoint configuration. Production always
/// targets the public APIM gateway; a `.env` override lets local
/// development point at `services/api`'s dev server directly (bypassing
/// APIM, which also strips its own `/v2` path segment before forwarding —
/// see services/api/src/routes/device.ts's routing comment).
struct WriterFlowAPIConfig: Sendable {
    let baseURL: URL

    static let production = WriterFlowAPIConfig(baseURL: URL(string: "https://api.writerflow.app/v2")!)

    #if DEBUG
    /// Reads `WRITERFLOW_API_BASE_URL` from the project `.env` (same file
    /// `AzureOpenAIClient`'s dev path already reads), e.g.
    /// `WRITERFLOW_API_BASE_URL=http://localhost:8080` while running
    /// `npm run dev --workspace services/api` locally. Debug-only — this
    /// override compiles out of release builds entirely.
    static func resolved() -> WriterFlowAPIConfig {
        let exec = URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? ".")
        if let envFile = DotEnvLoader.findProjectEnvFile(startingAt: exec.deletingLastPathComponent()),
           let env = DotEnvLoader.load(from: envFile),
           let raw = env["WRITERFLOW_API_BASE_URL"], let url = URL(string: raw) {
            return WriterFlowAPIConfig(baseURL: url)
        }
        return .production
    }
    #else
    static func resolved() -> WriterFlowAPIConfig { .production }
    #endif
}

/// Raw HTTP calls for the three bearer-exempt pairing routes
/// (ADR-0011/ADR-0012). Mirrors services/shared's Zod schemas field-for-field.
actor WriterFlowAPIClient {
    private let config: WriterFlowAPIConfig
    private let session: URLSession
    private let clientVersion: String

    init(config: WriterFlowAPIConfig = .resolved(), session: URLSession = .shared, clientVersion: String = "2.0.0") {
        self.config = config
        self.session = session
        self.clientVersion = clientVersion
    }

    struct AuthorizeResponse: Decodable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let verificationUriComplete: String
        let interval: Int
        let expiresIn: Int
    }

    func authorize(installID: String, deviceLabel: String?, codeChallenge: String) async throws -> AuthorizeResponse {
        struct Body: Encodable {
            let installId: String
            let deviceLabel: String?
            let codeChallenge: String
            let codeChallengeMethod = "S256"
        }
        return try await post(
            path: "/device/authorize",
            body: Body(installId: installID, deviceLabel: deviceLabel, codeChallenge: codeChallenge)
        )
    }

    enum TokenPollResult: Sendable {
        case issued(TokenResponse)
        case pending(String)
    }

    struct TokenResponse: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
        let deviceId: String
    }

    /// 200 -> `.issued`; 202 -> `.pending(status)` where status is one of
    /// authorization_pending/slow_down/access_denied/expired_token.
    func pollToken(deviceCode: String, codeVerifier: String) async throws -> TokenPollResult {
        struct Body: Encodable {
            let deviceCode: String
            let codeVerifier: String
        }
        struct Pending: Decodable { let status: String }

        let request = makeRequest(path: "/device/token")
        let (data, response) = try await send(
            request,
            body: Body(deviceCode: deviceCode, codeVerifier: codeVerifier)
        )
        guard let http = response as? HTTPURLResponse else { throw DeviceSessionError.decodingFailed }
        switch http.statusCode {
        case 200:
            guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                throw DeviceSessionError.decodingFailed
            }
            return .issued(decoded)
        case 202:
            guard let decoded = try? JSONDecoder().decode(Pending.self, from: data) else {
                throw DeviceSessionError.decodingFailed
            }
            return .pending(decoded.status)
        default:
            throw DeviceSessionError.httpError(http.statusCode)
        }
    }

    func refresh(refreshToken: String) async throws -> TokenResponse {
        struct Body: Encodable { let refreshToken: String }
        return try await post(path: "/token/refresh", body: Body(refreshToken: refreshToken))
    }

    // Siblings of AccountSnapshot rather than nested inside it — swiftlint
    // caps type nesting at 1 level, and these are already nested once inside
    // the actor.
    struct AccountDevice: Decodable, Sendable {
        let id: String
        let label: String?
        let createdAt: String
        let lastUsedAt: String
        let revoked: Bool
        let current: Bool
    }
    struct AccountEntitlement: Decodable, Sendable {
        let plan: String
        let monthlyUnitsIncluded: Int
        let monthlyUnitsUsed: Int
        let features: [String]
    }
    struct AccountPrivacy: Decodable, Sendable {
        let personalizationSyncEnabled: Bool
        let consentVersion: String
    }

    /// Docs/contracts/openapi.yaml `AccountSnapshot` — field names match the
    /// JSON response verbatim (the API already emits camelCase).
    struct AccountSnapshot: Decodable, Sendable {
        let userId: String
        let organizationId: String
        let device: AccountDevice
        let entitlement: AccountEntitlement
        let privacy: AccountPrivacy
    }

    /// `GET /v2/me` — requires a bearer WriterFlow access token (not the
    /// bearer-exempt pairing routes above).
    func me(accessToken: String) async throws -> AccountSnapshot {
        try await get(path: "/me", accessToken: accessToken)
    }

    /// `DELETE /v2/devices/{id}` — 204 on success; 404 if `deviceId` isn't
    /// one of the calling user's own devices.
    func revokeDevice(deviceId: String, accessToken: String) async throws {
        let request = makeRequest(path: "/devices/\(deviceId)", method: "DELETE", accessToken: accessToken)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeviceSessionError.decodingFailed }
        guard http.statusCode == 204 else { throw DeviceSessionError.httpError(http.statusCode) }
    }

    // MARK: - Plumbing

    private func makeRequest(path: String, method: String = "POST", accessToken: String? = nil) -> URLRequest {
        let url = config.baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "X-WriterFlow-Version")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
        return request
    }

    private func get<Response: Decodable>(path: String, accessToken: String) async throws -> Response {
        let request = makeRequest(path: path, method: "GET", accessToken: accessToken)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeviceSessionError.decodingFailed }
        guard (200...299).contains(http.statusCode) else {
            throw DeviceSessionError.httpError(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw DeviceSessionError.decodingFailed
        }
        return decoded
    }

    private func send<Body: Encodable>(_ request: URLRequest, body: Body) async throws -> (Data, URLResponse) {
        var request = request
        request.httpBody = try JSONEncoder().encode(body)
        return try await session.data(for: request)
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let request = makeRequest(path: path)
        let (data, response) = try await send(request, body: body)
        guard let http = response as? HTTPURLResponse else { throw DeviceSessionError.decodingFailed }
        guard (200...299).contains(http.statusCode) else {
            throw DeviceSessionError.httpError(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw DeviceSessionError.decodingFailed
        }
        return decoded
    }
}
