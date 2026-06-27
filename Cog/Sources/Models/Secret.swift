import Foundation

enum SecretType: Codable, CaseIterable, Hashable, Sendable {
    case cookie
    case keyValue
    case totp
    case unknown

    static var allCases: [SecretType] {
        [.cookie, .keyValue, .totp]
    }

    var rawValue: String {
        switch self {
        case .cookie: return "cookie"
        case .keyValue: return "key-value"
        case .totp: return "totp"
        case .unknown: return "unknown"
        }
    }

    var displayName: String {
        switch self {
        case .cookie: return "Cookie"
        case .keyValue: return "Key-value"
        case .totp: return "TOTP"
        case .unknown: return "Unknown"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "cookie": self = .cookie
        case "key-value", "key_value", "keyvalue": self = .keyValue
        case "totp": self = .totp
        default: self = .unknown
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Secret: Codable, Identifiable, Sendable {
    let secretId: String
    let key: String
    let note: String?
    let type: SecretType?
    let createdBy: String?
    let isSensitive: Bool?
    let createdAt: Int?

    var id: String { secretId }

    var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case secretId = "secret_id"
        case key
        case note
        case type
        case createdBy = "created_by"
        case isSensitive = "is_sensitive"
        case createdAt = "created_at"
    }

    init(
        secretId: String,
        key: String,
        note: String?,
        type: SecretType?,
        createdBy: String?,
        isSensitive: Bool?,
        createdAt: Int?
    ) {
        self.secretId = secretId
        self.key = key
        self.note = note
        self.type = type
        self.createdBy = createdBy
        self.isSensitive = isSensitive
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secretId = try container.decodeIfPresent(String.self, forKey: .secretId)
            ?? container.decode(String.self, forKey: .id)
        key = try container.decodeIfPresent(String.self, forKey: .key) ?? "Unnamed Secret"
        note = try container.decodeIfPresent(String.self, forKey: .note)
        type = try container.decodeIfPresent(SecretType.self, forKey: .type)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(secretId, forKey: .secretId)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(isSensitive, forKey: .isSensitive)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}
