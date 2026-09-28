import CoreGraphics
import XCTest
@testable import WriterFlow

@MainActor
final class Phase6PerceptionTests: XCTestCase {
    private func field(frame: CGRect = CGRect(x: 10, y: 20, width: 300, height: 80)) -> FocusedField {
        FocusedField(
            role: "AXTextArea",
            frame: frame,
            anchorRect: CGRect(x: 20, y: 30, width: 1, height: 18),
            appBundleID: "com.apple.Notes",
            appPID: 42
        )
    }

    private func snapshot(text: String = "Hello", selection: NSRange = NSRange(location: 5, length: 0)) -> FieldSnapshot {
        FieldSnapshot(
            fullText: text,
            selectedText: "",
            selectedRange: selection,
            role: "AXTextArea",
            appBundleID: "com.apple.Notes",
            windowTitle: "Project note"
        )
    }

    func testFocusedFieldIdentitySeparatesComposeBoxesInSameApp() {
        let first = field()
        let second = field(frame: first.frame.offsetBy(dx: 0, dy: 120))

        XCTAssertFalse(first.matchesRecommendationTarget(second))
    }

    func testTargetFingerprintRejectsContentAndSelectionChanges() {
        let target = TargetFingerprint.make(field: field(), snapshot: snapshot(), site: "notes")

        XCTAssertTrue(target.matches(field: field(), snapshot: snapshot(), site: "notes"))
        XCTAssertFalse(target.matches(field: field(), snapshot: snapshot(text: "Hello!"), site: "notes"))
        XCTAssertFalse(target.matches(
            field: field(),
            snapshot: snapshot(selection: NSRange(location: 0, length: 5)),
            site: "notes"
        ))
    }

    func testTargetFingerprintQuantizesSmallFrameMovement() {
        let target = TargetFingerprint.make(field: field(), snapshot: snapshot(), site: "notes")
        let smallMove = field(frame: CGRect(x: 11, y: 20, width: 300, height: 80))
        let largeMove = field(frame: CGRect(x: 18, y: 20, width: 300, height: 80))

        XCTAssertTrue(target.matches(field: smallMove, snapshot: snapshot(), site: "notes"))
        XCTAssertFalse(target.matches(field: largeMove, snapshot: snapshot(), site: "notes"))
    }

    func testWordAccumulatorPreservesExactOutput() {
        var emitted = ""
        let accumulator = WordStreamAccumulator(delay: .seconds(1)) { emitted += $0 }

        accumulator.push("Hel")
        accumulator.push("lo wor")
        accumulator.push("ld!\nNext")
        accumulator.flush()

        XCTAssertEqual(emitted, "Hello world!\nNext")
    }

    func testWordAccumulatorFlushesPartialWordAfterDeadline() async {
        var emitted = ""
        let accumulator = WordStreamAccumulator(delay: .milliseconds(10)) { emitted += $0 }

        accumulator.push("partial")
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(emitted, "partial")
    }

    func testContextCapsuleDebouncesAndExpires() async {
        let expectedSnapshot = snapshot()
        let store = ContextCapsuleStore(
            debounce: .milliseconds(10),
            idleLifetime: .milliseconds(35),
            snapshotReader: { _, _, _ in expectedSnapshot },
            conversationReader: { _, _ in "Visible thread" },
            secureInputEnabled: { false }
        )

        store.focus(field())
        XCTAssertNil(store.current)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(store.current, "Focus alone must not collect field context")

        store.fieldChanged(field())
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(store.current?.snapshot, expectedSnapshot)
        try? await Task.sleep(for: .milliseconds(45))
        XCTAssertNil(store.current)
    }

    func testContextCapsuleClearAndSecureInputFailClosed() async {
        let expectedSnapshot = snapshot()
        let store = ContextCapsuleStore(
            debounce: .milliseconds(1),
            idleLifetime: .seconds(1),
            snapshotReader: { _, _, _ in expectedSnapshot },
            conversationReader: { _, _ in nil },
            secureInputEnabled: { true }
        )

        let secureCapture = await store.captureForTrigger(field: field())
        XCTAssertNil(secureCapture)
        XCTAssertNil(store.current)
        store.focus(field())
        store.clear()
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertNil(store.current)
    }

    /// An explicit trigger (icon click / hotkey) has already passed the
    /// same user-initiated gate the legacy manual popover uses, so it may
    /// fall back to the clipboard when `kAXValue` is unreadable. The passive
    /// debounced refresh runs with no explicit action and must never do so.
    func testCaptureForTriggerAllowsClipboardFallbackButPassiveRefreshDoesNot() async {
        let expectedSnapshot = snapshot()
        let requestedFallback = ActorBox<[Bool]>([])
        let store = ContextCapsuleStore(
            debounce: .milliseconds(1),
            idleLifetime: .seconds(1),
            snapshotReader: { _, _, allowClipboardFallback in
                await requestedFallback.append(allowClipboardFallback)
                return expectedSnapshot
            },
            conversationReader: { _, _ in nil },
            secureInputEnabled: { false }
        )

        _ = await store.captureForTrigger(field: field())
        let afterTrigger = await requestedFallback.value
        XCTAssertEqual(afterTrigger, [true])

        store.fieldChanged(field())
        try? await Task.sleep(for: .milliseconds(20))
        let afterPassiveRefresh = await requestedFallback.value
        XCTAssertEqual(afterPassiveRefresh, [true, false])
    }
}

private actor ActorBox<Value> {
    private(set) var value: Value
    init(_ value: Value) { self.value = value }
    func append<Element>(_ element: Element) where Value == [Element] {
        value.append(element)
    }
}
