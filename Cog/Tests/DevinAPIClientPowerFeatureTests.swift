import Foundation
import XCTest
@testable import Cog

final class DevinAPIClientPowerFeatureTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSessionInsightsFixtureDecodes() throws {
        let insights = try JSONDecoder().decode(SessionInsights.self, from: Data(insightsJSON.utf8))

        XCTAssertEqual(insights.sessionSize, "m")
        XCTAssertEqual(insights.numMessages, 42)
        XCTAssertEqual(insights.analysis?.timeline.first?.title, "Started investigation")
        XCTAssertEqual(insights.analysis?.issues.first?.impact, "Delayed completion")
        XCTAssertEqual(insights.analysis?.actionItems.first?.title, "Add tests")
        XCTAssertEqual(insights.analysis?.suggestedPrompt?.suggested, "Please include reproduction steps.")
    }

    func testMetricsFixtureDecodesDictionaries() throws {
        let metrics = try JSONDecoder().decode(SessionMetrics.self, from: Data(metricsJSON.utf8))

        XCTAssertEqual(metrics.sessionsCreatedCount, 12)
        XCTAssertEqual(metrics.mergedPrsCount, 5)
        XCTAssertEqual(metrics.avgAcus, 3.4)
        XCTAssertEqual(metrics.byOrigin.first { $0.label == "api" }?.count, 4)
        XCTAssertEqual(metrics.bySize.first { $0.label == "m" }?.count, 6)
    }

    func testScheduleListFixtureDecodes() throws {
        let response = try JSONDecoder().decode(ScheduleListResponse.self, from: Data(scheduleListJSON.utf8))

        XCTAssertEqual(response.items.first?.scheduleId, "schedule-1")
        XCTAssertEqual(response.items.first?.frequency, .daily)
        XCTAssertEqual(response.items.first?.enabled, true)
    }

    func testLiveScheduleListFixtureDecodesScheduledSessionId() throws {
        let response = try JSONDecoder().decode(ScheduleListResponse.self, from: Data(liveScheduleListJSON.utf8))

        XCTAssertEqual(response.items.first?.scheduleId, "sched-1")
        XCTAssertEqual(response.items.first?.frequency, .daily)
        XCTAssertEqual(response.items.first?.notifyOn, "always")
        XCTAssertNil(response.items.first?.error)
    }

    func testSecretFixtureDecodes() throws {
        let response = try JSONDecoder().decode(PaginatedResponse<Secret>.self, from: Data(secretListJSON.utf8))

        XCTAssertEqual(response.items.first?.secretId, "secret-1")
        XCTAssertEqual(response.items.first?.type, .keyValue)
        XCTAssertEqual(response.items.first?.isSensitive, true)
    }

    func testGetAndGenerateSessionInsightsRequests() async throws {
        var requestIndex = 0
        let client = p1MakeClient { request in
            requestIndex += 1
            if requestIndex == 1 {
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/sessions/devin-1/insights")
                return p1JSONResponse(for: request, body: insightsJSON)
            }

            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/sessions/devin-1/insights/generate")
            return p1JSONResponse(for: request, statusCode: 204, body: "")
        }

        _ = try await client.getSessionInsights(devinId: "devin-1")
        try await client.generateSessionInsights(devinId: "devin-1")
        XCTAssertEqual(requestIndex, 2)
    }

    func testGetSessionMetricsSendsDateQuery() async throws {
        let client = p1MakeClient { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/metrics/sessions")

            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let queryNames = Set((components.queryItems ?? []).map(\.name))
            XCTAssertTrue(queryNames.contains("time_after"))
            XCTAssertTrue(queryNames.contains("time_before"))

            return p1JSONResponse(for: request, body: metricsJSON)
        }

        _ = try await client.getSessionMetrics(
            timeAfter: Date(timeIntervalSince1970: 1780000000),
            timeBefore: Date(timeIntervalSince1970: 1782572400)
        )
    }

    func testScheduleCRUDRequests() async throws {
        var requestIndex = 0
        let client = p1MakeClient { request in
            requestIndex += 1

            switch requestIndex {
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/schedules")
                return p1JSONResponse(for: request, body: scheduleListJSON)
            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/schedules")
                let body = try p1RequestJSONBody(request)
                XCTAssertEqual(body["name"] as? String, "Daily review")
                XCTAssertEqual(body["frequency"] as? String, "0 13 * * *")
                XCTAssertEqual(body["schedule_type"] as? String, "recurring")
                XCTAssertEqual(body["agent"] as? String, "devin")
                return p1JSONResponse(for: request, body: scheduleJSON)
            case 3:
                XCTAssertEqual(request.httpMethod, "PATCH")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/schedules/schedule-1")
                let body = try p1RequestJSONBody(request)
                XCTAssertEqual(body["enabled"] as? Bool, false)
                return p1JSONResponse(for: request, body: disabledScheduleJSON)
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/schedules/schedule-1")
                return p1JSONResponse(for: request, statusCode: 204, body: "")
            }
        }

        _ = try await client.listSchedules()
        _ = try await client.createSchedule(scheduleMutation(enabled: true))
        _ = try await client.updateSchedule(
            scheduleId: "schedule-1",
            mutation: ScheduleMutation(
                name: nil,
                prompt: nil,
                frequency: nil,
                scheduleType: nil,
                agent: nil,
                bypassApproval: nil,
                playbookId: nil,
                tags: nil,
                notifyOn: nil,
                scheduledAt: nil,
                enabled: false
            )
        )
        try await client.deleteSchedule(scheduleId: "schedule-1")
        XCTAssertEqual(requestIndex, 4)
    }

    func testSecretCRUDRequests() async throws {
        var requestIndex = 0
        let client = p1MakeClient { request in
            requestIndex += 1

            switch requestIndex {
            case 1:
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/secrets")
                return p1JSONResponse(for: request, body: secretListJSON)
            case 2:
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/secrets")
                let body = try p1RequestJSONBody(request)
                XCTAssertEqual(body["key"] as? String, "API_TOKEN")
                XCTAssertEqual(body["value"] as? String, "secret-value")
                XCTAssertEqual(body["type"] as? String, "key-value")
                XCTAssertEqual(body["is_sensitive"] as? Bool, true)
                return p1JSONResponse(for: request, body: secretJSON)
            default:
                XCTAssertEqual(request.httpMethod, "DELETE")
                XCTAssertEqual(request.url?.path, "/v3/organizations/org-test/secrets/secret-1")
                return p1JSONResponse(for: request, statusCode: 204, body: "")
            }
        }

        _ = try await client.listSecrets()
        _ = try await client.createSecret(
            key: "API_TOKEN",
            value: "secret-value",
            type: .keyValue,
            isSensitive: true,
            note: "Used by CI"
        )
        try await client.deleteSecret(secretId: "secret-1")
        XCTAssertEqual(requestIndex, 3)
    }
}

private let insightsJSON = """
{
  "session_size": "m",
  "num_messages": 42,
  "generated_at": 1782572400,
  "analysis": {
    "summary": "Devin investigated the issue and opened a PR.",
    "timeline": [
      {"title": "Started investigation", "description": "Read logs", "timestamp": "09:00"}
    ],
    "issues": [
      {"title": "Flaky test", "description": "One test failed intermittently.", "impact": "Delayed completion"}
    ],
    "action_items": [
      {"title": "Add tests", "description": "Cover the regression.", "status": "open"}
    ],
    "suggested_prompt": {
      "original": "Fix this",
      "suggested": "Please include reproduction steps.",
      "explanation": "Specific context helps Devin start faster."
    },
    "note_usage": ["Repo setup note"]
  }
}
"""

private let metricsJSON = """
{
  "sessions_created_count": 12,
  "merged_prs_count": 5,
  "avg_acus": 3.4,
  "by_origin": {
    "api": 4,
    "webapp": 8
  },
  "by_size": {
    "s": 6,
    "m": 6
  }
}
"""

private let scheduleJSON = """
{
  "schedule_id": "schedule-1",
  "name": "Daily review",
  "prompt": "Review open pull requests.",
  "frequency": "daily",
  "schedule_type": "recurring",
  "agent": "devin",
  "bypass_approval": false,
  "playbook_id": "playbook-1",
  "tags": ["review"],
  "notify_on": "completion",
  "scheduled_at": "2026-06-28T13:00:00Z",
  "enabled": true,
  "last_executed_at": null,
  "error": null
}
"""

private let disabledScheduleJSON = """
{
  "schedule_id": "schedule-1",
  "name": "Daily review",
  "prompt": "Review open pull requests.",
  "frequency": "daily",
  "schedule_type": "recurring",
  "agent": "devin",
  "enabled": false
}
"""

private let scheduleListJSON = """
{
  "items": [
    \(scheduleJSON)
  ],
  "has_next_page": false,
  "end_cursor": null,
  "total": 1
}
"""

private let liveScheduleListJSON = """
{
  "items": [
    {
      "scheduled_session_id": "sched-1",
      "org_id": "org-test",
      "created_by": "bot_apk",
      "name": "Codex Test Schedule",
      "prompt": "Temporary CRUD verification.",
      "playbook": null,
      "frequency": "0 13 * * *",
      "interval_count": 1,
      "schedule_type": "recurring",
      "scheduled_at": "2026-06-27T17:00:50Z",
      "enabled": true,
      "last_executed_at": null,
      "last_error_message": null,
      "notify_on": "always",
      "agent": "devin",
      "bypass_approval": false,
      "tags": null
    }
  ],
  "end_cursor": null,
  "has_next_page": false,
  "total": 1
}
"""

private let secretJSON = """
{
  "secret_id": "secret-1",
  "key": "API_TOKEN",
  "note": "Used by CI",
  "type": "key-value",
  "created_by": "service-user",
  "is_sensitive": true,
  "created_at": 1782572400
}
"""

private let secretListJSON = """
{
  "items": [
    \(secretJSON)
  ],
  "has_next_page": false,
  "end_cursor": null,
  "total": 1
}
"""

private func scheduleMutation(enabled: Bool) -> ScheduleMutation {
    ScheduleMutation(
        name: "Daily review",
        prompt: "Review open pull requests.",
        frequency: "0 13 * * *",
        scheduleType: .recurring,
        agent: .devin,
        bypassApproval: false,
        playbookId: "playbook-1",
        tags: ["review"],
        notifyOn: "always",
        scheduledAt: "2026-06-28T13:00:00Z",
        enabled: enabled
    )
}

private func p1MakeClient(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> DevinAPIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.requestHandler = handler
    return DevinAPIClient(
        apiKey: "test-key",
        orgId: "org-test",
        session: URLSession(configuration: configuration)
    )
}

private func p1JSONResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    body: String
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(body.utf8))
}

private func p1RequestJSONBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try p1RequestBodyData(request)
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
}

private func p1RequestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeContentData)
        }
        if count == 0 {
            break
        }
        data.append(buffer, count: count)
    }

    return data
}
