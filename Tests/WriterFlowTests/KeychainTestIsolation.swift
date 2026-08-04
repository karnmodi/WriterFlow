import XCTest
@testable import WriterFlow

/// Points `DeviceTokenKeychain` at a throwaway Keychain service for the
/// duration of a test.
///
/// Tests used to read and write the production item directly, which destroyed
/// whatever session the user was actually signed into on the machine running
/// them. It also made cleanup unreliable: the unsigned `swift test` binary is a
/// different code-signing identity from the installed app, so it cannot delete
/// an item the app created, and leftover state leaked between tests.
enum KeychainTestIsolation {
    static func begin() {
        DeviceTokenKeychain.serviceOverrideForTesting = "com.karan.writerflow.device-session.tests"
        DeviceTokenKeychain.delete()
        DeviceTokenKeychain.invalidateCache()
    }

    static func end() {
        DeviceTokenKeychain.delete()
        DeviceTokenKeychain.invalidateCache()
        DeviceTokenKeychain.serviceOverrideForTesting = nil
    }
}
