import Foundation

struct SessionMetrics: Codable, Sendable {
    let sessionsCreatedCount: Int
    let mergedPrsCount: Int
    let avgAcus: Double?
    let byOrigin: [SessionMetricCount]
    let bySize: [SessionMetricCount]
    let sessionsCreatedWithPlaybookCount: Int
    let sessionsCreatedWithSearchCount: Int
    let sessionsWithMergedPrsCount: Int
    let sessionsWithMergedPrsBySize: [SessionMetricCount]

    enum CodingKeys: String, CodingKey {
        case sessionsCreatedCount = "sessions_created_count"
        case mergedPrsCount = "merged_prs_count"
        case sessionsWithMergedPrsCount = "sessions_with_merged_prs_count"
        case avgAcus = "avg_acus"
        case avgAcusPerSession = "avg_acus_per_session"
        case byOrigin = "by_origin"
        case sessionsByOrigin = "sessions_by_origin"
        case sessionsCreatedByOrigin = "sessions_created_by_origin"
        case bySize = "by_size"
        case sessionsBySize = "sessions_by_size"
        case sessionsCreatedBySize = "sessions_created_by_size"
        case sessionsCreatedWithPlaybookCount = "sessions_created_with_playbook_count"
        case sessionsCreatedWithSearchCount = "sessions_created_with_search_count"
        case sessionsWithMergedPrsBySize = "sessions_with_merged_prs_by_size"
    }

    init(
        sessionsCreatedCount: Int,
        mergedPrsCount: Int,
        avgAcus: Double?,
        byOrigin: [SessionMetricCount],
        bySize: [SessionMetricCount],
        sessionsCreatedWithPlaybookCount: Int = 0,
        sessionsCreatedWithSearchCount: Int = 0,
        sessionsWithMergedPrsCount: Int? = nil,
        sessionsWithMergedPrsBySize: [SessionMetricCount] = []
    ) {
        self.sessionsCreatedCount = sessionsCreatedCount
        self.mergedPrsCount = mergedPrsCount
        self.avgAcus = avgAcus
        self.byOrigin = byOrigin
        self.bySize = bySize
        self.sessionsCreatedWithPlaybookCount = sessionsCreatedWithPlaybookCount
        self.sessionsCreatedWithSearchCount = sessionsCreatedWithSearchCount
        self.sessionsWithMergedPrsCount = sessionsWithMergedPrsCount ?? mergedPrsCount
        self.sessionsWithMergedPrsBySize = sessionsWithMergedPrsBySize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currentMergedPrs = try container.decodeIfPresent(Int.self, forKey: .sessionsWithMergedPrsCount)
        let legacyMergedPrs = try container.decodeIfPresent(Int.self, forKey: .mergedPrsCount)

        sessionsCreatedCount = try container.decodeIfPresent(Int.self, forKey: .sessionsCreatedCount) ?? 0
        mergedPrsCount = legacyMergedPrs ?? currentMergedPrs ?? 0
        sessionsWithMergedPrsCount = currentMergedPrs ?? legacyMergedPrs ?? 0
        avgAcus = try container.decodeIfPresent(Double.self, forKey: .avgAcus)
            ?? container.decodeIfPresent(Double.self, forKey: .avgAcusPerSession)
        byOrigin = Self.decodeCounts(
            from: container,
            keys: [.sessionsCreatedByOrigin, .byOrigin, .sessionsByOrigin]
        )
        bySize = Self.decodeCounts(
            from: container,
            keys: [.sessionsCreatedBySize, .bySize, .sessionsBySize],
            sortOrder: Self.sizeSortOrder
        )
        sessionsCreatedWithPlaybookCount = try container.decodeIfPresent(
            Int.self,
            forKey: .sessionsCreatedWithPlaybookCount
        ) ?? 0
        sessionsCreatedWithSearchCount = try container.decodeIfPresent(
            Int.self,
            forKey: .sessionsCreatedWithSearchCount
        ) ?? 0
        sessionsWithMergedPrsBySize = Self.decodeCounts(
            from: container,
            keys: [.sessionsWithMergedPrsBySize],
            sortOrder: Self.sizeSortOrder
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionsCreatedCount, forKey: .sessionsCreatedCount)
        try container.encode(sessionsWithMergedPrsCount, forKey: .sessionsWithMergedPrsCount)
        try container.encodeIfPresent(avgAcus, forKey: .avgAcusPerSession)
        try container.encode(byOrigin, forKey: .sessionsCreatedByOrigin)
        try container.encode(bySize, forKey: .sessionsCreatedBySize)
        try container.encode(sessionsCreatedWithPlaybookCount, forKey: .sessionsCreatedWithPlaybookCount)
        try container.encode(sessionsCreatedWithSearchCount, forKey: .sessionsCreatedWithSearchCount)
        try container.encode(sessionsWithMergedPrsBySize, forKey: .sessionsWithMergedPrsBySize)
    }

    private static func decodeCounts(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys],
        sortOrder: [String]? = nil
    ) -> [SessionMetricCount] {
        for key in keys {
            if let values = try? container.decode([SessionMetricCount].self, forKey: key) {
                return Self.sortedCounts(values, sortOrder: sortOrder)
            }
            if let dictionary = try? container.decode([String: Int].self, forKey: key) {
                let values = dictionary.map { SessionMetricCount(label: $0.key, count: $0.value) }
                return Self.sortedCounts(values, sortOrder: sortOrder)
            }
        }
        return []
    }

    private static let sizeSortOrder = ["xs", "s", "m", "l", "xl"]

    private static func sortedCounts(
        _ values: [SessionMetricCount],
        sortOrder: [String]?
    ) -> [SessionMetricCount] {
        guard let sortOrder else {
            return values.sorted { $0.label < $1.label }
        }

        return values.sorted {
            let lhsIndex = sortOrder.firstIndex(of: $0.label) ?? sortOrder.count
            let rhsIndex = sortOrder.firstIndex(of: $1.label) ?? sortOrder.count
            if lhsIndex == rhsIndex {
                return $0.label < $1.label
            }
            return lhsIndex < rhsIndex
        }
    }
}

struct SessionMetricCount: Codable, Identifiable, Sendable {
    let label: String
    let count: Int

    var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label
        case count
        case origin
        case size
        case sessions
    }

    init(label: String, count: Int) {
        self.label = label
        self.count = count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decodeIfPresent(String.self, forKey: .origin)
            ?? container.decodeIfPresent(String.self, forKey: .size)
            ?? "unknown"
        count = try container.decodeIfPresent(Int.self, forKey: .count)
            ?? container.decodeIfPresent(Int.self, forKey: .sessions)
            ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(count, forKey: .count)
    }
}

struct PullRequestMetrics: Codable, Sendable {
    let createdCount: Int
    let openedCount: Int
    let mergedCount: Int
    let closedCount: Int
    let takenOverCount: Int
    let takenOverOpenedCount: Int
    let takenOverMergedCount: Int
    let takenOverClosedCount: Int

    var mergeRate: Double? {
        guard createdCount > 0 else { return nil }
        return Double(mergedCount) / Double(createdCount)
    }

    enum CodingKeys: String, CodingKey {
        case createdCount = "prs_created_count"
        case openedCount = "prs_opened_count"
        case mergedCount = "prs_merged_count"
        case closedCount = "prs_closed_count"
        case takenOverCount = "prs_taken_over_count"
        case takenOverOpenedCount = "prs_taken_over_opened_count"
        case takenOverMergedCount = "prs_taken_over_merged_count"
        case takenOverClosedCount = "prs_taken_over_closed_count"
    }

    init(
        createdCount: Int,
        openedCount: Int,
        mergedCount: Int,
        closedCount: Int,
        takenOverCount: Int = 0,
        takenOverOpenedCount: Int = 0,
        takenOverMergedCount: Int = 0,
        takenOverClosedCount: Int = 0
    ) {
        self.createdCount = createdCount
        self.openedCount = openedCount
        self.mergedCount = mergedCount
        self.closedCount = closedCount
        self.takenOverCount = takenOverCount
        self.takenOverOpenedCount = takenOverOpenedCount
        self.takenOverMergedCount = takenOverMergedCount
        self.takenOverClosedCount = takenOverClosedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdCount = try container.decodeIfPresent(Int.self, forKey: .createdCount) ?? 0
        openedCount = try container.decodeIfPresent(Int.self, forKey: .openedCount) ?? 0
        mergedCount = try container.decodeIfPresent(Int.self, forKey: .mergedCount) ?? 0
        closedCount = try container.decodeIfPresent(Int.self, forKey: .closedCount) ?? 0
        takenOverCount = try container.decodeIfPresent(Int.self, forKey: .takenOverCount) ?? 0
        takenOverOpenedCount = try container.decodeIfPresent(Int.self, forKey: .takenOverOpenedCount) ?? 0
        takenOverMergedCount = try container.decodeIfPresent(Int.self, forKey: .takenOverMergedCount) ?? 0
        takenOverClosedCount = try container.decodeIfPresent(Int.self, forKey: .takenOverClosedCount) ?? 0
    }
}

struct SearchMetrics: Codable, Sendable {
    let searchesCreatedCount: Int

    enum CodingKeys: String, CodingKey {
        case searchesCreatedCount = "searches_created_count"
    }
}

struct ConsumptionMetrics: Codable, Sendable {
    let totalAcus: Double
    let consumptionByDate: [DailyConsumption]

    enum CodingKeys: String, CodingKey {
        case totalAcus = "total_acus"
        case consumptionByDate = "consumption_by_date"
    }
}

struct DailyConsumption: Codable, Identifiable, Sendable {
    let date: Int
    let acus: Double
    let acusByProduct: ProductConsumption

    var id: Int { date }
    var day: Date { Date(timeIntervalSince1970: TimeInterval(date)) }

    enum CodingKeys: String, CodingKey {
        case date
        case acus
        case acusByProduct = "acus_by_product"
    }
}

struct ProductConsumption: Codable, Sendable {
    let devin: Double
    let cascade: Double
    let terminal: Double
    let review: Double?

    init(devin: Double, cascade: Double, terminal: Double, review: Double? = nil) {
        self.devin = devin
        self.cascade = cascade
        self.terminal = terminal
        self.review = review
    }
}

struct ActiveUserMetric: Codable, Identifiable, Sendable {
    let startTime: Int
    let endTime: Int
    let activeUsers: Int

    var id: String { "\(startTime)-\(endTime)" }
    var startDate: Date { Date(timeIntervalSince1970: TimeInterval(startTime)) }

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case activeUsers = "active_users"
    }
}

enum ActiveUserGranularity: String, CaseIterable, Sendable {
    case daily = "dau"
    case weekly = "wau"
    case monthly = "mau"

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}
