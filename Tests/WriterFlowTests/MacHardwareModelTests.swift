import XCTest
@testable import WriterFlow

final class MacHardwareModelTests: XCTestCase {
    func testFriendlyNameIsNeverEmptyAndNeverContainsADigit() {
        let name = MacHardwareModel.friendlyName
        XCTAssertFalse(name.isEmpty)
        XCTAssertFalse(name.contains(where: \.isNumber), "must be a generic family name, not a specific hardware revision")
    }

    func testFriendlyNameNeverLooksLikeAPersonalHostname() {
        // The bug this guards against: Host.current().localizedName on macOS
        // is typically "<Owner's Name>'s MacBook Pro" — a hostname, not a
        // generic label, and exactly what Docs/contracts/openapi.yaml's
        // deviceLabel field says this must never be.
        let name = MacHardwareModel.friendlyName
        XCTAssertFalse(name.contains("'s "), "must not resemble a possessive hostname like \"Karan's MacBook Pro\"")
    }
}
