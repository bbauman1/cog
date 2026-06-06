import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int?)
    case serverError(statusCode: Int)
    case networkError(Error)
    case decodingError(Error)
    case unknown(statusCode: Int, data: Data?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized:
            return "Invalid or expired API key"
        case .forbidden:
            return "Insufficient permissions"
        case .notFound:
            return "Resource not found"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(seconds) seconds."
            }
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .unknown(let code, _):
            return "Unexpected error (\(code))"
        }
    }
}

actor DevinAPIClient {
    private let baseURL = "https://api.devin.ai/v3"
    private let session: URLSession
    private var apiKey: String
    private var orgId: String

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    init(apiKey: String, orgId: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.orgId = orgId
        self.session = session
    }

    func updateCredentials(apiKey: String, orgId: String) {
        self.apiKey = apiKey
        self.orgId = orgId
    }

    // MARK: - Generic Request

    private func request<T: Decodable & Sendable>(
        method: String = "GET",
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable)? = nil
    ) async throws -> T {
        var components = URLComponents(string: baseURL + path)
        components?.queryItems = queryItems?.isEmpty == false ? queryItems : nil

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(statusCode: 0, data: nil)
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.unknown(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Auth

    func verifySelf() async throws -> SelfResponse {
        try await request(path: "/self")
    }

    // MARK: - Sessions

    func listSessions(
        first: Int = 20,
        after: String? = nil,
        category: SessionCategory? = nil,
        origins: [SessionOrigin]? = nil,
        tags: [String]? = nil
    ) async throws -> PaginatedResponse<Session> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        if let category { queryItems.append(URLQueryItem(name: "category", value: category.rawValue)) }
        if let origins {
            for origin in origins {
                queryItems.append(URLQueryItem(name: "origins", value: origin.rawValue))
            }
        }
        if let tags {
            for tag in tags {
                queryItems.append(URLQueryItem(name: "tags", value: tag))
            }
        }

        return try await request(
            path: "/organizations/\(orgId)/sessions",
            queryItems: queryItems
        )
    }

    func getSession(devinId: String) async throws -> Session {
        try await request(path: "/organizations/\(orgId)/sessions/\(devinId)")
    }

    func createSession(prompt: String, playBookId: String? = nil, tags: [String]? = nil) async throws -> Session {
        var body: [String: Any] = ["prompt": prompt]
        if let playBookId { body["playbook_id"] = playBookId }
        if let tags { body["tags"] = tags }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        let components = URLComponents(string: baseURL + "/organizations/\(orgId)/sessions")
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown(statusCode: 0, data: nil)
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try decoder.decode(Session.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        default:
            throw APIError.unknown(statusCode: httpResponse.statusCode, data: data)
        }
    }

    func terminateSession(devinId: String) async throws {
        let _: Session = try await request(
            method: "DELETE",
            path: "/organizations/\(orgId)/sessions/\(devinId)"
        )
    }

    // MARK: - Messages

    func listMessages(
        devinId: String,
        first: Int = 50,
        after: String? = nil
    ) async throws -> PaginatedResponse<Message> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/sessions/\(devinId)/messages",
            queryItems: queryItems
        )
    }

    func sendMessage(devinId: String, message: String) async throws -> Session {
        struct MessageBody: Encodable {
            let message: String
        }
        return try await request(
            method: "POST",
            path: "/organizations/\(orgId)/sessions/\(devinId)/messages",
            body: MessageBody(message: message)
        )
    }

    // MARK: - Playbooks

    func listPlaybooks(first: Int = 50, after: String? = nil) async throws -> PaginatedResponse<Playbook> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/playbooks",
            queryItems: queryItems
        )
    }

    // MARK: - Knowledge

    func listKnowledge(first: Int = 50, after: String? = nil) async throws -> PaginatedResponse<KnowledgeNote> {
        var queryItems = [URLQueryItem(name: "first", value: "\(first)")]
        if let after { queryItems.append(URLQueryItem(name: "after", value: after)) }

        return try await request(
            path: "/organizations/\(orgId)/knowledge/notes",
            queryItems: queryItems
        )
    }
}
