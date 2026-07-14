import Charts
import SwiftUI

struct UsageView: View {
    @ObservedObject var viewModel: UsageViewModel

    /// Fixed hue order matching `WritingAction.allCases` — identity by action never shifts
    /// even as filters change which actions have data in a given window.
    private static let actionOrder = ["Elaborate", "Formal", "Casual", "Fix Grammar", "Reply", "Prompt Builder", "Custom"]
    private static let actionColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statTiles
                granularityPicker
                actionVolumeChart
                tokenVolumeChart
                Spacer(minLength: 8)
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage")
                .font(.title2).bold()
            Text("What WriterFlow has actually done, and roughly what it cost. Acceptance rate is the number that matters most — it's the share of rewrites you kept.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            StatTile(
                title: "Acceptance Rate",
                value: viewModel.acceptanceRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                subtitle: viewModel.totalActions == 0 ? "No actions yet" : "of \(viewModel.totalActions) actions kept",
                emphasize: true
            )
            StatTile(
                title: "Total Actions",
                value: "\(viewModel.totalActions)",
                subtitle: "all time"
            )
            StatTile(
                title: "Tokens Used",
                value: formattedTokenCount(viewModel.totalTokensIn + viewModel.totalTokensOut),
                subtitle: "\(formattedTokenCount(viewModel.totalTokensIn)) in / \(formattedTokenCount(viewModel.totalTokensOut)) out"
            )
            StatTile(
                title: "Estimated Cost",
                value: String(format: "$%.2f", viewModel.estimatedCostUSD),
                subtitle: "from Settings tab pricing"
            )
        }
    }

    private var granularityPicker: some View {
        Picker("Granularity", selection: $viewModel.granularity) {
            ForEach(UsageViewModel.Granularity.allCases) { g in
                Text(g.rawValue).tag(g)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
        .labelsHidden()
    }

    private var actionVolumeChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actions by Type")
                .font(.headline)
            if viewModel.actionCountsBySeries.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(viewModel.actionCountsBySeries) { row in
                    BarMark(
                        x: .value(viewModel.granularity == .daily ? "Day" : "Week", row.bucketStart, unit: viewModel.granularity == .daily ? .day : .weekOfYear),
                        y: .value("Count", row.count)
                    )
                    .foregroundStyle(by: .value("Action", row.series))
                }
                .chartForegroundStyleScale(domain: Self.actionOrder, range: Self.actionColors)
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 220)
            }
        }
    }

    private var tokenVolumeChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token Volume")
                .font(.headline)
            if viewModel.tokenCountsBySeries.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(viewModel.tokenCountsBySeries) { row in
                    BarMark(
                        x: .value(viewModel.granularity == .daily ? "Day" : "Week", row.bucketStart, unit: viewModel.granularity == .daily ? .day : .weekOfYear),
                        y: .value("Tokens", row.count)
                    )
                    .foregroundStyle(by: .value("Direction", row.series))
                }
                .chartForegroundStyleScale(domain: ["Input", "Output"], range: [.blue, .orange])
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 220)
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        Text("Not enough data yet in this window.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }

    private func formattedTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String
    var emphasize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(emphasize ? .system(size: 30, weight: .bold) : .title2.bold())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.25)))
    }
}
