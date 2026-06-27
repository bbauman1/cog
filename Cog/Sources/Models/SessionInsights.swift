import Foundation

struct SessionInsights: Codable, Sendable {
    let analysis: InsightsAnalysis?
    let sessionSize: String?
    let numMessages: Int?
    let generatedAt: Int?

    var hasAnalysis: Bool {
        analysis != nil
    }

    enum CodingKeys: String, CodingKey {
        case analysis
        case sessionSize = "session_size"
        case numMessages = "num_messages"
        case generatedAt = "generated_at"
    }
}

struct InsightsAnalysis: Codable, Sendable {
    let summary: String?
    let timeline: [InsightsTimeline]
    let issues: [InsightsIssue]
    let actionItems: [InsightsActionItem]
    let suggestedPrompt: InsightsSuggestedPrompt?
    let noteUsage: [InsightsNoteUsage]

    enum CodingKeys: String, CodingKey {
        case summary
        case timeline
        case issues
        case actionItems = "action_items"
        case suggestedPrompt = "suggested_prompt"
        case noteUsage = "note_usage"
    }

    init(
        summary: String?,
        timeline: [InsightsTimeline],
        issues: [InsightsIssue],
        actionItems: [InsightsActionItem],
        suggestedPrompt: InsightsSuggestedPrompt?,
        noteUsage: [InsightsNoteUsage]
    ) {
        self.summary = summary
        self.timeline = timeline
        self.issues = issues
        self.actionItems = actionItems
        self.suggestedPrompt = suggestedPrompt
        self.noteUsage = noteUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        timeline = Self.decodeTimeline(from: container)
        issues = Self.decodeIssues(from: container)
        actionItems = Self.decodeActionItems(from: container)
        suggestedPrompt = try? container.decodeIfPresent(InsightsSuggestedPrompt.self, forKey: .suggestedPrompt)
        noteUsage = Self.decodeNoteUsage(from: container)
    }

    private static func decodeTimeline(from container: KeyedDecodingContainer<CodingKeys>) -> [InsightsTimeline] {
        if let items = try? container.decode([InsightsTimeline].self, forKey: .timeline) {
            return items
        }
        if let strings = try? container.decode([String].self, forKey: .timeline) {
            return strings.map { InsightsTimeline(title: $0, description: nil, timestamp: nil) }
        }
        return []
    }

    private static func decodeIssues(from container: KeyedDecodingContainer<CodingKeys>) -> [InsightsIssue] {
        if let items = try? container.decode([InsightsIssue].self, forKey: .issues) {
            return items
        }
        if let strings = try? container.decode([String].self, forKey: .issues) {
            return strings.map { InsightsIssue(title: $0, description: nil, impact: nil) }
        }
        return []
    }

    private static func decodeActionItems(from container: KeyedDecodingContainer<CodingKeys>) -> [InsightsActionItem] {
        if let items = try? container.decode([InsightsActionItem].self, forKey: .actionItems) {
            return items
        }
        if let strings = try? container.decode([String].self, forKey: .actionItems) {
            return strings.map { InsightsActionItem(title: $0, description: nil, status: nil) }
        }
        return []
    }

    private static func decodeNoteUsage(from container: KeyedDecodingContainer<CodingKeys>) -> [InsightsNoteUsage] {
        if let items = try? container.decode([InsightsNoteUsage].self, forKey: .noteUsage) {
            return items
        }
        if let strings = try? container.decode([String].self, forKey: .noteUsage) {
            return strings.map { InsightsNoteUsage(noteName: $0, feedback: nil) }
        }
        return []
    }
}

struct InsightsTimeline: Codable, Identifiable, Sendable {
    let title: String
    let description: String?
    let timestamp: String?

    var id: String {
        [timestamp, title, description].compactMap { $0 }.joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case event
        case summary
        case timestamp
        case time
    }

    init(title: String, description: String?, timestamp: String?) {
        self.title = title
        self.description = description
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            title = value
            description = nil
            timestamp = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .event)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? "Timeline Event"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
            ?? container.decodeIfPresent(String.self, forKey: .time)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
    }
}

struct InsightsIssue: Codable, Identifiable, Sendable {
    let title: String
    let description: String?
    let impact: String?

    var id: String {
        [title, description, impact].compactMap { $0 }.joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case issue
        case impact
    }

    init(title: String, description: String?, impact: String?) {
        self.title = title
        self.description = description
        self.impact = impact
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            title = value
            description = nil
            impact = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .issue)
            ?? "Issue"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        impact = try container.decodeIfPresent(String.self, forKey: .impact)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(impact, forKey: .impact)
    }
}

struct InsightsActionItem: Codable, Identifiable, Sendable {
    let title: String
    let description: String?
    let status: String?

    var id: String {
        [title, description, status].compactMap { $0 }.joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case action
        case status
    }

    init(title: String, description: String?, status: String?) {
        self.title = title
        self.description = description
        self.status = status
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            title = value
            description = nil
            status = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .action)
            ?? "Action Item"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
    }
}

struct InsightsSuggestedPrompt: Codable, Sendable {
    let original: String?
    let suggested: String
    let explanation: String?

    enum CodingKeys: String, CodingKey {
        case original
        case suggested
        case prompt
        case explanation
    }

    init(original: String?, suggested: String, explanation: String?) {
        self.original = original
        self.suggested = suggested
        self.explanation = explanation
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            original = nil
            suggested = value
            explanation = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        original = try container.decodeIfPresent(String.self, forKey: .original)
        suggested = try container.decodeIfPresent(String.self, forKey: .suggested)
            ?? container.decodeIfPresent(String.self, forKey: .prompt)
            ?? ""
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(original, forKey: .original)
        try container.encode(suggested, forKey: .suggested)
        try container.encodeIfPresent(explanation, forKey: .explanation)
    }
}

struct InsightsNoteUsage: Codable, Identifiable, Sendable {
    let noteName: String
    let feedback: String?

    var id: String {
        [noteName, feedback].compactMap { $0 }.joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case noteName = "note_name"
        case name
        case feedback
    }

    init(noteName: String, feedback: String?) {
        self.noteName = noteName
        self.feedback = feedback
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let value = try? container.decode(String.self) {
            noteName = value
            feedback = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        noteName = try container.decodeIfPresent(String.self, forKey: .noteName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? "Knowledge Note"
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(noteName, forKey: .noteName)
        try container.encodeIfPresent(feedback, forKey: .feedback)
    }
}
