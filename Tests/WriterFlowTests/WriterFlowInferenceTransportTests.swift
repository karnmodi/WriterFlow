@testable import WriterFlow
import XCTest

private actor FakeDeviceSession: DeviceSessionProviding {
    private let fixedState: DeviceSessionState
    private let token: String
    private var refreshCount = 0

    init(state: DeviceSessionState, token: String = "access-token-1") {
        self.fixedState = state
        self.token = token
    }

    var state: DeviceSessionState { fixedState }
    var needsRelaunchAfterAccountSwitch: Bool { false }
    func beginPairing() async throws -> PairingChallenge { throw DeviceSessionError.notPaired }
    func awaitPairedToken() async throws { throw DeviceSessionError.notPaired }
    func accessToken() async throws -> String {
        guard case .signedIn = fixedState else { throw DeviceSessionError.notPaired }
        return token
    }
    func signOut() async {}
    func markSessionInvalid() async {}
    func forceRefreshAccessToken() async throws -> String {
        refreshCount += 1
        return "access-token-refreshed"
    }
    func forcedRefreshCount() -> Int { refreshCount }
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

    private func makeRequest() -> InferenceRequest {
        .init(
            action: .fixGrammar,
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
            customInstruction: nil,
            promptBuilder: nil,
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

    func testCustomActionSendsRequestedActionAndInstruction() async throws {
        let body = sseBody([
            #"{"type":"decision","intent":"custom","confidence":null,"outputMode":"insert_before","route":"rewrite_standard","reasonCode":null}"#,
            #"{"type":"output.delta","delta":"Launch summary"}"#,
            #"{"type":"completed","requestId":"30000000-0000-4000-8000-000000000005","promptVersion":"custom@5.1.0"}"#
        ])
        MockURLProtocol.stub(method: "POST", pathSuffix: "/inference/stream", statusCode: 200, json: body)
        let session = FakeDeviceSession(state: .signedIn(deviceId: "device-1"))
        let transport = WriterFlowInferenceTransport(deviceSession: session, config: testConfig, session: MockURLProtocol.session)
        let request = InferenceRequestBuilder.build(
            action: .custom,
            snapshot: FieldSnapshot(
                fullText: "WriterFlow launches Friday.",
                selectedText: "",
                selectedRange: NSRange(location: 0, length: 0),
                role: "AXTextArea",
                appBundleID: "com.apple.Notes",
                windowTitle: "Note"
            ),
            site: nil,
            conversation: nil,
            customInstruction: "Write a short title"
        )

        _ = try await collect(transport.stream(request))

        let urlRequest = try XCTUnwrap(MockURLProtocol.requests().first)
        let data = try XCTUnwrap(urlRequest.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let task = try XCTUnwrap(json["task"] as? [String: Any])
        XCTAssertEqual(task["requestedAction"] as? String, "custom")
        XCTAssertEqual(task["customInstruction"] as? String, "Write a short title")
        XCTAssertEqual(task["outputModeHint"] as? String, "insert_before")
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

    func testUnauthorizedInferenceRefreshesOnceAndRetries() async throws {
        MockURLProtocol.stub(
            method: "POST",
            pathSuffix: "/inference/stream",
            statusCode: 401,
            json: Data()
        )
        MockURLProtocol.stub(
            method: "POST",
            pathSuffix: "/inference/stream",
            statusCode: 200,
            json: sseBody([
                #"{"type":"request.accepted","requestId":"30000000-0000-4000-8000-000000000006"}"#,
                #"{"type":"decision","intent":"grammar","confidence":null,"outputMode":"replace","route":"grammar_fast","reasonCode":null}"#,
                #"{"type":"output.delta","delta":"Fixed."}"#,
                #"{"type":"usage.summary","usedUnits":2,"remainingUnits":498}"#,
                #"{"type":"completed","requestId":"30000000-0000-4000-8000-000000000006","promptVersion":"grammar@5.1.0"}"#
            ])
        )
        let deviceSession = FakeDeviceSession(state: .signedIn(deviceId: "device-1"))
        let transport = WriterFlowInferenceTransport(
            deviceSession: deviceSession,
            config: testConfig,
            session: MockURLProtocol.session
        )

        let events = try await collect(transport.stream(makeRequest()))

        XCTAssertEqual(events.last, .completed(
            requestId: "30000000-0000-4000-8000-000000000006",
            promptVersion: "grammar@5.1.0"
        ))
        let refreshCount = await deviceSession.forcedRefreshCount()
        XCTAssertEqual(refreshCount, 1)
        let requests = MockURLProtocol.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-token-1")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-token-refreshed")
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Idempotency-Key"),
            requests[1].value(forHTTPHeaderField: "Idempotency-Key"),
            "a token refresh retry must remain the same idempotent operation"
        )
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
