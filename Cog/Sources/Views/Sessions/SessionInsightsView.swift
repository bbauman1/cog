import SwiftUI

struct SessionInsightsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: SessionInsightsViewModel

    init(sessionId: String) {
        _viewModel = State(initialValue: SessionInsightsViewModel(sessionId: sessionId))
    }

    var body: some View {
        content
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if let client = appState.apiClient {
                    viewModel.configure(with: client)
                    await viewModel.loadInsights()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.insights == nil {
            ProgressView("Loading insights...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.insights == nil {
            ContentUnavailableView {
                Label("Unable to Load Insights", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.loadInsights() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let insights = viewModel.insights, insights.hasAnalysis {
            insightsList(insights)
        } else {
            ContentUnavailableView {
                Label("No Insights Yet", systemImage: "sparkles")
            } description: {
                Text("Generate an analysis for this session when Devin has enough activity to review.")
            } actions: {
                Button(viewModel.isGenerating ? "Generating..." : "Generate Insights") {
                    Task { await viewModel.generateInsights() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating)
            }
        }
    }

    private func insightsList(_ insights: SessionInsights) -> some View {
        List {
            Section("Overview") {
                if let sessionSize = insights.sessionSize {
                    LabeledContent("Session Size", value: sessionSize.uppercased())
                }
                if let numMessages = insights.numMessages {
                    LabeledContent("Messages", value: "\(numMessages)")
                }
                if let summary = insights.analysis?.summary, !summary.isEmpty {
                    Text(summary)
                }
            }

            if let timeline = insights.analysis?.timeline, !timeline.isEmpty {
                Section("Timeline") {
                    ForEach(timeline) { item in
                        InsightsTimelineRow(item: item)
                    }
                }
            }

            if let issues = insights.analysis?.issues, !issues.isEmpty {
                Section("Issues") {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.title)
                                .font(.subheadline.weight(.medium))
                            if let description = issue.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let impact = issue.impact, !impact.isEmpty {
                                Label(impact, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            if let actionItems = insights.analysis?.actionItems, !actionItems.isEmpty {
                Section("Action Items") {
                    ForEach(actionItems) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if let status = item.status, !status.isEmpty {
                                    Text(status)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5), in: Capsule())
                                }
                            }
                            if let description = item.description, !description.isEmpty {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let suggestedPrompt = insights.analysis?.suggestedPrompt,
               !suggestedPrompt.suggested.isEmpty {
                Section("Suggested Prompt") {
                    if let original = suggestedPrompt.original, !original.isEmpty {
                        PromptDiffBlock(title: "Original", text: original, color: .red)
                    }
                    PromptDiffBlock(title: "Suggested", text: suggestedPrompt.suggested, color: .green)
                    if let explanation = suggestedPrompt.explanation, !explanation.isEmpty {
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let noteUsage = insights.analysis?.noteUsage, !noteUsage.isEmpty {
                Section("Knowledge Notes") {
                    ForEach(noteUsage) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.noteName)
                                .font(.subheadline.weight(.medium))
                            if let feedback = note.feedback, !feedback.isEmpty {
                                Text(feedback)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button(viewModel.isGenerating ? "Generating..." : "Regenerate Insights") {
                    Task { await viewModel.generateInsights() }
                }
                .disabled(viewModel.isGenerating)
            }
        }
        .refreshable {
            await viewModel.loadInsights()
        }
    }
}

private struct InsightsTimelineRow: View {
    let item: InsightsTimeline

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 1)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if let timestamp = item.timestamp, !timestamp.isEmpty {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PromptDiffBlock: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
