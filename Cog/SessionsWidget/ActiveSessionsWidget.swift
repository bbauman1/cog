import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

struct SessionsEntry: TimelineEntry {
    let date: Date
    let sessions: [WidgetSessionEntry]
    let totalActive: Int
    let isPlaceholder: Bool

    static var placeholder: SessionsEntry {
        SessionsEntry(
            date: .now,
            sessions: [
                WidgetSessionEntry(
                    sessionId: "placeholder-1",
                    title: "Fix login bug",
                    statusRaw: "running",
                    statusDetailRaw: "working",
                    acusConsumed: 2.5,
                    createdAt: Int(Date().timeIntervalSince1970)
                ),
                WidgetSessionEntry(
                    sessionId: "placeholder-2",
                    title: "Add dark mode",
                    statusRaw: "running",
                    statusDetailRaw: "waiting_for_user",
                    acusConsumed: 1.2,
                    createdAt: Int(Date().timeIntervalSince1970)
                ),
                WidgetSessionEntry(
                    sessionId: "placeholder-3",
                    title: "Update README",
                    statusRaw: "exit",
                    statusDetailRaw: "finished",
                    acusConsumed: 0.8,
                    createdAt: Int(Date().timeIntervalSince1970)
                ),
            ],
            totalActive: 2,
            isPlaceholder: true
        )
    }
}

// MARK: - Timeline Provider

struct SessionsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionsEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionsEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        let entry = buildEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionsEntry>) -> Void) {
        let entry = buildEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func buildEntry() -> SessionsEntry {
        guard let snapshot = WidgetDataStore.load() else {
            return SessionsEntry(date: .now, sessions: [], totalActive: 0, isPlaceholder: false)
        }
        return SessionsEntry(
            date: snapshot.updatedAt,
            sessions: snapshot.sessions,
            totalActive: snapshot.totalActive,
            isPlaceholder: false
        )
    }
}

// MARK: - Widget Definition

struct ActiveSessionsWidget: Widget {
    let kind = "ActiveSessionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SessionsTimelineProvider()) { entry in
            SessionsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Sessions")
        .description("See your Devin sessions at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Views

struct SessionsWidgetView: View {
    let entry: SessionsEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    // MARK: - Small Widget (count only)

    private var smallWidget: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("\(entry.totalActive)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text(entry.totalActive == 1 ? "Active Session" : "Active Sessions")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium Widget (top 3 sessions)

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Sessions", systemImage: "list.bullet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.totalActive) active")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if entry.sessions.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No sessions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(entry.sessions.prefix(3).enumerated()), id: \.offset) { _, session in
                    Link(destination: URL(string: "cog://session/\(session.sessionId)")!) {
                        sessionRow(session)
                    }
                }
                if entry.sessions.count > 3 {
                    Text("+\(entry.sessions.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func sessionRow(_ session: WidgetSessionEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor(for: session))
                .frame(width: 16)

            Text(session.displayTitle)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            Text(session.statusLabel)
                .font(.caption2)
                .foregroundStyle(statusColor(for: session))
        }
        .padding(.vertical, 2)
    }

    private func statusColor(for session: WidgetSessionEntry) -> Color {
        switch session.statusRaw {
        case "running":
            if session.statusDetailRaw == "waiting_for_user" ||
               session.statusDetailRaw == "waiting_for_approval" {
                return .orange
            }
            return .blue
        case "exit":
            return session.statusDetailRaw == "finished" ? .green : .secondary
        case "error":
            return .red
        case "suspended":
            return .yellow
        default:
            return .secondary
        }
    }
}

// MARK: - Preview

#Preview("Small", as: .systemSmall) {
    ActiveSessionsWidget()
} timeline: {
    SessionsEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    ActiveSessionsWidget()
} timeline: {
    SessionsEntry.placeholder
}
