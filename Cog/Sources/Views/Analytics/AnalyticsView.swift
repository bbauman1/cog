import Charts
import SwiftUI

struct AnalyticsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = AnalyticsViewModel()

    var body: some View {
        content
            .navigationTitle("Analytics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadMetrics() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
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
            }

            if viewModel.isLoading && viewModel.metrics == nil {
                Section {
                    ProgressView("Loading metrics...")
                        .frame(maxWidth: .infinity)
                }
            } else if let error = viewModel.errorMessage, viewModel.metrics == nil {
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
            } else if let metrics = viewModel.metrics {
                Section("Summary") {
                    AnalyticsSummaryGrid(metrics: metrics)
                }

                if !metrics.byOrigin.isEmpty {
                    Section("By Origin") {
                        metricChart(metrics.byOrigin)
                            .frame(height: 220)
                    }
                }

                if !metrics.bySize.isEmpty {
                    Section("By Size") {
                        metricChart(metrics.bySize)
                            .frame(height: 220)
                    }
                }
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

    private func metricChart(_ values: [SessionMetricCount]) -> some View {
        Chart(values) { value in
            BarMark(
                x: .value("Type", value.label),
                y: .value("Sessions", value.count)
            )
            .foregroundStyle(.blue)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

private struct AnalyticsSummaryGrid: View {
    let metrics: SessionMetrics

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                summaryItem("Sessions", "\(metrics.sessionsCreatedCount)", "rectangle.stack")
                summaryItem("Merged PRs", "\(metrics.mergedPrsCount)", "arrow.triangle.merge")
            }
            GridRow {
                summaryItem("Avg ACU", avgAcuText, "bolt")
                summaryItem("Origins", "\(metrics.byOrigin.count)", "point.3.connected.trianglepath.dotted")
            }
        }
    }

    private var avgAcuText: String {
        guard let avgAcus = metrics.avgAcus else { return "N/A" }
        return String(format: "%.1f", avgAcus)
    }

    private func summaryItem(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

