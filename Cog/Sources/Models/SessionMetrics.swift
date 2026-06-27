import Foundation

struct SessionMetrics: Codable, Sendable {
    let sessionsCreatedCount: Int
    let mergedPrsCount: Int
    let avgAcus: Double?
    let byOrigin: [SessionMetricCount]
    let bySize: [SessionMetricCount]

    enum CodingKeys: String, CodingKey {
        case sessionsCreatedCount = "sessions_created_count"
        case mergedPrsCount = "merged_prs_count"
        case avgAcus = "avg_acus"
        case avgAcusPerSession = "avg_acus_per_session"
        case byOrigin = "by_origin"
        case sessionsByOrigin = "sessions_by_origin"
        case bySize = "by_size"
        case sessionsBySize = "sessions_by_size"
    }

    init(
        sessionsCreatedCount: Int,
        mergedPrsCount: Int,
        avgAcus: Double?,
        byOrigin: [SessionMetricCount],
        bySize: [SessionMetricCount]
    ) {
        self.sessionsCreatedCount = sessionsCreatedCount
        self.mergedPrsCount = mergedPrsCount
        self.avgAcus = avgAcus
        self.byOrigin = byOrigin
        self.bySize = bySize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionsCreatedCount = try container.decodeIfPresent(Int.self, forKey: .sessionsCreatedCount) ?? 0
        mergedPrsCount = try container.decodeIfPresent(Int.self, forKey: .mergedPrsCount) ?? 0
        avgAcus = try container.decodeIfPresent(Double.self, forKey: .avgAcus)
            ?? container.decodeIfPresent(Double.self, forKey: .avgAcusPerSession)
        byOrigin = Self.decodeCounts(from: container, primaryKey: .byOrigin, fallbackKey: .sessionsByOrigin)
        bySize = Self.decodeCounts(from: container, primaryKey: .bySize, fallbackKey: .sessionsBySize)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionsCreatedCount, forKey: .sessionsCreatedCount)
        try container.encode(mergedPrsCount, forKey: .mergedPrsCount)
        try container.encodeIfPresent(avgAcus, forKey: .avgAcus)
        try container.encode(byOrigin, forKey: .byOrigin)
        try container.encode(bySize, forKey: .bySize)
    }

    private static func decodeCounts(
        from container: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        fallbackKey: CodingKeys
    ) -> [SessionMetricCount] {
        if let values = try? container.decode([SessionMetricCount].self, forKey: primaryKey) {
            return values
        }
        if let values = try? container.decode([SessionMetricCount].self, forKey: fallbackKey) {
            return values
        }
        if let dictionary = try? container.decode([String: Int].self, forKey: primaryKey) {
            return dictionary.map { SessionMetricCount(label: $0.key, count: $0.value) }
                .sorted { $0.label < $1.label }
        }
        if let dictionary = try? container.decode([String: Int].self, forKey: fallbackKey) {
            return dictionary.map { SessionMetricCount(label: $0.key, count: $0.value) }
                .sorted { $0.label < $1.label }
        }
        return []
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
