@testable import WriterFlow
import XCTest

private actor FakeDeviceSession: DeviceSessionProviding {
    private let fixedState: DeviceSessionState
    private let token: String

    init(state: DeviceSessionState, token: String = "access-token-1") {
        self.fixedState = state
        self.token = token
    }

    var state: DeviceSessionState { fixedState }
    func beginPairing() async throws -> PairingChallenge { throw DeviceSessionError.notPaired }
    func awaitPairedToken() async throws { throw DeviceSessionError.notPaired }
    func accessToken() async throws -> String {
        guard case .signedIn = fixedState else { throw DeviceSessionError.notPaired }
        return token
    }
    func signOut() async {}
    func markSessionInvalid() async {}
    func forceRefreshAccessToken() async throws -> String { try await accessToken() }
    func handleForegroundHint() async {}
    func cancelPairing() async {}
}

final class WriterFlowInferenceTransportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private let testConfig = WriterFlowAPIConfig(baseURL: URL(string: "https://test.invalid/v2")!)

    private func makeRequest() -> InferenceFixGrammarRequest {
        .init(
            operationId: UUID(),
            retryOf: nil,
            bundleId: "com.apple.Notes",
            site: nil,
            windowClass: nil,
            targetScope: "field",
            draft: "Their going to the store.",
            selectedText: nil,
            conversation: nil,
            hasSelection: false,
            hasVisibleThread: false,
            outputModeHint: "replace"
        )
    }

    private func collect(_ stream: AsyncThrowingStream<InferenceStreamEvent, Error>) async throws -> [InferenceStreamEvent] {
        var events: [InferenceStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func sseBody(_ lines: [String]) -> Data {
        Data(lines.map { "data: \($0)\n\n" }.joined().utf8)
    }

    func testHappyPathYieldsCanonicalEventOrderAndSendsExpectedHeaders() async throws {
        let body = sseBody([
            #"{"type":"request.accepted","requestId":"30000000-0000-4000-8000-000000000004"}"#,
            #"{"type":"decision","intent":"grammar","confidence":null,"outputMode":"replace","route":"grammar_fast","reasonCode":null}"#,
            #"{"type":"output.delta","delta":"They're going to "}"#,
            #"{"type":"output.delta","delta":"the store."}"#,
            #"{"type":"usage.summary","usedUnits":1,"remainingUnits":499}"#,
            #"{"type":"completed","requestId":"30000000-0000-4000-8000-000000000004","promptVersion":"grammar@5.1.0"}"#
        ])
        MockURLProtocol.stub(method: "POST", pathSuffix: "/inference/stream", statusCode: 200, json: body)
        let session = FakeDeviceSession(state: .signedIn(deviceId: "device-1"))
        let transport = WriterFlowInferenceTransport(deviceSession: session, config: testConfig, session: MockURLProtocol.session)

        let events = try await collect(transport.streamFixGrammar(makeRequest()))

        XCTAssertEqual(events, [
            .requestAccepted(requestId: "30000000-0000-4000-8000-000000000004"),
            .decision(intent: "grammar", route: "grammar_fast", outputMode: "replace"),
            .delta("They're going to "),
            .delta("the store."),
            .usageSummary(usedUnits: 1, remainingUnits: 499),
            .completed(requestId: "30000000-0000-4000-8000-000000000004", promptVersion: "grammar@5.1.0")
        ])

        let request = try XCTUnwrap(MockURLProtocol.requests().first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-WriterFlow-Device"), "device-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testDeltaBeforeDecisionIsRejectedAsInvalidOrder() async throws {
        let body = sseBody([
            #"{"type":"output.delta","delta":"too early"}"#
        ])
        MockURLProtocol.stub(method: "POST", pathSuffix: "/inference/stream", statusCode: 200, json: body)
        let session = FakeDeviceSession(state: .signedIn(deviceId: "device-1"))
        let transport = WriterFlowInferenceTransport(deviceSession: session, config: testConfig, session: MockURLProtocol.session)

        do {
            _ = try await collect(transport.streamFixGrammar(makeRequest()))
            XCTFail("expected invalidOrder to be thrown")
        } catch WriterFlowInferenceError.invalidOrder {
            // expected
        }
    }

    func testUnrecognizedEventTypeInvalidatesTheStream() async throws {
        let body = sseBody([
            #"{"type":"decision","intent":"grammar","confidence":null,"outputMode":"replace","route":"grammar_fast","reasonCode":null}"#,
            #"{"type":"some.future.event"}"#
        ])
        MockURLProtocol.stub(method: "POST", pathSuffix: "/inference/stream", statusCode: 200, json: body)
        let session = FakeDeviceSession(state: .signedIn(deviceId: "device-1"))
        let transport = WriterFlowInferenceTransport(deviceSession: session, config: testConfig, session: MockURLProtocol.session)

        do {
            _ = try await collect(transport.streamFixGrammar(makeRequest()))
            XCTFail("expected malformedStream to be thrown")
        } catch WriterFlowInferenceError.malformedStream {
            // expected
        }
    }

    func testServerErrorEventThrowsWithCodeAndMessage() async throws {
        let body = sseBody([
            #"{"type":"error","code":"QUOTA_EXCEEDED","message":"Monthly usage limit reached.","requestId":null}"#
        ])
        MockURLProtocol.stub(method: "POST", pathSuffix: "/inference/stream", statusCode: 200, json: body)
        let session = FakeDeviceSession(state: .signedIn(deviceId: "device-1"))
        let transport = WriterFlowInferenceTransport(deviceSession: session, config: testConfig, session: MockURLProtocol.session)

        do {
            _ = try await collect(transport.streamFixGrammar(makeRequest()))
            XCTFail("expected .server to be thrown")
        } catch WriterFlowInferenceError.server(let code, let message) {
            XCTAssertEqual(code, "QUOTA_EXCEEDED")
            XCTAssertEqual(message, "Monthly usage limit reached.")
        }
    }

    func testNotSignedInThrowsWithoutMakingARequest() async throws {
        let session = FakeDeviceSession(state: .signedOut)
        let transport = WriterFlowInferenceTransport(deviceSession: session, config: testConfig, session: MockURLProtocol.session)

        do {
            _ = try await collect(transport.streamFixGrammar(makeRequest()))
            XCTFail("expected notSignedIn to be thrown")
        } catch DeviceSessionError.notPaired {
            // FakeDeviceSession.accessToken() throws first, matching how a
            // real DeviceSessionStore would behave when never paired.
        }
        XCTAssertTrue(MockURLProtocol.requests().isEmpty)
    }
}
