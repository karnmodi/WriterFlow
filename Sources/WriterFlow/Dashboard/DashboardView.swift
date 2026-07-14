import SwiftUI

struct DashboardView: View {
    @StateObject private var historyViewModel = HistoryViewModel()
    let settingsWindow: SettingsWindowController

    var body: some View {
        TabView {
            HistoryView(viewModel: historyViewModel)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            ComingSoonView(stage: "Stage 3.3", feature: "Personalization")
                .tabItem { Label("Personalization", systemImage: "person.text.rectangle") }

            SettingsTabView(settingsWindow: settingsWindow)
                .tabItem { Label("Settings", systemImage: "gearshape") }

            ComingSoonView(stage: "Stage 3.5", feature: "Usage")
                .tabItem { Label("Usage", systemImage: "chart.bar") }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

private struct ComingSoonView: View {
    let stage: String
    let feature: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("\(feature) ships in \(stage)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Stage 3.4 will move full settings editing into this tab; for now it hosts
/// the Phase 1.5 API-key panel that already exists as its own window.
private struct SettingsTabView: View {
    let settingsWindow: SettingsWindowController

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "gearshape")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Full settings editing (hotkey, models, retention) lands in Stage 3.4.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open API Key Settings…") {
                settingsWindow.show()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
