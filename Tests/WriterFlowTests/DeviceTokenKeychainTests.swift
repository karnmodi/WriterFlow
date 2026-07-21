import Security
import XCTest
@testable import WriterFlow

/// Stage 5.2 checklist: "Keychain read/write without an access group."
/// `DeviceSessionStoreTests`/`AccountViewModelTests` already exercise
/// read-after-write indirectly through `DeviceSessionStore`; this file
/// verifies the specific security property directly against
/// `DeviceTokenKeychain` itself, and that it never collides with
/// `KeychainStore`'s separate BYO-Azure-key item.
final class DeviceTokenKeychainTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DeviceTokenKeychain.delete()
    }

    override func tearDown() {
        DeviceTokenKeychain.delete()
        super.tearDown()
    }

    private func makeTokens(deviceID: String = "device-1") -> DeviceTokenKeychain.StoredTokens {
        .init(deviceID: deviceID, accessToken: "access-1", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "refresh-1")
    }

    func testBaseQueryNeverSetsAnAccessGroup() {
        let query = DeviceTokenKeychain.baseQuery()
        XCTAssertNil(
            query[kSecAttrAccessGroup as String],
            "device tokens must never be scoped to a shared Keychain access group (Stage 5.2 checklist)"
        )
    }

    func testBaseQueryScopesByThisItemsOwnServiceAndAccount() {
        let query = DeviceTokenKeychain.baseQuery()
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertNotNil(query[kSecAttrService as String])
        XCTAssertNotNil(query[kSecAttrAccount as String])
    }

    func testWriteThenReadRoundTripsWithoutAnAccessGroup() {
        let tokens = makeTokens()
        XCTAssertTrue(DeviceTokenKeychain.write(tokens))

        let read = DeviceTokenKeychain.read()
        XCTAssertEqual(read, tokens)
    }

    func testWriteOverwritesAPreviousItemRatherThanFailing() {
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-1")))
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-2")))

        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-2")
    }

    func testDeleteClearsTheItem() {
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens()))
        DeviceTokenKeychain.delete()

        XCTAssertNil(DeviceTokenKeychain.read())
    }

    func testReadWithNothingStoredReturnsNil() {
        XCTAssertNil(DeviceTokenKeychain.read())
    }

    /// The Stage 5.2 spec calls out that device tokens live in "the app's own
    /// Keychain item" — deliberately separate from `KeychainStore`'s BYO
    /// Azure key item, so signing out of a WriterFlow account can never
    /// touch a user's own Azure credential and vice versa.
    func testDeviceTokenItemIsIndependentOfKeychainStoresBYOAzureItem() {
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens()))
        KeychainStore.clearUserProvidedKey()

        XCTAssertNotNil(DeviceTokenKeychain.read(), "clearing an unrelated BYO-Azure key must not touch device tokens")
    }
}
