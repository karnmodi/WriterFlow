import XCTest
@testable import WriterFlow

final class TerminalAppsTests: XCTestCase {
    func testKnownTerminals() {
        XCTAssertTrue(TerminalApps.isTerminal(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(TerminalApps.isTerminal(bundleID: "com.googlecode.iterm2"))
        XCTAssertTrue(TerminalApps.isTerminal(bundleID: "com.mitchellh.ghostty"))
        XCTAssertTrue(TerminalApps.isTerminal(bundleID: "org.alacritty"))
        XCTAssertFalse(TerminalApps.isTerminal(bundleID: "com.apple.Notes"))
    }

    func testCurrentLineFromScrollback() {
        let scrollback = """
        last login: today
        $ echo hello
        hello
        $ draft command here
        """
        XCTAssertEqual(TerminalApps.currentLine(from: scrollback), "$ draft command here")
    }

    func testAdapterSupportsReplace() {
        XCTAssertTrue(TerminalAdapter().supportsReplace)
        XCTAssertEqual(
            AppAdapterRegistry.siteLabel(bundleID: "com.apple.Terminal", windowTitle: nil),
            "terminal"
        )
    }

    func testGoogleDocsSiteLabel() {
        XCTAssertEqual(
            AppAdapterRegistry.siteLabel(
                bundleID: "com.google.Chrome",
                windowTitle: "Notes - Google Docs"
            ),
            "google-docs"
        )
    }

    func testVSCodeSiteLabel() {
        XCTAssertEqual(
            AppAdapterRegistry.siteLabel(bundleID: "com.microsoft.VSCode", windowTitle: nil),
            "vscode"
        )
    }
}
