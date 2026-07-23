import Foundation

/// Stage 5.4 cohort flag — when true and the user is signed in, eligible actions
/// route through WriterFlow's cloud inference API instead of BYO Azure.
enum TransportPreferences {
    private static let useCloudInferenceKey = "writerflow.transport.useCloudInference"
    private static let allowByoFallbackKey = "writerflow.transport.allowByoFallback"

    static var useCloudInference: Bool {
        get {
            guard UserDefaults.standard.object(forKey: useCloudInferenceKey) != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: useCloudInferenceKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: useCloudInferenceKey) }
    }

    static var allowByoFallback: Bool {
        get {
            guard UserDefaults.standard.object(forKey: allowByoFallbackKey) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: allowByoFallbackKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: allowByoFallbackKey) }
    }

    static func apply(useCloudInference: Bool, allowByoFallback: Bool) {
        self.useCloudInference = useCloudInference
        self.allowByoFallback = allowByoFallback
    }
}
