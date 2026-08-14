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

    func testSoftHideOnlyWhenRecoverable() {
        XCTAssertTrue(
            PreviewSession.shouldSoftHideOnDismiss(
                hasActiveSession: true,
                isStreaming: true,
                hasVisibleText: false,
                hasError: false,
                isClarify: false
            )
        )
        XCTAssertTrue(
            PreviewSession.shouldSoftHideOnDismiss(
                hasActiveSession: true,
                isStreaming: false,
                hasVisibleText: true,
                hasError: false,
                isClarify: false
            )
        )
        XCTAssertFalse(
            PreviewSession.shouldSoftHideOnDismiss(
                hasActiveSession: false,
                isStreaming: false,
                hasVisibleText: false,
                hasError: false,
                isClarify: false
            )
        )
        // Terminal generation failure → hard-clear back to the floating icon.
        XCTAssertFalse(
            PreviewSession.shouldSoftHideOnDismiss(
                hasActiveSession: true,
                isStreaming: false,
                hasVisibleText: false,
                hasError: true,
                isClarify: false
            )
        )
    }

    func testBusyIconWhileSoftHiddenSession() {
        XCTAssertTrue(
            PreviewSession.isIconBusy(
                isStreaming: false,
                isSoftHidden: true,
                hasActiveSession: true,
                hasError: false
            )
        )
        XCTAssertTrue(
            PreviewSession.isIconBusy(
                isStreaming: true,
                isSoftHidden: true,
                hasActiveSession: true,
                hasError: false
            )
        )
        XCTAssertFalse(
            PreviewSession.isIconBusy(
                isStreaming: false,
                isSoftHidden: false,
                hasActiveSession: false,
                hasError: false
            )
        )
        XCTAssertFalse(
            PreviewSession.isIconBusy(
                isStreaming: false,
                isSoftHidden: true,
                hasActiveSession: true,
                hasError: true
            )
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
