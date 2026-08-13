import XCTest
@testable import WriterFlow

final class ComposeAppPolicyTests: XCTestCase {
    func testDefaultIsStandard() {
        XCTAssertEqual(ComposeAppPolicy.resolve(bundleID: "com.apple.Notes", windowTitle: nil), .standard)
        XCTAssertEqual(ComposeAppPolicy.resolve(bundleID: "com.google.Chrome", windowTitle: "Gmail"), .standard)
    }

    func testCursorAndVSCodeUseTallCompose() {
        XCTAssertEqual(
            ComposeAppPolicy.resolve(bundleID: "com.todesktop.230313mzl4w4u92", windowTitle: nil),
            .tallCompose
        )
        XCTAssertEqual(
            ComposeAppPolicy.resolve(bundleID: "com.microsoft.VSCode", windowTitle: nil),
            .tallCompose
        )
        XCTAssertEqual(ComposeAppPolicy.tallComposeMaxHeight, 800)
    }

    func testGoogleDocsDocumentSurface() {
        XCTAssertEqual(
            ComposeAppPolicy.resolve(
                bundleID: "com.google.Chrome",
                windowTitle: "Project plan - Google Docs"
            ),
            .documentSurface
        )
        XCTAssertNil(ComposeAppPolicy.documentSurfaceMaxHeight)
    }

    func testSpreadsheetBundles() {
        XCTAssertEqual(
            ComposeAppPolicy.resolve(bundleID: "com.microsoft.Excel", windowTitle: nil),
            .spreadsheet
        )
        XCTAssertEqual(
            ComposeAppPolicy.resolve(bundleID: "com.apple.iWork.Numbers", windowTitle: nil),
            .spreadsheet
        )
    }

    func testStandardLimitsUnchanged() {
        XCTAssertEqual(ComposeAppPolicy.standard.maxWebHeight, 600)
        XCTAssertEqual(ComposeAppPolicy.standard.maxWebWidth, 1_200)
        XCTAssertTrue(ComposeAppPolicy.standard.enforcesWindowAreaFraction)
    }
}

private extension ComposeAppPolicy {
    static var tallComposeMaxHeight: CGFloat { ComposeAppPolicy.tallCompose.maxWebHeight ?? -1 }
    static var documentSurfaceMaxHeight: CGFloat? { ComposeAppPolicy.documentSurface.maxWebHeight }
}
