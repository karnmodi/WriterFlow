import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var showClearConfirm = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                list
            }
            .searchable(text: $viewModel.searchText, prompt: "Search input & output")
            .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        } detail: {
            if let id = viewModel.selectedEventID,
               let event = viewModel.events.first(where: { $0.id == id }) {
                HistoryDetailView(event: event)
            } else {
                ContentUnavailableFallback()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear History", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
        .confirmationDialog(
            "Delete all conversion history? This can't be undone.",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                viewModel.clearAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("App", selection: $viewModel.appFilter) {
                Text("All Apps").tag(String?.none)
                ForEach(viewModel.availableApps, id: \.self) { app in
                    Text(app).tag(String?.some(app))
                }
            }
            Picker("Action", selection: $viewModel.actionFilter) {
                Text("All Actions").tag(String?.none)
                ForEach(viewModel.availableActions, id: \.self) { action in
                    Text(action).tag(String?.some(action))
                }
            }
            Picker("Status", selection: $viewModel.acceptedFilter) {
                Text("All").tag(Bool?.none)
                Text("Accepted").tag(Bool?.some(true))
                Text("Discarded").tag(Bool?.some(false))
            }
        }
        .labelsHidden()
        .padding(8)
    }

    private var list: some View {
        List(selection: $viewModel.selectedEventID) {
            ForEach(viewModel.groupedEvents, id: \.day) { group in
                Section(sectionTitle(for: group.day)) {
                    ForEach(group.events) { event in
                        HistoryRowView(event: event)
                            .tag(event.id)
                    }
                }
            }
        }
        .overlay {
            if viewModel.filteredEvents.isEmpty {
                ContentUnavailableFallback(message: viewModel.events.isEmpty
                    ? "No conversions yet — actions you accept or run will show up here."
                    : "No conversions match your search/filters.")
            }
        }
    }

    private func sectionTitle(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct ContentUnavailableFallback: View {
    var message: String = "Select a conversion to see its detail."

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
