import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @State private var showClearConfirm = false

    var body: some View {
        HSplitView {
            listColumn
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 420)
            detailColumn
                .frame(minWidth: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var listColumn: some View {
        VStack(spacing: 0) {
            Text("Every rewrite WriterFlow has run or you've accepted, newest first. Search looks at both the original and rewritten text.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .fixedSize(horizontal: false, vertical: true)

            historyControls
            filterBar
            Divider()
            list
        }
    }

    private var detailColumn: some View {
        Group {
            if let id = viewModel.selectedEventID,
               let event = viewModel.events.first(where: { $0.id == id }) {
                HistoryDetailView(event: event)
            } else {
                ContentUnavailableFallback()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                appFilterPicker.frame(maxWidth: .infinity)
                actionFilterPicker.frame(maxWidth: .infinity)
                statusFilterPicker.frame(width: 120)
            }
            VStack(spacing: 8) {
                appFilterPicker
                actionFilterPicker
                statusFilterPicker
            }
        }
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var historyControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search input & output", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.separator.opacity(0.35))
                    }
            }

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.events.isEmpty)
            .help("Clear History")
            .accessibilityLabel("Clear History")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var appFilterPicker: some View {
        Picker("App", selection: $viewModel.appFilter) {
            Text("All Apps").tag(String?.none)
            ForEach(viewModel.availableApps, id: \.self) { app in
                Text(app).tag(String?.some(app))
            }
        }
    }

    private var actionFilterPicker: some View {
        Picker("Action", selection: $viewModel.actionFilter) {
            Text("All Actions").tag(String?.none)
            ForEach(viewModel.availableActions, id: \.self) { action in
                Text(action).tag(String?.some(action))
            }
        }
    }

    private var statusFilterPicker: some View {
        Picker("Status", selection: $viewModel.acceptedFilter) {
            Text("All").tag(Bool?.none)
            Text("Accepted").tag(Bool?.some(true))
            Text("Discarded").tag(Bool?.some(false))
        }
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
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
