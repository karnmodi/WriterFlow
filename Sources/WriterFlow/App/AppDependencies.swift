import Foundation

/// One composition root for production services. Feature code receives
/// protocols and never constructs a BYO or WriterFlow transport itself.
@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let modelsConfig: AzureModelsConfig
    let deviceSession: any DeviceSessionProviding
    let writerFlowAPI: WriterFlowAPIClient
    let inferenceTransport: any InferenceTransport
    let legacyActionClient: any LegacyActionInferenceClient
    let recommendationClassifier: any RecommendationClassifying

    private init() {
        let modelsConfig = AzureModelsConfig.load()
        let deviceSession: any DeviceSessionProviding = DeviceSessionStore()
        self.modelsConfig = modelsConfig
        self.deviceSession = deviceSession
        writerFlowAPI = WriterFlowAPIClient()
        inferenceTransport = WriterFlowInferenceTransport(deviceSession: deviceSession)
        legacyActionClient = AzureLegacyActionInferenceAdapter(config: modelsConfig)
        recommendationClassifier = AzureRecommendationAdapter(config: modelsConfig)
    }
}
