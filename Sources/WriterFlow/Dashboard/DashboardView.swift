import SwiftUI

struct DashboardView: View {
    @StateObject private var historyViewModel = HistoryViewModel()
    @StateObject private var personalizationViewModel: PersonalizationViewModel
    @StateObject private var usageViewModel: UsageViewModel
    private let modelsConfig: AzureModelsConfig

    init(modelsConfig: AzureModelsConfig) {
        self.modelsConfig = modelsConfig
        _personalizationViewModel = StateObject(wrappedValue: PersonalizationViewModel(modelsConfig: modelsConfig))
        _usageViewModel = StateObject(wrappedValue: UsageViewModel(modelsConfig: modelsConfig))
    }

    var body: some View {
        TabView {
            HistoryView(viewModel: historyViewModel)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            PersonalizationView(viewModel: personalizationViewModel)
                .tabItem { Label("Personalization", systemImage: "person.text.rectangle") }

            SettingsTabView(modelsConfig: modelsConfig)
                .tabItem { Label("Settings", systemImage: "gearshape") }

            UsageView(viewModel: usageViewModel)
                .tabItem { Label("Usage", systemImage: "chart.bar") }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}
