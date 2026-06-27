import Foundation

struct ScheduleListResponse: Codable, Sendable {
    let items: [Schedule]
    let hasNextPage: Bool
    let endCursor: String?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case items
        case schedules
        case hasNextPage = "has_next_page"
        case endCursor = "end_cursor"
        case total
    }

    init(items: [Schedule], hasNextPage: Bool = false, endCursor: String? = nil, total: Int? = nil) {
        self.items = items
        self.hasNextPage = hasNextPage
        self.endCursor = endCursor
        self.total = total
    }

    init(from decoder: Decoder) throws {
        if var container = try? decoder.unkeyedContainer() {
            var decodedItems: [Schedule] = []
            while !container.isAtEnd {
                decodedItems.append(try container.decode(Schedule.self))
            }
            items = decodedItems
            hasNextPage = false
            endCursor = nil
            total = decodedItems.count
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Schedule].self, forKey: .items)
            ?? container.decodeIfPresent([Schedule].self, forKey: .schedules)
            ?? []
        hasNextPage = try container.decodeIfPresent(Bool.self, forKey: .hasNextPage) ?? false
        endCursor = try container.decodeIfPresent(String.self, forKey: .endCursor)
        total = try container.decodeIfPresent(Int.self, forKey: .total)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(hasNextPage, forKey: .hasNextPage)
        try container.encodeIfPresent(endCursor, forKey: .endCursor)
        try container.encodeIfPresent(total, forKey: .total)
    }
}

enum ScheduleFrequency: Codable, CaseIterable, Hashable, Sendable {
    case hourly
    case daily
    case weekly
    case unknown

    static var allCases: [ScheduleFrequency] {
        [.hourly, .daily, .weekly]
    }

    var rawValue: String {
        switch self {
        case .hourly: return "hourly"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .unknown: return "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        default: return rawValue.capitalized
        }
    }

    func cronExpression(for date: Date, calendar: Calendar = .current) -> String? {
        guard self != .unknown else { return nil }
        let minute = calendar.component(.minute, from: date)
        let hour = calendar.component(.hour, from: date)

        switch self {
        case .hourly:
            return "\(minute) * * * *"
        case .daily:
            return "\(minute) \(hour) * * *"
        case .weekly:
            let weekday = calendar.component(.weekday, from: date) - 1
            return "\(minute) \(hour) * * \(weekday)"
        case .unknown:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "hourly": self = .hourly
        case "daily": self = .daily
        case "weekly": self = .weekly
        default:
            self = Self.frequency(fromCronExpression: value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func frequency(fromCronExpression value: String) -> ScheduleFrequency {
        let parts = value.split(separator: " ")
        guard parts.count == 5 || parts.count == 6 || parts.count == 7 else {
            return .unknown
        }
        if parts[1] == "*" {
            return .hourly
        }
        if parts[4] != "*" {
            return .weekly
        }
        return .daily
    }
}

enum ScheduleType: Codable, CaseIterable, Hashable, Sendable {
    case recurring
    case oneTime
    case unknown

    static var allCases: [ScheduleType] {
        [.recurring, .oneTime]
    }

    var rawValue: String {
        switch self {
        case .recurring: return "recurring"
        case .oneTime: return "one_time"
        case .unknown: return "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .recurring: return "Recurring"
        case .oneTime: return "One-time"
        case .unknown: return "Unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "recurring": self = .recurring
        case "one_time", "one-time": self = .oneTime
        default: self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ScheduleAgent: Codable, CaseIterable, Hashable, Sendable {
    case devin
    case dataAnalyst
    case unknown

    static var allCases: [ScheduleAgent] {
        [.devin, .dataAnalyst]
    }

    var rawValue: String {
        switch self {
        case .devin: return "devin"
        case .dataAnalyst: return "data_analyst"
        case .unknown: return "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .devin: return "Devin"
        case .dataAnalyst: return "Data Analyst"
        case .unknown: return "Unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "devin": self = .devin
        case "data_analyst", "data-analyst": self = .dataAnalyst
        default: self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Schedule: Codable, Identifiable, Sendable {
    let scheduleId: String
    let name: String
    let prompt: String?
    let frequency: ScheduleFrequency?
    let scheduleType: ScheduleType?
    let agent: ScheduleAgent?
    let bypassApproval: Bool?
    let playbookId: String?
    let tags: [String]?
    let notifyOn: String?
    let scheduledAt: String?
    let enabled: Bool
    let lastExecutedAt: String?
    let error: String?

    var id: String { scheduleId }

    enum CodingKeys: String, CodingKey {
        case id
        case scheduleId = "schedule_id"
        case scheduledSessionId = "scheduled_session_id"
        case name
        case prompt
        case frequency
        case scheduleType = "schedule_type"
        case agent
        case bypassApproval = "bypass_approval"
        case playbookId = "playbook_id"
        case tags
        case notifyOn = "notify_on"
        case scheduledAt = "scheduled_at"
        case enabled
        case isEnabled = "is_enabled"
        case lastExecutedAt = "last_executed_at"
        case error
        case lastErrorMessage = "last_error_message"
    }

    init(
        scheduleId: String,
        name: String,
        prompt: String?,
        frequency: ScheduleFrequency?,
        scheduleType: ScheduleType?,
        agent: ScheduleAgent?,
        bypassApproval: Bool?,
        playbookId: String?,
        tags: [String]?,
        notifyOn: String?,
        scheduledAt: String?,
        enabled: Bool,
        lastExecutedAt: String?,
        error: String?
    ) {
        self.scheduleId = scheduleId
        self.name = name
        self.prompt = prompt
        self.frequency = frequency
        self.scheduleType = scheduleType
        self.agent = agent
        self.bypassApproval = bypassApproval
        self.playbookId = playbookId
        self.tags = tags
        self.notifyOn = notifyOn
        self.scheduledAt = scheduledAt
        self.enabled = enabled
        self.lastExecutedAt = lastExecutedAt
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheduleId = try container.decodeIfPresent(String.self, forKey: .scheduleId)
            ?? container.decodeIfPresent(String.self, forKey: .scheduledSessionId)
            ?? container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Automation"
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        frequency = try container.decodeIfPresent(ScheduleFrequency.self, forKey: .frequency)
        scheduleType = try container.decodeIfPresent(ScheduleType.self, forKey: .scheduleType)
        agent = try container.decodeIfPresent(ScheduleAgent.self, forKey: .agent)
        bypassApproval = try container.decodeIfPresent(Bool.self, forKey: .bypassApproval)
        playbookId = try container.decodeIfPresent(String.self, forKey: .playbookId)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        notifyOn = try container.decodeIfPresent(String.self, forKey: .notifyOn)
        scheduledAt = try container.decodeIfPresent(String.self, forKey: .scheduledAt)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .isEnabled)
            ?? true
        lastExecutedAt = try container.decodeIfPresent(String.self, forKey: .lastExecutedAt)
        error = try container.decodeIfPresent(String.self, forKey: .error)
            ?? container.decodeIfPresent(String.self, forKey: .lastErrorMessage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scheduleId, forKey: .scheduleId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(frequency, forKey: .frequency)
        try container.encodeIfPresent(scheduleType, forKey: .scheduleType)
        try container.encodeIfPresent(agent, forKey: .agent)
        try container.encodeIfPresent(bypassApproval, forKey: .bypassApproval)
        try container.encodeIfPresent(playbookId, forKey: .playbookId)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(notifyOn, forKey: .notifyOn)
        try container.encodeIfPresent(scheduledAt, forKey: .scheduledAt)
        try container.encode(enabled, forKey: .enabled)
        try container.encodeIfPresent(lastExecutedAt, forKey: .lastExecutedAt)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

struct ScheduleMutation: Encodable, Sendable {
    let name: String?
    let prompt: String?
    let frequency: String?
    let scheduleType: ScheduleType?
    let agent: ScheduleAgent?
    let bypassApproval: Bool?
    let playbookId: String?
    let tags: [String]?
    let notifyOn: String?
    let scheduledAt: String?
    let enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case prompt
        case frequency
        case scheduleType = "schedule_type"
        case agent
        case bypassApproval = "bypass_approval"
        case playbookId = "playbook_id"
        case tags
        case notifyOn = "notify_on"
        case scheduledAt = "scheduled_at"
        case enabled
    }
}
