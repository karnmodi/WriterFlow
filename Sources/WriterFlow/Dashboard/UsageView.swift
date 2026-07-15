import Charts
import SwiftUI

struct UsageView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var hoveredAction: UsageViewModel.StackedSeriesCount?
    @State private var hoveredToken: UsageViewModel.StackedSeriesCount?

    private static let actionOrder = ["Elaborate", "Formal", "Casual", "Fix Grammar", "Reply", "Prompt Builder", "Custom"]
    private static let actionColors: [Color] = [.blue, .teal, .orange, .purple, .pink, .cyan, .indigo]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardChrome.sectionSpacing) {
                DashboardPageHeader(
                    title: "Usage",
                    subtitle: "Track writing activity, token usage, and the share of suggestions you kept."
                )

                statTiles

                HStack(spacing: 12) {
                    Text("Time range")
                        .font(.callout.weight(.medium))
                    Picker("Time range", selection: $viewModel.granularity) {
                        ForEach(UsageViewModel.Granularity.allCases) { granularity in
                            Text(granularity.rawValue).tag(granularity)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Spacer()

                    Label("Hover a chart for exact values", systemImage: "cursorarrow.motionlines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    actionVolumeChart
                        .frame(maxWidth: .infinity)
                    tokenVolumeChart
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(DashboardChrome.contentPadding)
        }
        .onChange(of: viewModel.granularity) {
            hoveredAction = nil
            hoveredToken = nil
        }
    }

    private var statTiles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                statTileContent
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                spacing: 12
            ) {
                statTileContent
            }
        }
    }

    @ViewBuilder
    private var statTileContent: some View {
        StatTile(
            title: "Acceptance Rate",
            value: viewModel.acceptanceRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
            subtitle: viewModel.totalActions == 0
                ? "No actions yet"
                : "\(viewModel.acceptedActions) of \(viewModel.totalActions) suggestions kept",
            emphasize: true
        )
        StatTile(
            title: "Total Actions",
            value: "\(viewModel.totalActions)",
            subtitle: "All recorded suggestions"
        )
        StatTile(
            title: "Tokens Used",
            value: formattedTokenCount(viewModel.totalTokensIn + viewModel.totalTokensOut),
            subtitle: tokenCoverageSubtitle
        )
        StatTile(
            title: "Estimated Cost",
            value: String(format: "$%.2f", viewModel.estimatedCostUSD),
            subtitle: viewModel.actionsUsingFallbackPricing == 0
                ? "Based on configured model pricing"
                : "\(viewModel.actionsUsingFallbackPricing) actions use fallback pricing"
        )
    }

    private var actionBarWidth: MarkDimension {
        switch viewModel.granularity {
        case .daily: return .fixed(28)
        case .weekly: return .fixed(34)
        }
    }

    private var actionVolumeChart: some View {
        DashboardCard(
            title: "Actions by Type",
            subtitle: "Suggestions generated in each \(periodName), stacked by action"
        ) {
            if viewModel.actionCountsBySeries.allSatisfy({ $0.count == 0 }) {
                emptyChartPlaceholder
            } else {
                let activeSeries = viewModel.activeActionSeries
                Chart {
                    ForEach(viewModel.actionStackedSeries) { row in
                        BarMark(
                            x: .value("Date", periodLabel(row.bucketStart)),
                            yStart: .value("Stack start", row.lowerBound),
                            yEnd: .value("Stack end", row.upperBound),
                            width: actionBarWidth
                        )
                        .foregroundStyle(by: .value("Action", row.series))
                        .opacity(hoveredAction == nil || hoveredAction?.id == row.id ? 1 : 0.35)
                        .accessibilityLabel("\(row.series), \(periodLabel(row.bucketStart))")
                        .accessibilityValue("\(row.count) suggestions")
                    }

                    if let row = hoveredAction {
                        RuleMark(x: .value("Selected period", periodLabel(row.bucketStart)))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, spacing: 8) {
                                hoverCard(
                                    bucket: row.bucketStart,
                                    series: row.series,
                                    count: row.count,
                                    isTokenChart: false
                                )
                            }
                    }
                }
                .chartForegroundStyleScale(
                    domain: activeSeries.isEmpty ? Self.actionOrder : activeSeries,
                    range: colors(for: activeSeries.isEmpty ? Self.actionOrder : activeSeries)
                )
                .chartYScale(domain: 0...viewModel.actionYAxisUpperBound)
                .chartXAxis {
                    AxisMarks(values: viewModel.actionDataBuckets.map(periodLabel)) { _ in
                        AxisGridLine()
                            .foregroundStyle(.separator.opacity(0.22))
                        AxisTick()
                            .foregroundStyle(.secondary)
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                            .foregroundStyle(.separator.opacity(0.22))
                        AxisValueLabel()
                    }
                }
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    actionHoverOverlay(proxy: proxy)
                }
                .frame(height: 250)
                .accessibilityLabel("Actions by type over the \(viewModel.granularity.rawValue.lowercased())")

                actionLegend
            }
        }
    }

    private var tokenVolumeChart: some View {
        DashboardCard(
            title: "Token Volume",
            subtitle: "Input and output token usage by \(periodName)"
        ) {
            if viewModel.tokenCountsBySeries.allSatisfy({ $0.count == 0 }) {
                emptyChartPlaceholder
            } else {
                Chart {
                    ForEach(viewModel.tokenStackedSeries) { row in
                        BarMark(
                            x: .value("Date", periodLabel(row.bucketStart)),
                            yStart: .value("Stack start", row.lowerBound),
                            yEnd: .value("Stack end", row.upperBound),
                            width: actionBarWidth
                        )
                        .foregroundStyle(by: .value("Direction", row.series))
                        .opacity(hoveredToken == nil || hoveredToken?.id == row.id ? 1 : 0.35)
                        .accessibilityLabel("\(row.series) tokens, \(periodLabel(row.bucketStart))")
                        .accessibilityValue("\(row.count) tokens")
                    }

                    if let row = hoveredToken {
                        RuleMark(x: .value("Selected period", periodLabel(row.bucketStart)))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, spacing: 8) {
                                hoverCard(
                                    bucket: row.bucketStart,
                                    series: row.series,
                                    count: row.count,
                                    isTokenChart: true
                                )
                            }
                    }
                }
                .chartForegroundStyleScale(domain: ["Input", "Output"], range: [Color.blue, Color.orange])
                .chartYScale(domain: 0...viewModel.tokenYAxisUpperBound)
                .chartXAxis {
                    AxisMarks(values: viewModel.tokenDataBuckets.map(periodLabel)) { _ in
                        AxisGridLine()
                            .foregroundStyle(.separator.opacity(0.22))
                        AxisTick()
                            .foregroundStyle(.secondary)
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                            .foregroundStyle(.separator.opacity(0.22))
                        AxisValueLabel(format: IntegerFormatStyle<Int>().notation(.compactName))
                    }
                }
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    tokenHoverOverlay(proxy: proxy)
                }
                .frame(height: 250)
                .accessibilityLabel("Input and output token volume over the \(viewModel.granularity.rawValue.lowercased())")

                tokenLegend
            }
        }
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No activity in this time range")
                .font(.callout.weight(.medium))
            Text("Completed suggestions will appear here automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.2))
        }
    }

    private var actionLegend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 5
        ) {
            ForEach(viewModel.activeActionSeries, id: \.self) { series in
                legendItem(series, color: color(for: series))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .topLeading)
    }

    private var tokenLegend: some View {
        HStack(spacing: 16) {
            legendItem("Input", color: .blue)
            legendItem("Output", color: .orange)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .topLeading)
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var tokenCoverageSubtitle: String {
        guard viewModel.totalActions > 0 else { return "No token usage recorded yet" }
        return "\(formattedTokenCount(viewModel.totalTokensIn)) in / \(formattedTokenCount(viewModel.totalTokensOut)) out · \(viewModel.actionsWithTokenUsage)/\(viewModel.totalActions) actions"
    }

    private var periodName: String {
        viewModel.granularity == .daily ? "day" : "week"
    }

    private func periodLabel(_ date: Date) -> String {
        let formatted = date.formatted(.dateTime.month(.abbreviated).day())
        return viewModel.granularity == .daily ? formatted : "Week of \(formatted)"
    }

    private func actionHoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else {
                            hoveredAction = nil
                            return
                        }
                        let frame = geometry[plotFrame]
                        guard frame.contains(location),
                              let label: String = proxy.value(atX: location.x - frame.minX),
                              let yValue: Double = proxy.value(atY: location.y - frame.minY),
                              let bucket = viewModel.actionDataBuckets.first(where: {
                                  periodLabel($0) == label
                              }),
                              let bucketX = proxy.position(forX: label),
                              abs(location.x - frame.minX - bucketX) <= 18
                        else {
                            hoveredAction = nil
                            return
                        }

                        hoveredAction = viewModel.actionStackedSeries.first {
                            $0.bucketStart == bucket
                                && yValue >= Double($0.lowerBound)
                                && yValue <= Double($0.upperBound)
                        }
                    case .ended:
                        hoveredAction = nil
                    }
                }
        }
    }

    private func tokenHoverOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else {
                            hoveredToken = nil
                            return
                        }
                        let frame = geometry[plotFrame]
                        guard frame.contains(location),
                              let label: String = proxy.value(atX: location.x - frame.minX),
                              let yValue: Double = proxy.value(atY: location.y - frame.minY),
                              let bucket = viewModel.tokenDataBuckets.first(where: {
                                  periodLabel($0) == label
                              }),
                              let bucketX = proxy.position(forX: label)
                        else {
                            hoveredToken = nil
                            return
                        }

                        let horizontalOffset = location.x - frame.minX - bucketX
                        hoveredToken = viewModel.tokenStackedSeries.first {
                            $0.bucketStart == bucket
                                && abs(horizontalOffset) <= 26
                                && yValue >= Double($0.lowerBound)
                                && yValue <= Double($0.upperBound)
                        }
                    case .ended:
                        hoveredToken = nil
                    }
                }
        }
    }

    private func hoverCard(
        bucket: Date,
        series: String,
        count: Int,
        isTokenChart: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(periodLabel(bucket))
                .font(.caption.weight(.semibold))

            HStack(spacing: 7) {
                Circle()
                    .fill(isTokenChart ? tokenColor(for: series) : color(for: series))
                    .frame(width: 7, height: 7)
                Text(series)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 14)
                Text(isTokenChart ? formattedTokenCount(count) : "\(count)")
                    .font(.caption.monospacedDigit().weight(.medium))
            }
            .font(.caption)
        }
        .padding(10)
        .frame(minWidth: 150)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.separator.opacity(0.5))
        }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }

    private func formattedTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func colors(for series: [String]) -> [Color] {
        series.map(color(for:))
    }

    private func color(for series: String) -> Color {
        guard let index = Self.actionOrder.firstIndex(of: series) else { return .gray }
        return Self.actionColors[index]
    }

    private func tokenColor(for series: String) -> Color {
        series == "Input" ? .blue : .orange
    }
}
