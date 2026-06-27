import Charts
import SwiftUI

struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AnalyticsViewModel()

    var body: some View {
        content
            .navigationTitle("Analytics")
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadMetrics()
                }
            }
            .onChange(of: viewModel.selectedRange) {
                Task { await viewModel.loadMetrics() }
            }
    }

    @ViewBuilder
    private var content: some View {
        List {
            Section {
                Picker("Range", selection: Bindable(viewModel).selectedRange) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if viewModel.isLoading && viewModel.dashboard == nil {
                Section {
                    ProgressView("Loading metrics...")
                        .frame(maxWidth: .infinity)
                }
            } else if let error = viewModel.errorMessage, viewModel.dashboard == nil {
                Section {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await viewModel.loadMetrics() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if let dashboard = viewModel.dashboard {
                dashboardSections(dashboard)
            } else {
                Section {
                    ContentUnavailableView(
                        "No Metrics",
                        systemImage: "chart.bar",
                        description: Text("No analytics data is available for this range.")
                    )
                }
            }
        }
        .refreshable {
            await viewModel.loadMetrics()
        }
    }

    @ViewBuilder
    private func dashboardSections(_ dashboard: AnalyticsDashboardData) -> some View {
        Section("Summary") {
            AnalyticsSummaryGrid(dashboard: dashboard)
        }

        if !viewModel.warningMessages.isEmpty {
            Section("Unavailable") {
                Label("Some analytics sources could not be loaded", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                ForEach(viewModel.warningMessages, id: \.self) { warning in
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if let consumption = dashboard.consumption,
           !consumption.consumptionByDate.isEmpty {
            Section("ACU Trend") {
                consumptionChart(consumption)
                    .frame(height: 240)
                LabeledContent("Total ACU", value: decimalText(consumption.totalAcus))
            }
        }

        if let metrics = dashboard.pullRequestMetrics {
            Section("PR Funnel") {
                prFunnelChart(metrics)
                    .frame(height: 210)
                LabeledContent("Merge Rate", value: percentageText(metrics.mergeRate))
                if metrics.takenOverCount > 0 {
                    LabeledContent("Taken Over", value: "\(metrics.takenOverCount)")
                }
            }
        }

        if let metrics = dashboard.sessionMetrics {
            let values = adoptionValues(metrics)
            if !values.isEmpty {
                Section("Playbook & Search Adoption") {
                    adoptionChart(values)
                        .frame(height: 160)
                    LabeledContent(
                        "Playbook Sessions",
                        value: "\(metrics.sessionsCreatedWithPlaybookCount) / \(metrics.sessionsCreatedCount)"
                    )
                    LabeledContent(
                        "Search Sessions",
                        value: "\(metrics.sessionsCreatedWithSearchCount) / \(metrics.sessionsCreatedCount)"
                    )
                }
            }
        }

        if !dashboard.activeUsers.isEmpty {
            Section("\(viewModel.selectedRange.activeUserGranularity.displayName) Active Users") {
                activeUsersChart(dashboard.activeUsers)
                    .frame(height: 220)
            }
        }

        if let metrics = dashboard.sessionMetrics {
            if !metrics.byOrigin.isEmpty {
                Section("Sessions by Origin") {
                    countChart(metrics.byOrigin)
                        .frame(height: chartHeight(for: metrics.byOrigin))
                }
            }

            if !metrics.bySize.isEmpty {
                Section("Sessions by Size") {
                    countChart(metrics.bySize)
                        .frame(height: chartHeight(for: metrics.bySize))
                }
            }

            if !metrics.sessionsWithMergedPrsBySize.isEmpty {
                Section("Merged PR Sessions by Size") {
                    countChart(metrics.sessionsWithMergedPrsBySize)
                        .frame(height: chartHeight(for: metrics.sessionsWithMergedPrsBySize))
                }
            }
        }

        if let searchMetrics = dashboard.searchMetrics {
            Section("Search") {
                LabeledContent("Searches Created", value: "\(searchMetrics.searchesCreatedCount)")
            }
        }
    }

    private func consumptionChart(_ consumption: ConsumptionMetrics) -> some View {
        let values = consumptionProductValues(consumption)

        return Chart(values) { value in
            BarMark(
                x: .value("Date", value.date, unit: .day),
                y: .value("ACU", value.acus)
            )
            .foregroundStyle(by: .value("Product", value.product))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .chartLegend(position: .bottom, alignment: .leading)
    }

    private func prFunnelChart(_ metrics: PullRequestMetrics) -> some View {
        Chart(prFunnelValues(metrics)) { value in
            BarMark(
                x: .value("PRs", value.count),
                y: .value("State", value.label)
            )
            .foregroundStyle(by: .value("State", value.label))
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartLegend(.hidden)
    }

    private func adoptionChart(_ values: [SegmentedMetricValue]) -> some View {
        Chart(values) { value in
            BarMark(
                x: .value("Sessions", value.count),
                y: .value("Signal", value.label)
            )
            .foregroundStyle(by: .value("Segment", value.segment))
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartLegend(position: .bottom, alignment: .leading)
    }

    private func activeUsersChart(_ values: [ActiveUserMetric]) -> some View {
        Chart(values) { value in
            LineMark(
                x: .value("Date", value.startDate),
                y: .value("Active Users", value.activeUsers)
            )
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Date", value.startDate),
                y: .value("Active Users", value.activeUsers)
            )
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
    }

    private func countChart(_ values: [SessionMetricCount]) -> some View {
        Chart(values) { value in
            BarMark(
                x: .value("Sessions", value.count),
                y: .value("Type", displayLabel(value.label))
            )
            .foregroundStyle(.blue)
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
    }

    private func chartHeight(for values: [SessionMetricCount]) -> CGFloat {
        CGFloat(max(160, values.count * 34))
    }

    private func adoptionValues(_ metrics: SessionMetrics) -> [SegmentedMetricValue] {
        guard metrics.sessionsCreatedCount > 0 else { return [] }

        let playbookCount = metrics.sessionsCreatedWithPlaybookCount
        let searchCount = metrics.sessionsCreatedWithSearchCount

        return [
            SegmentedMetricValue(
                label: "Playbook",
                segment: "With",
                count: playbookCount
            ),
            SegmentedMetricValue(
                label: "Playbook",
                segment: "Without",
                count: max(metrics.sessionsCreatedCount - playbookCount, 0)
            ),
            SegmentedMetricValue(
                label: "Search",
                segment: "With",
                count: searchCount
            ),
            SegmentedMetricValue(
                label: "Search",
                segment: "Without",
                count: max(metrics.sessionsCreatedCount - searchCount, 0)
            )
        ]
    }

    private func prFunnelValues(_ metrics: PullRequestMetrics) -> [CountMetricValue] {
        [
            CountMetricValue(label: "Created", count: metrics.createdCount),
            CountMetricValue(label: "Open", count: metrics.openedCount),
            CountMetricValue(label: "Merged", count: metrics.mergedCount),
            CountMetricValue(label: "Closed", count: metrics.closedCount)
        ]
    }

    private func consumptionProductValues(_ consumption: ConsumptionMetrics) -> [ConsumptionProductValue] {
        consumption.consumptionByDate.flatMap { day in
            [
                ConsumptionProductValue(date: day.day, product: "Devin", acus: day.acusByProduct.devin),
                ConsumptionProductValue(date: day.day, product: "Cascade", acus: day.acusByProduct.cascade),
                ConsumptionProductValue(date: day.day, product: "Terminal", acus: day.acusByProduct.terminal),
                ConsumptionProductValue(date: day.day, product: "Review", acus: day.acusByProduct.review ?? 0)
            ].filter { $0.acus > 0 }
        }
    }

    private func decimalText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.0f%%", value * 100)
    }

    private func displayLabel(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

private struct AnalyticsSummaryGrid: View {
    let dashboard: AnalyticsDashboardData

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                summaryItem("Sessions", sessionCountText, "rectangle.stack")
                summaryItem("Merged PRs", mergedPrsText, "arrow.triangle.merge")
            }
            GridRow {
                summaryItem("Avg ACU", avgAcuText, "bolt")
                summaryItem("Total ACU", totalAcuText, "chart.line.uptrend.xyaxis")
            }
            GridRow {
                summaryItem("Searches", searchesText, "magnifyingglass")
                summaryItem("Active Users", activeUsersText, "person.2")
            }
        }
    }

    private var sessionCountText: String {
        intText(dashboard.sessionMetrics?.sessionsCreatedCount)
    }

    private var mergedPrsText: String {
        if let pullRequestMetrics = dashboard.pullRequestMetrics {
            return "\(pullRequestMetrics.mergedCount)"
        }
        return intText(dashboard.sessionMetrics?.sessionsWithMergedPrsCount)
    }

    private var avgAcuText: String {
        guard let avgAcus = dashboard.sessionMetrics?.avgAcus else { return "N/A" }
        return String(format: "%.1f", avgAcus)
    }

    private var totalAcuText: String {
        guard let totalAcus = dashboard.consumption?.totalAcus else { return "N/A" }
        return String(format: "%.1f", totalAcus)
    }

    private var searchesText: String {
        if let searchMetrics = dashboard.searchMetrics {
            return "\(searchMetrics.searchesCreatedCount)"
        }
        return intText(dashboard.sessionMetrics?.sessionsCreatedWithSearchCount)
    }

    private var activeUsersText: String {
        guard let activeUsers = dashboard.activeUsers.last?.activeUsers else { return "N/A" }
        return "\(activeUsers)"
    }

    private func intText(_ value: Int?) -> String {
        guard let value else { return "N/A" }
        return "\(value)"
    }

    private func summaryItem(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct CountMetricValue: Identifiable {
    let label: String
    let count: Int

    var id: String { label }
}

private struct SegmentedMetricValue: Identifiable {
    let label: String
    let segment: String
    let count: Int

    var id: String { "\(label)-\(segment)" }
}

private struct ConsumptionProductValue: Identifiable {
    let date: Date
    let product: String
    let acus: Double

    var id: String { "\(Int(date.timeIntervalSince1970))-\(product)" }
}
