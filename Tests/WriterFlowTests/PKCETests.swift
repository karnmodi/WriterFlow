import XCTest
import CryptoKit
@testable import WriterFlow

final class PKCETests: XCTestCase {
    func testVerifierIsWithinRFC7636Length() {
        let pair = PKCE.generate()
        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertLessThanOrEqual(pair.verifier.count, 128)
    }

    func testVerifierUsesOnlyUnreservedCharacters() {
        let pair = PKCE.generate()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        XCTAssertTrue(pair.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testChallengeMatchesIndependentSHA256Computation() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedDigest = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(expectedDigest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
    }

    func testGeneratedPairsAreUnique() {
        let pairs = (0..<200).map { _ in PKCE.generate() }
        let verifiers = Set(pairs.map(\.verifier))
        XCTAssertEqual(verifiers.count, 200)
    }

    func testChallengeIsDeterministicForAGivenVerifier() {
        let pair = PKCE.generate()
        XCTAssertEqual(PKCE.challenge(for: pair.verifier), pair.challenge)
    }
}
