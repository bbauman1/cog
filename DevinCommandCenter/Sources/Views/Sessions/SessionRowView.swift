import SwiftUI

struct SessionRowView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
            contentSection
            Spacer()
            metadataSection
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: some View {
        Image(systemName: statusSymbol)
            .font(.title3)
            .foregroundStyle(statusColor)
            .frame(width: 28)
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? session.sessionId)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let detail = session.statusDetail {
                Text(statusLabel(for: detail))
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(timeAgo(from: session.createdDate))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(String(format: "%.1f ACU", session.acusConsumed))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSymbol: String {
        switch session.status {
        case .running:
            switch session.statusDetail {
            case .waitingForUser: return "person.fill.questionmark"
            case .waitingForApproval: return "checkmark.shield"
            default: return "play.circle.fill"
            }
        case .suspended:
            return "pause.circle.fill"
        case .exit:
            return session.statusDetail == .finished ? "checkmark.circle.fill" : "stop.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .new, .claimed:
            return "circle.dotted"
        case .resuming:
            return "arrow.clockwise.circle.fill"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running:
            switch session.statusDetail {
            case .waitingForUser, .waitingForApproval: return .orange
            default: return .blue
            }
        case .exit:
            return session.statusDetail == .finished ? .green : .secondary
        case .error:
            return .red
        case .suspended:
            return .yellow
        case .new, .claimed, .resuming:
            return .secondary
        }
    }

    private func statusLabel(for detail: SessionStatusDetail) -> String {
        switch detail {
        case .working: return "Working..."
        case .waitingForUser: return "Needs your input"
        case .waitingForApproval: return "Awaiting approval"
        case .finished: return "Completed"
        case .inactivity: return "Suspended (inactive)"
        case .userRequest: return "Paused by user"
        case .usageLimitExceeded: return "Usage limit reached"
        case .outOfCredits: return "Out of credits"
        case .outOfQuota: return "Out of quota"
        case .noQuotaAllocation: return "No quota"
        case .paymentDeclined: return "Payment declined"
        case .orgUsageLimitExceeded: return "Org limit reached"
        case .totalSessionLimitExceeded: return "Session limit reached"
        case .error: return "Error"
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
