@testable import WriterFlow
import XCTest

final class TransportPreferencesTests: XCTestCase {
    private let key = "writerflow.transport.useCloudInference"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testUseCloudInferenceDefaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(TransportPreferences.useCloudInference)
    }

    func testUseCloudInferencePersists() {
        TransportPreferences.useCloudInference = true
        XCTAssertTrue(TransportPreferences.useCloudInference)
        TransportPreferences.useCloudInference = false
        XCTAssertFalse(TransportPreferences.useCloudInference)
    }
}

final class InferenceTransportRoutingTests: XCTestCase {
    func testCloudInferenceEnabledOnlyForSignedInFixGrammarWithFlagAndTransport() {
        XCTAssertTrue(cloudInferenceEnabled(
            action: .fixGrammar,
            useCloudInference: true,
            sessionState: .signedIn(deviceId: "device-1"),
            hasTransport: true
        ))
        XCTAssertFalse(cloudInferenceEnabled(
            action: .fixGrammar,
            useCloudInference: false,
            sessionState: .signedIn(deviceId: "device-1"),
            hasTransport: true
        ))
        XCTAssertFalse(cloudInferenceEnabled(
            action: .fixGrammar,
            useCloudInference: true,
            sessionState: .signedOut,
            hasTransport: true
        ))
        XCTAssertFalse(cloudInferenceEnabled(
            action: .fixGrammar,
            useCloudInference: true,
            sessionState: .signedIn(deviceId: "device-1"),
            hasTransport: false
        ))
        XCTAssertFalse(cloudInferenceEnabled(
            action: .elaborate,
            useCloudInference: true,
            sessionState: .signedIn(deviceId: "device-1"),
            hasTransport: true
        ))
    }
}

final class InferenceRequestBuilderTests: XCTestCase {
    private func snapshot(
        fullText: String,
        selectedText: String = "",
        selectedRange: NSRange = NSRange(location: 0, length: 0)
    ) -> FieldSnapshot {
        FieldSnapshot(
            fullText: fullText,
            selectedText: selectedText,
            selectedRange: selectedRange,
            role: "AXTextArea",
            appBundleID: "com.apple.Notes",
            windowTitle: "Note"
        )
    }

    func testFixGrammarFieldScopeUsesFullDraft() {
        let request = InferenceRequestBuilder.fixGrammar(
            snapshot: snapshot(fullText: "Their going to the store."),
            site: "notes",
            conversation: nil
        )
        XCTAssertEqual(request.targetScope, "field")
        XCTAssertEqual(request.draft, "Their going to the store.")
        XCTAssertNil(request.selectedText)
        XCTAssertFalse(request.hasSelection)
        XCTAssertEqual(request.bundleId, "com.apple.Notes")
        XCTAssertEqual(request.site, "notes")
        XCTAssertEqual(request.outputModeHint, "replace")
    }

    func testFixGrammarSelectionScopeIncludesSelectedText() {
        let request = InferenceRequestBuilder.fixGrammar(
            snapshot: snapshot(
                fullText: "hey can we push the launch back a bit, not feeling ready",
                selectedText: "not feeling ready",
                selectedRange: NSRange(location: 41, length: 17)
            ),
            site: nil,
            conversation: "Prior thread"
        )
        XCTAssertEqual(request.targetScope, "selection")
        XCTAssertEqual(request.selectedText, "not feeling ready")
        XCTAssertTrue(request.hasSelection)
        XCTAssertTrue(request.hasVisibleThread)
    }
}
