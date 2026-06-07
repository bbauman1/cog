import Foundation

enum DevinMode: String, Codable, CaseIterable, Sendable {
    case normal
    case fast
    case lite

    var displayName: String {
        switch self {
        case .normal: return "Agent"
        case .fast: return "Fast"
        case .lite: return "Lite"
        }
    }
}

struct Repository: Codable, Identifiable, Sendable {
    let repositoryPath: String
    let gitConnectionHost: String
    let gitConnectionId: String

    var id: String { repositoryPath }

    enum CodingKeys: String, CodingKey {
        case repositoryPath = "repo_path"
        case gitConnectionHost = "git_connection_host"
        case gitConnectionId = "git_connection_id"
    }
}

enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case new
    case claimed
    case running
    case exit
    case error
    case suspended
    case resuming
}

enum SessionStatusDetail: String, Codable, CaseIterable, Sendable {
    case working
    case waitingForUser = "waiting_for_user"
    case waitingForApproval = "waiting_for_approval"
    case finished
    case inactivity
    case userRequest = "user_request"
    case usageLimitExceeded = "usage_limit_exceeded"
    case outOfCredits = "out_of_credits"
    case outOfQuota = "out_of_quota"
    case noQuotaAllocation = "no_quota_allocation"
    case paymentDeclined = "payment_declined"
    case orgUsageLimitExceeded = "org_usage_limit_exceeded"
    case totalSessionLimitExceeded = "total_session_limit_exceeded"
    case error
}

enum SessionCategory: String, Codable, CaseIterable, Sendable {
    case bugFixing = "bug_fixing"
    case ciCdAndDevops = "ci_cd_and_devops"
    case codeQualityAndSecurity = "code_quality_and_security"
    case codeReview = "code_review"
    case codeReviewAndAnalysis = "code_review_and_analysis"
    case dataAndAutomation = "data_and_automation"
    case documentationAndContent = "documentation_and_content"
    case featureDevelopment = "feature_development"
    case migrationsAndUpgrades = "migrations_and_upgrades"
    case other
    case refactoringAndOptimization = "refactoring_and_optimization"
    case researchAndExploration = "research_and_exploration"
    case security
    case unitTestGeneration = "unit_test_generation"
}

enum SessionOrigin: String, Codable, CaseIterable, Sendable {
    case webapp
    case slack
    case teams
    case api
    case linear
    case jira
    case automation
    case cli
    case desktop
    case codeScan = "code_scan"
    case other
}

struct SessionPullRequest: Codable, Identifiable, Sendable {
    let url: String
    let state: String?

    var id: String { url }

    enum CodingKeys: String, CodingKey {
        case url = "pr_url"
        case state = "pr_state"
    }
}

struct Session: Codable, Identifiable, Sendable {
    let sessionId: String
    let status: SessionStatus
    let statusDetail: SessionStatusDetail?
    let acusConsumed: Double
    let category: SessionCategory?
    let createdAt: Int
    let origin: SessionOrigin?
    let orgId: String
    let pullRequests: [SessionPullRequest]
    let serviceUserId: String?
    let childSessionIds: [String]?
    let parentSessionId: String?
    let playBookId: String?
    let isArchived: Bool
    let url: String?
    let tags: [String]?
    let title: String?

    var id: String { sessionId }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case status
        case statusDetail = "status_detail"
        case acusConsumed = "acus_consumed"
        case category
        case createdAt = "created_at"
        case origin
        case orgId = "org_id"
        case pullRequests = "pull_requests"
        case serviceUserId = "service_user_id"
        case childSessionIds = "child_session_ids"
        case parentSessionId = "parent_session_id"
        case playBookId = "playbook_id"
        case isArchived = "is_archived"
        case url
        case tags
        case title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        status = try container.decode(SessionStatus.self, forKey: .status)
        statusDetail = try container.decodeIfPresent(SessionStatusDetail.self, forKey: .statusDetail)
        acusConsumed = try container.decode(Double.self, forKey: .acusConsumed)
        category = try container.decodeIfPresent(SessionCategory.self, forKey: .category)
        createdAt = try container.decode(Int.self, forKey: .createdAt)
        origin = try container.decodeIfPresent(SessionOrigin.self, forKey: .origin)
        orgId = try container.decode(String.self, forKey: .orgId)
        pullRequests = try container.decodeIfPresent([SessionPullRequest].self, forKey: .pullRequests) ?? []
        serviceUserId = try container.decodeIfPresent(String.self, forKey: .serviceUserId)
        childSessionIds = try container.decodeIfPresent([String].self, forKey: .childSessionIds)
        parentSessionId = try container.decodeIfPresent(String.self, forKey: .parentSessionId)
        playBookId = try container.decodeIfPresent(String.self, forKey: .playBookId)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        url = try container.decodeIfPresent(String.self, forKey: .url)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }
}
