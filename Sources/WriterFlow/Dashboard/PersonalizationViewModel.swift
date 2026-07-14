import Foundation

/// Backs the Personalization tab's "Analyze my writing style" flow only — voice profile,
/// snippets/facts, and per-app rules are edited directly against `SettingsStore`,
/// `MemoryStore`, and `AppRuleStore` (all `@MainActor` `ObservableObject` singletons) from
/// `PersonalizationView`, so they don't need a proxy view model.
@MainActor
final class PersonalizationViewModel: ObservableObject {
    @Published var isAnalyzing = false
    @Published var proposedStyleText: String?
    @Published var statusMessage: String?
    @Published var statusIsError = false

    private let client: AzureOpenAIClient
    private static let minimumSamples = 3
    private static let sampleLimit = 20

    init(modelsConfig: AzureModelsConfig) {
        self.client = AzureOpenAIClient(config: modelsConfig)
    }

    func analyzeStyle() {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        statusMessage = nil
        statusIsError = false
        Task {
            let samples = await ConversionEventStore.shared.recentAcceptedOutputs(limit: Self.sampleLimit)
            guard samples.count >= Self.minimumSamples else {
                isAnalyzing = false
                statusIsError = true
                statusMessage = "Accept at least \(Self.minimumSamples) actions first — WriterFlow analyzes your own accepted outputs, never types you haven't confirmed."
                return
            }
            do {
                let result = try await client.analyzeWritingStyle(samples: samples)
                isAnalyzing = false
                proposedStyleText = result
            } catch {
                isAnalyzing = false
                statusIsError = true
                statusMessage = (error as? LocalizedError)?.errorDescription ?? "Analysis failed. Try again."
            }
        }
    }

    func approveProposedStyle() {
        guard let text = proposedStyleText else { return }
        Task { await MemoryStore.shared.add(kind: .style, text: text) }
        proposedStyleText = nil
        statusIsError = false
        statusMessage = "Added to your memory notes below."
    }

    func rejectProposedStyle() {
        proposedStyleText = nil
    }
}
