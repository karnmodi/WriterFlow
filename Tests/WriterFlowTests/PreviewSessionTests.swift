import XCTest
@testable import WriterFlow

final class PreviewSessionTests: XCTestCase {
    func testActiveSessionWhileStreaming() {
        XCTAssertTrue(
            PreviewSession.hasActiveSession(
                pendingAction: .formal,
                isStreaming: true,
                hasVisibleText: false,
                hasError: false,
                isClarify: false
            )
        )
    }

    func testActiveSessionWithUnseenResult() {
        XCTAssertTrue(
            PreviewSession.hasActiveSession(
                pendingAction: .fixGrammar,
                isStreaming: false,
                hasVisibleText: true,
                hasError: false,
                isClarify: false
            )
        )
    }

    func testInactiveWithoutPendingAction() {
        XCTAssertFalse(
            PreviewSession.hasActiveSession(
                pendingAction: nil,
                isStreaming: false,
                hasVisibleText: true,
                hasError: false,
                isClarify: false
            )
        )
    }

    func testSoftHideOnlyWhenSessionActive() {
        XCTAssertTrue(PreviewSession.shouldSoftHideOnDismiss(hasActiveSession: true))
        XCTAssertFalse(PreviewSession.shouldSoftHideOnDismiss(hasActiveSession: false))
    }

    func testBusyIconWhileSoftHiddenSession() {
        XCTAssertTrue(
            PreviewSession.isIconBusy(isStreaming: false, isSoftHidden: true, hasActiveSession: true)
        )
        XCTAssertTrue(
            PreviewSession.isIconBusy(isStreaming: true, isSoftHidden: true, hasActiveSession: true)
        )
        XCTAssertFalse(
            PreviewSession.isIconBusy(isStreaming: false, isSoftHidden: false, hasActiveSession: false)
        )
    }

    func testAutoRestoreOnCompletion() {
        XCTAssertTrue(
            PreviewSession.shouldAutoRestoreOnCompletion(isSoftHidden: true, hasActiveSession: true)
        )
        XCTAssertFalse(
            PreviewSession.shouldAutoRestoreOnCompletion(isSoftHidden: false, hasActiveSession: true)
        )
    }
}
