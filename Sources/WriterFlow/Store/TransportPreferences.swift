import Foundation

/// Stage 5.4 cohort flag — when true and the user is signed in, eligible actions
/// route through WriterFlow's cloud inference API instead of BYO Azure.
enum TransportPreferences {
    private static let useCloudInferenceKey = "writerflow.transport.useCloudInference"

    static var useCloudInference: Bool {
        get { UserDefaults.standard.bool(forKey: useCloudInferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: useCloudInferenceKey) }
    }
}
