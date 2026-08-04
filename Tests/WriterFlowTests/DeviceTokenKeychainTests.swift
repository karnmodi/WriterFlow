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
        KeychainTestIsolation.begin()
    }

    override func tearDown() {
        KeychainTestIsolation.end()
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

        // Drop the in-process mirror so this still proves the tokens reached
        // the Keychain rather than just the cache.
        DeviceTokenKeychain.invalidateCache()
        let read = DeviceTokenKeychain.read()
        XCTAssertEqual(read, tokens)
    }

    /// Regression: `write` used to `SecItemDelete` + `SecItemAdd`, replacing the
    /// item and with it the ACL — discarding the "Always Allow" the user had
    /// granted this build, so the next launch prompted for the Keychain
    /// password all over again. Because the access token rotates on nearly
    /// every launch, that reset the grant indefinitely. Rotating a token has to
    /// update the existing item in place.
    func testWriteUpdatesTheExistingItemInsteadOfRecreatingIt() {
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-1")))

        // Stands in for the item's ACL: per-item state that only survives if
        // the item itself survives a write.
        let marker = "acl-survival-marker"
        XCTAssertEqual(
            SecItemUpdate(
                DeviceTokenKeychain.baseQuery() as CFDictionary,
                [kSecAttrComment as String: marker] as CFDictionary
            ),
            errSecSuccess
        )

        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-2")))

        XCTAssertEqual(storedComment(), marker, "rotating the token must not replace the Keychain item")
        DeviceTokenKeychain.invalidateCache()
        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-2", "the rotated token must still persist")
    }

    /// New writes target AfterFirstUnlock so launch-at-login does not race an
    /// interactive unlock prompt. (macOS often omits `kSecAttrAccessible` from
    /// `SecItemCopyMatching` attribute dumps, so this asserts the write path's
    /// constant rather than round-tripping the stored attribute.)
    func testPreferredAccessibleIsAfterFirstUnlock() {
        XCTAssertEqual(
            DeviceTokenKeychain.preferredAccessible as String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    /// `KeychainItem.write` must never delete+recreate on update failure — that
    /// would wipe Always Allow. Simulate a locked-out update by deleting the
    /// item mid-flight is not reliable under test ACLs; instead assert that a
    /// successful rotation preserves creation date (cdat) while updating mdat.
    func testTokenRotationPreservesItemCreationDate() throws {
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-1")))
        let created = try XCTUnwrap(storedCreationDate())

        // Brief pause so mdat can differ from cdat on filesystems with 1s resolution.
        Thread.sleep(forTimeInterval: 1.1)
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-2")))

        XCTAssertEqual(storedCreationDate(), created, "update-in-place must keep the original Keychain item")
        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-2")
    }

    /// Every uncached read of this item can cost the user a Keychain password
    /// prompt, and `DeviceSessionStore` reads it from `init` plus every
    /// `accessToken()` call. One launch must mean one Keychain hit.
    func testRepeatedReadsAreServedFromTheCache() throws {
        XCTAssertTrue(DeviceTokenKeychain.write(makeTokens(deviceID: "device-1")))
        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-1")

        // Rewrite the stored bytes behind the cache's back. A second read that
        // still reports device-1 proves it never went back to the Keychain.
        let rotated = try JSONEncoder().encode(makeTokens(deviceID: "device-2"))
        XCTAssertEqual(
            SecItemUpdate(
                DeviceTokenKeychain.baseQuery() as CFDictionary,
                [kSecValueData as String: rotated] as CFDictionary
            ),
            errSecSuccess
        )

        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-1")
        DeviceTokenKeychain.invalidateCache()
        XCTAssertEqual(DeviceTokenKeychain.read()?.deviceID, "device-2")
    }

    private func storedComment() -> String? {
        storedAttributes()?[kSecAttrComment as String] as? String
    }

    private func storedCreationDate() -> Date? {
        storedAttributes()?[kSecAttrCreationDate as String] as? Date
    }

    private func storedAttributes() -> [String: Any]? {
        var query = DeviceTokenKeychain.baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any] else { return nil }
        return attributes
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
