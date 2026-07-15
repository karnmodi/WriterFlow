import SwiftUI

struct DashboardView: View {
    @State private var selectedTab: DashboardTab? = .history
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .toolbar { sectionToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 640, minHeight: 480)
    }

    private var sidebar: some View {
        List(selection: $selectedTab) {
            Section("WriterFlow") {
                ForEach(DashboardTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 150, ideal: 190, max: 220)
    }

    @ToolbarContentBuilder
    private var sectionToolbar: some ToolbarContent {
        if columnVisibility != .all {
            ToolbarItem(placement: .navigation) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases) { tab in
                        Text(tab.title).tag(Optional(tab))
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 140)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab ?? .history {
        case .history:
            HistoryView(viewModel: historyViewModel)
        case .personalization:
            PersonalizationView(viewModel: personalizationViewModel)
        case .settings:
            SettingsTabView(modelsConfig: modelsConfig)
        case .usage:
            UsageView(viewModel: usageViewModel)
        }
    }
}
