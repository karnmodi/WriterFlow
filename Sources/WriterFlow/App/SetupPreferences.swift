import Foundation

/// Persists whether the user closed Setup and asked not to see it on every launch.
enum SetupPreferences {
    private static let dismissedKey = "writerflow.setup.userDismissed"

    static var userDismissedSetup: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }
}
