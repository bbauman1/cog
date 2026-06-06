# Devin Command Center — Native SwiftUI iOS App

## Product Plan & Technical Architecture

---

## 1. Executive Summary

**Devin Command Center** is a native SwiftUI iPhone app that gives developers on-the-go control over their Devin AI sessions. Think of it as mission control for your AI engineer — monitor active sessions, spin up new work, chat with Devin, manage your knowledge base and playbooks, and get notified the instant Devin needs you or finishes a task.

The app is built on the [Devin API v3](https://docs.devin.ai/api-reference/overview), targets **iOS 26+** exclusively, and is designed to exploit the latest native iOS capabilities (Liquid Glass design language, Live Activities, Widgets, Foundation Models, SF Symbols, on-device speech-to-text, Siri, Shortcuts, biometrics) to deliver an experience that is impossible to replicate in a mobile browser.

> **Design principle:** Follow how Devin looks and works on mobile web today, but expressed through iOS 26's Liquid Glass design system. The app should feel native-first — not a web wrapper.

> **Key architecture decision: No backend.** This is a fully client-side app. The user's Devin API key is stored in the iOS Keychain and the app hits `api.devin.ai` directly. Zero infrastructure to deploy or maintain. The only feature that would eventually benefit from a backend is real-time remote push notifications — that's scoped as an optional Tier 4 add-on, only to be built if local notification latency (~15 min when backgrounded) becomes a real user complaint.

---

## 2. Devin API Surface — What We Have to Work With

### 2.1 Authentication

| Method | Token Prefix | Notes |
|---|---|---|
| Service User API Key | `cog_` | Recommended for automation. Org-scoped or enterprise-scoped. |
| Personal Access Token (PAT) | `cog_` | **Closed beta.** Authenticates as the human user directly. |

- Base URL: `https://api.devin.ai/v3`
- Auth header: `Authorization: Bearer cog_...`
- Organization ID (`org_id`) required in all org-level endpoints.

### 2.2 Available Endpoints (v3)

| Domain | Endpoints | Key Operations |
|---|---|---|
| **Sessions** | `POST/GET /organizations/{org_id}/sessions` | Create, list, get, messages, attachments, tags, terminate |
| **Knowledge** | `POST/GET/PUT/DELETE /organizations/{org_id}/knowledge/notes` | CRUD notes with name, trigger, body |
| **Playbooks** | `POST/GET/PUT/DELETE /organizations/{org_id}/playbooks` | CRUD playbooks with name & instructions |
| **Schedules** | `POST/GET/PATCH/DELETE /organizations/{org_id}/schedules` | CRUD cron-based scheduled sessions |
| **Automations** | `POST/GET/PUT/DELETE /organizations/{org_id}/automations` | Event-driven automations (GitHub, Slack, Linear, webhooks) |
| **Secrets** | `POST/GET/DELETE /organizations/{org_id}/secrets` (v1) | Manage org secrets (metadata only, no values returned) |
| **Enterprise** | `/v3/enterprise/*` | Orgs, members, audit logs, consumption, billing |
| **Self** | `GET /v3/self` | Verify credentials, get principal identity |

### 2.3 Session Model (key fields)

```
SessionResponse {
  session_id: String          // e.g. "devin-abc123"
  url: String                 // Web link to session
  status: Enum                // new | claimed | running | exit | error | suspended | resuming
  status_detail: Enum         // working | waiting_for_user | waiting_for_approval | finished | ...
  acus_consumed: Float        // Usage metric
  pull_requests: [PR]         // Associated PRs
  created_at: Int             // Unix timestamp
  origin: Enum                // webapp | api | slack | cli | desktop | ...
  category: Enum?             // bug_fixing | feature_development | ...
  tags: [String]
  child_session_ids: [String]?
  playbook_id: String?
}
```

### 2.4 Pagination

All list endpoints use cursor-based pagination: `?first=N&after=<cursor>`. Responses include `has_next_page`, `end_cursor`, and `total`.

---

## 3. App Authentication Strategy

> **Context:** This is a third-party app. We cannot modify the Devin web dashboard or create new server-side auth flows on Devin's infrastructure. We can only use what the [Devin API](https://docs.devin.ai/api-reference/authentication) exposes today.

The Devin API authenticates via bearer tokens (`cog_` prefix) — there is no OAuth2 flow for third-party apps. Two token types exist:

| Token Type | Status | Who It Authenticates As | Source |
|---|---|---|---|
| Service User API Key | **GA** | A non-human service user (org-scoped) | [Docs: Authentication](https://docs.devin.ai/api-reference/authentication) |
| Personal Access Token (PAT) | **Closed beta** (feature-flagged, contact support) | The human user themselves | [Docs: Personal Access Tokens](https://docs.devin.ai/api-reference/personal-access-tokens) |

### 3.1 Recommended Approach: Phased Third-Party Auth

**Phase 1 (MVP): Direct token entry + Keychain storage**

This is the only viable approach today and is the standard pattern for third-party API clients (similar to how apps like Working Copy, Blink Shell, or HTTP clients handle API keys).

- User generates a Service User API Key (or PAT if they have beta access) from [Settings > Service Users](https://app.devin.ai) in the Devin web dashboard.
- User enters the `cog_` token and their org ID into the app.
- We provide an in-app guide with step-by-step screenshots showing where to find these values.
- Token is validated immediately via `GET /v3/self` before storing.
- Stored in the iOS Keychain (encrypted, hardware-backed via Secure Enclave).
- App is protected behind Face ID / Touch ID on every cold launch.

The onboarding UX matters a lot here — we need to make the key-entry flow as frictionless as possible:
- Deep link / universal link support: user could tap a link from their browser that passes the key to the app (e.g., `devincommand://auth?token=cog_...&org=org-...`). This lets them copy the key on their Mac/desktop and send it to their phone via iMessage/AirDrop/universal clipboard.
- Clipboard detection: offer to paste from clipboard if it contains a `cog_` prefix string.
- Clear inline instructions with a "Open Devin Settings" button that links to `https://app.devin.ai`.

**Phase 2: Multi-account & smart token management**

- Support multiple org credentials (users may belong to several Devin orgs).
- Token health monitoring: periodically call `GET /v3/self` to detect revoked keys and prompt re-auth.
- Guide users toward PATs once they become GA — PATs are better for end users since they authenticate as the human user directly (proper audit trail, personal permissions).
- Implement token rotation reminders (e.g., "Your token is 90 days old, consider rotating").

**Phase 3 (Aspirational): OAuth2 PKCE — if/when Devin supports it**

- If Cognition ever adds an OAuth2 authorization server for third-party apps, we would implement Authorization Code + PKCE via `ASWebAuthenticationSession`.
- This would eliminate all manual token handling — users just tap "Sign in with Devin" and authorize in a browser sheet.
- Until then, this phase is aspirational. We should monitor the [Devin API release notes](https://docs.devin.ai/api-reference/release-notes) for any OAuth2 announcements.

### 3.2 Token Types: Practical Guidance for Users

The app should guide users on which token type to use:

| User Scenario | Recommended Token | Why |
|---|---|---|
| Individual user, wants sessions attributed to them | **PAT** (if available) | Sessions show as created by _them_, not a bot |
| Individual user, no PAT access | **Service User API Key** + `create_as_user_id` | Workaround: create a service user, grant `ImpersonateOrgSessions`, pass own user ID |
| Team admin managing org sessions | **Service User API Key** with `ManageOrgSessions` | Designed for automation and management |
| Enterprise, multiple orgs | **Enterprise Service User API Key** | Cross-org access via `/v3/enterprise/*` |

The app's onboarding flow should ask "What do you want to do?" and recommend the right token type + required permissions.

### 3.3 Security Measures (All Phases)

| Layer | Implementation |
|---|---|
| Storage | iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — encrypted at rest, device-bound, excluded from backups |
| App lock | Require Face ID / Touch ID on every cold launch (via `LAContext`) |
| Transport | TLS 1.3 only; certificate pinning for `api.devin.ai` |
| Token display | Never show full token in UI; mask with `cog_••••••ab3f` |
| Clipboard | Auto-clear clipboard 30 seconds after paste-detection is used |
| URL scheme | Validate token format (`cog_` prefix) before accepting via deep link; reject malformed input |
| Logout | Keychain wipe + in-memory credential zeroing |
| Jailbreak detection | Optional: warn users on compromised devices |

---

## 4. Long-Term Vision

The fully realized Devin Command Center is a **real-time, AI-native mobile command center** that makes Devin feel like a teammate in your pocket:

```
┌─────────────────────────────────────────────────┐
│             DEVIN COMMAND CENTER                 │
│                                                  │
│  ┌───────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Sessions  │  │ Create   │  │  Knowledge   │  │
│  │ Dashboard │  │ Session  │  │  & Playbooks │  │
│  └─────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│        │              │               │          │
│  ┌─────▼──────────────▼───────────────▼───────┐  │
│  │         Devin API v3 Service Layer         │  │
│  └─────┬──────────────┬───────────────┬───────┘  │
│        │              │               │          │
│  ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼───────┐  │
│  │   Push    │  │   Live    │  │   Widgets   │  │
│  │  Notifs   │  │Activities │  │  & Siri     │  │
│  └───────────┘  └───────────┘  └─────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │     Schedules │ Automations │ Analytics    │  │
│  └────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Vision Pillars

1. **Real-time awareness** — You always know what Devin is doing. Live Activities on the lock screen show active session progress. Push notifications fire when Devin needs input, hits an error, or finishes work.

2. **Instant action** — Create sessions with voice ("Hey Siri, tell Devin to fix the login bug"), from the Share Sheet (share a GitHub issue URL → create session), or with one tap from a Widget.

3. **Conversational control** — Chat with running sessions like iMessage. Send follow-up instructions, approve PRs, upload screenshots from your camera roll.

4. **Org-wide visibility** — Dashboard of all sessions across your org. Filter by status, assignee, category. See ACU consumption trending. Enterprise users see cross-org analytics.

5. **Deep system integration** — Spotlight search finds past sessions. Universal Links open `app.devin.ai` URLs in the app. Shortcuts power complex multi-step automations.

---

## 5. Feature Breakdown by Priority

### Tier 1 — MVP (Weeks 1-4): "Monitor & Control"

The MVP answers the #1 user need: **"What is Devin doing right now, and can I talk to it?"**

| Feature | API Endpoints | iOS Tech |
|---|---|---|
| **Onboarding & Auth** — paste API key + org ID, store in Keychain, Face ID lock | `GET /v3/self` | Keychain, LocalAuthentication |
| **Session List** — paginated list with status badges, pull-to-refresh, search/filter by status | `GET /sessions?first=20` | SwiftUI `List`, `AsyncImage`, `Searchable` |
| **Session Detail** — status, ACUs, PRs, created time, category, tags | `GET /sessions/{id}` | SwiftUI detail view |
| **Session Chat** — read messages, send messages to active sessions | `GET /sessions/{id}/messages`, `POST /sessions/{id}/messages` | Chat-style UI with `ScrollViewReader` |
| **Create Session** — prompt input, optional repo/playbook/tags/mode selection | `POST /sessions` | Sheet with form, playbook picker |
| **Terminate Session** — swipe-to-terminate or button | `DELETE /sessions/{id}` (terminate) | Swipe actions, confirmation alert |
| **Playbook List** — browse playbooks to attach when creating sessions | `GET /playbooks` | Picker integration |

**Architecture for MVP:**

```
DevinCommandCenter/
├── App/
│   ├── DevinCommandCenterApp.swift     // @main entry point
│   └── AppState.swift                  // Global auth state (ObservableObject)
├── Services/
│   ├── DevinAPIClient.swift            // URLSession-based API client
│   ├── KeychainService.swift           // Keychain CRUD wrapper
│   └── AuthenticationService.swift     // Biometric auth (Face ID/Touch ID)
├── Models/
│   ├── Session.swift                   // Codable session model
│   ├── Message.swift                   // Session message model
│   ├── Playbook.swift                  // Playbook model
│   └── PaginatedResponse.swift         // Generic paginated response
├── Views/
│   ├── Auth/
│   │   ├── LoginView.swift             // API key entry
│   │   └── BiometricUnlockView.swift   // Face ID prompt
│   ├── Sessions/
│   │   ├── SessionListView.swift       // Main session list
│   │   ├── SessionRowView.swift        // List row component
│   │   ├── SessionDetailView.swift     // Session detail + chat
│   │   └── CreateSessionView.swift     // New session form
│   └── Settings/
│       └── SettingsView.swift          // Account info, logout, preferences
├── ViewModels/
│   ├── SessionListViewModel.swift      // Pagination, filtering, polling
│   ├── SessionDetailViewModel.swift    // Messages, status updates
│   └── CreateSessionViewModel.swift    // Form validation, submission
└── Extensions/
    ├── Date+Formatting.swift
    └── Color+Devin.swift               // Brand colors
```

**Key MVP Technical Decisions:**

- **Networking:** `URLSession` + `async/await` (no third-party deps). Generic `DevinAPIClient` with typed request/response.
- **State management:** `@Observable` (iOS 17+) or `ObservableObject` + `@Published` (iOS 16 support).
- **Polling:** `Timer.publish` every 5-10 seconds for active session status. Background refresh via `BGAppRefreshTask`.
- **Minimum target:** iOS 17.0 (lets us use `@Observable`, `#Preview`, SwiftData if needed).

### Tier 2 — Notifications & Glanceability (Weeks 5-8)

| Feature | API Mechanism | iOS Tech |
|---|---|---|
| **Local Notifications** — session finished, error, waiting for user, PR created | Polling + `BGAppRefreshTask` → local notification | `UNUserNotificationCenter`, rich notifications |
| **Home Screen Widgets** — active session count, latest session status | `GET /sessions` | WidgetKit (small, medium, large) |
| **Live Activities** — real-time session progress on lock screen | `GET /sessions/{id}` (poll) | ActivityKit + `LiveActivityAttributes` |
| **Session Attachments** — view/download files from sessions | `GET /sessions/{id}/attachments` | Quick Look, share sheet |
| **Knowledge Notes** — browse, create, edit, delete notes | `GET/POST/PUT/DELETE /knowledge/notes` | CRUD views with editor |

**Notification Architecture:**

> **Design decision:** No backend for MVP. The app is fully client-side — it stores the Devin API key in Keychain and hits `api.devin.ai` directly. This means zero infrastructure cost and zero deployment complexity.

**MVP: Client-side polling + local notifications (no backend)**
- When app is foregrounded, poll `GET /sessions` every 5-10 seconds and diff against last-known state.
- Background App Refresh (`BGAppRefreshTask`) polls when backgrounded — iOS throttles this to ~15-30 minutes and it's not guaranteed.
- Trigger local `UNNotificationRequest` when session status transitions are detected (e.g., running → waiting_for_user, running → exit).
- Rich notification with session title, status, and action buttons ("View Session", "Send Message").
- **Limitation:** Notifications are delayed up to 15-30 minutes when the app is fully backgrounded or killed. This is an acceptable tradeoff for zero infrastructure.

**Future (Tier 4): Optional remote notifications via lightweight backend**
- When the user base grows and real-time alerts become critical, add an optional backend relay:
  - Tiny server (Cloudflare Worker, AWS Lambda, or Fly.io) stores encrypted device push tokens + Devin API keys.
  - Polls `GET /sessions` every 10-30 seconds per active user.
  - Compares session status to last-known state; sends APNs push on transitions.
  - ~200 lines of code. Estimated infra cost: <$5/month for small user base.
- Device registers its APNs push token with the relay on opt-in.
- This is additive — local notifications continue to work for users who don't opt in.
- **Only build this when local notification latency becomes a real user complaint.**

### Tier 3 — Power Features (Weeks 9-14)

| Feature | API Mechanism | iOS Tech |
|---|---|---|
| **Siri & Shortcuts** — "Hey Siri, ask Devin to fix the tests" | `POST /sessions` | `AppIntents`, `SiriTipView` |
| **Share Sheet** — share a URL/text → create session | `POST /sessions` (prompt = shared content) | Share Extension |
| **Spotlight Search** — find past sessions from home screen | Local index of session data | `CSSearchableItem`, Core Spotlight |
| **Universal Links** — tap `app.devin.ai/sessions/xyz` → opens in app | URL matching | Associated Domains, `onOpenURL` |
| **Schedule Management** — view, create, edit, toggle schedules | `POST/GET/PATCH/DELETE /schedules` | CRUD views with cron builder |
| **Automation Browser** — view and manage automations | `GET/PUT/DELETE /automations` | List + detail views |
| **Batch Operations** — terminate/archive multiple sessions | Multiple `DELETE`/`PATCH` calls | Edit mode with multi-select |

### Tier 4 — Org Intelligence & Enterprise (Weeks 15-20+)

| Feature | API Mechanism | iOS Tech |
|---|---|---|
| **Analytics Dashboard** — ACU consumption, session trends, PR throughput | `GET /sessions` (aggregate client-side) or enterprise endpoints | Swift Charts |
| **Team View** — see sessions by team member | Enterprise member + session APIs | Grouped list views |
| **PR Review Flow** — see PRs from sessions, open in GitHub/browser | Session `pull_requests` field | Deep links to GitHub app |
| **Audit Log Viewer** — enterprise audit trail | `GET /enterprise/audit-logs` | Searchable log view |
| **Multi-Org Support** — switch between organizations | `GET /enterprise/organizations` | Org picker in settings |
| **Apple Watch Companion** — session status on wrist, haptic alerts | Session status polling | WatchKit, `WKExtendedRuntimeSession` |
| **iPad Optimized Layout** — multi-column, keyboard shortcuts | Same API | `NavigationSplitView`, keyboard shortcuts |

---

## 6. Technical Architecture

### 6.1 Networking Layer

```swift
// Core API client — thin wrapper over URLSession
final class DevinAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.devin.ai/v3")!
    private let keychain: KeychainService

    func request<T: Decodable>(
        _ endpoint: Endpoint,
        method: HTTPMethod = .get,
        body: (any Encodable)? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: endpoint.path))
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(try keychain.getAPIKey())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200...201: return try JSONDecoder().decode(T.self, from: data)
        case 401: throw APIError.unauthorized
        case 429: throw APIError.rateLimited
        default: throw APIError.httpError(http.statusCode, data)
        }
    }
}
```

### 6.2 Credential Storage

```swift
final class KeychainService {
    private static let apiKeyAccount = "ai.devin.commandcenter.apikey"
    private static let orgIdAccount  = "ai.devin.commandcenter.orgid"

    func store(apiKey: String, orgId: String) throws {
        try set(apiKey, account: Self.apiKeyAccount)
        try set(orgId,  account: Self.orgIdAccount)
    }

    // kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    // → encrypted at rest, not included in backups, device-bound
    private func set(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String:   Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }
}
```

### 6.3 Session Polling & State

```swift
@Observable
final class SessionListViewModel {
    var sessions: [Session] = []
    var isLoading = false
    private var pollingTask: Task<Void, Never>?

    func startPolling(interval: TimeInterval = 5) {
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refresh() async {
        let response: PaginatedResponse<Session> = try await api.request(
            .sessions(orgId: orgId, first: 20, status: currentFilter)
        )
        sessions = response.items
    }
}
```

### 6.4 Live Activity (Lock Screen Session Tracker)

```swift
struct DevinSessionAttributes: ActivityAttributes {
    let sessionId: String
    let prompt: String

    struct ContentState: Codable, Hashable {
        let status: String        // "running", "waiting_for_user", etc.
        let statusDetail: String
        let acusConsumed: Double
        let elapsedMinutes: Int
    }
}

// Start Live Activity when user taps "Track" on a running session
func startLiveTracking(session: Session) throws {
    let attributes = DevinSessionAttributes(
        sessionId: session.id,
        prompt: String(session.prompt.prefix(60))
    )
    let state = DevinSessionAttributes.ContentState(
        status: session.status,
        statusDetail: session.statusDetail,
        acusConsumed: session.acusConsumed,
        elapsedMinutes: session.elapsedMinutes
    )
    _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
}
```

### 6.5 Widget

```swift
struct DevinSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ActiveSessions", provider: SessionTimelineProvider()) { entry in
            VStack(alignment: .leading) {
                Text("\(entry.activeSessions) active")
                    .font(.title2.bold())
                Text("\(entry.waitingSessions) waiting for you")
                    .foregroundStyle(.orange)
                if let latest = entry.latestSession {
                    Text(latest.prompt.prefix(40))
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .configurationDisplayName("Devin Sessions")
        .description("Active session overview at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

---

## 7. MVP Build Plan — Sprint Overview

> **Detailed task lists with testing built into each sprint are in Section 14.**

| Sprint | Timeline | Deliverable |
|---|---|---|
| **Sprint 0** | Day 1-2 | Hello World app builds + runs in Limrun simulator (toolchain validation) |
| **Sprint 1** | Week 1-2 | Auth + session list (working API integration, mock tests, screenshot proof) |
| **Sprint 2** | Week 3-4 | Session detail + chat + create + terminate (full lifecycle) |
| **Sprint 3** | Week 5-6 | Notifications + Widgets |
| **Sprint 4** | Week 7-8 | Live Activities + Knowledge + Attachments |

Each sprint's PR includes: unit tests (mock), UI screenshots, interaction videos, and integration test results. See Section 12 for the full testing workflow and Section 14 for detailed task checklists.

---

## 8. Backlog — Post-MVP Iterations

Ordered by expected user impact. Each item is a candidate for a 1-2 week sprint.

### Phase 2: Power User Features

1. **Siri Shortcuts integration** — `AppIntents` for "Create Devin Session", "Check Session Status", "List Active Sessions". Surfaces in Shortcuts app for automation.

2. **Share Extension** — Share a URL, error log, or screenshot from any app → create a Devin session with it as context. Maps to `POST /sessions` with `attachment_urls` or inline prompt.

3. **Universal Links** — Register `app.devin.ai` associated domain. Tapping any `app.devin.ai/sessions/*` link opens directly in the app.

4. **Spotlight indexing** — Index completed sessions with `CSSearchableItem`. Users can search "login bug fix" from home screen and jump to the session.

5. **Schedule management** — CRUD interface for cron schedules. Visual cron builder (day/time picker rather than raw cron syntax). Toggle schedules on/off.

6. **Automation browser** — Read-only view of configured automations (GitHub triggers, Slack triggers, etc.) with ability to enable/disable.

### Phase 3: Team & Org Features

7. **Multi-org support** — Org switcher for users belonging to multiple organizations. Each org gets its own credential set in Keychain.

8. **Team activity feed** — See all sessions across the org, not just your own. Filter by team member. Useful for engineering managers.

9. **ACU analytics dashboard** — Swift Charts visualizations: daily ACU burn rate, session count trends, category breakdown pie chart, cost projections.

10. **PR integration** — Surface pull requests from sessions prominently. One-tap to open in GitHub mobile app. Show PR status (open/merged/closed).

11. **Audit log viewer** (enterprise) — Searchable audit trail. Filter by action type, user, date range.

### Phase 4: Advanced & Experimental

12. **Apple Watch companion** — Complication showing active session count. Haptic tap when session needs attention. Quick "terminate" action.

13. **iPad multi-column layout** — `NavigationSplitView` with session list + detail side-by-side. Keyboard shortcuts (Cmd+N new session, Cmd+R refresh).

14. **Offline mode** — Cache recent sessions in SwiftData. Queue messages for send when connectivity returns.

15. **Remote push notification backend (optional)** — Lightweight relay service (Cloudflare Worker / Lambda) that polls Devin API per-user and sends real APNs pushes. Opt-in for users who want <30 second notification latency. Only build when local notification delay becomes a user pain point.

16. **Voice session creation** — On-device speech-to-text (`SFSpeechRecognizer`) → directly submit as session prompt. "Record a task for Devin" workflow.

17. **Session templates** — Save frequently-used session configs (repo + playbook + tags + mode) as templates for one-tap creation.

18. **Haptic feedback language** — Distinct haptic patterns for different events: success (triple tap), error (buzz), waiting (gentle pulse).

19. **Cross-device credential transfer** — Use Apple's universal clipboard or a custom URL scheme (`devincommand://auth?token=...&org=...`) so users can copy credentials on desktop and open them on phone with one tap.

20. **App Clip** — Lightweight clip accessible via shared link. View a specific session's status without installing the full app.

---

## 9. Native iOS Capabilities Utilization Map

| iOS Capability | Where Used | Phase |
|---|---|---|
| **SwiftUI (iOS 26)** | Entire UI layer | MVP |
| **Liquid Glass** (`.glassEffect()`) | Tab bar, toolbars, floating buttons, sheets | MVP |
| **SF Symbols 7** (draw-on animations) | Status badges, action icons, loading states | MVP |
| **`@Animatable` macro** | Session status transitions, morphing | MVP |
| **Keychain Services** | API key + org ID storage | MVP |
| **LocalAuthentication** (Face ID / Touch ID) | App unlock | MVP |
| **URLSession async/await** | All API calls | MVP |
| **Pull-to-refresh** (`.refreshable`) | Session list, knowledge list | MVP |
| **Searchable** + `Tab(role: .search)` | Session filtering via glass search tab | MVP |
| **NavigationStack** + `.navigationSubtitle()` | Navigation with session status subtitles | MVP |
| **Sheet morphing** (`.glassEffectID()`) | Smooth list → detail transitions | MVP |
| **WidgetKit** | Home screen session widgets | Tier 2 |
| **ActivityKit** (Live Activities) | Lock screen session tracking | Tier 2 |
| **UNUserNotificationCenter** | Local push notifications | Tier 2 |
| **Background App Refresh** | Polling when backgrounded | Tier 2 |
| **Quick Look** | Attachment preview | Tier 2 |
| **WebView** (SwiftUI native, iOS 26) | Preview Devin session web URLs in-app | Tier 2 |
| **Rich TextEditor** (AttributedString) | Formatted session prompt composition | Tier 2 |
| **AppIntents** (Siri & Shortcuts) | Voice commands, automation | Tier 3 |
| **Share Extension** | Create session from any app | Tier 3 |
| **Core Spotlight** | Session search from home screen | Tier 3 |
| **Associated Domains** (Universal Links) | Open Devin URLs in-app | Tier 3 |
| **Foundation Models** (on-device LLM) | Summarize sessions, suggest prompts, smart search | Tier 3 |
| **`SpeechRecognizer`** (on-device, iOS 26) | Voice-to-prompt without network | Tier 3 |
| **Swift Charts** | Analytics dashboard | Tier 4 |
| **SwiftData** | Offline cache | Tier 4 |
| **WatchKit** | Apple Watch companion | Tier 4 |
| **AVFoundation** | Camera for screenshots/attachments | Tier 4 |

---

## 10. Tech Stack & Dependencies

| Layer | Choice | Rationale |
|---|---|---|
| UI Framework | **SwiftUI (iOS 26+)** | Liquid Glass, latest APIs, no backward compat baggage |
| Design Language | **Liquid Glass** (`.glassEffect()`, `GlassEffectContainer`) | iOS 26 native, matches system chrome |
| Language | **Swift 6** (strict concurrency) | Modern, safe, fast |
| Min Deployment | **iOS 26.0** | Access to Foundation Models, Liquid Glass, latest SF Symbols |
| Networking | `URLSession` + `async/await` | Zero deps, built-in, sufficient for REST |
| JSON | `Codable` + `JSONDecoder` | No third-party needed |
| Secure storage | Keychain Services (Security framework) | Hardware-backed encryption |
| Biometrics | LocalAuthentication (`LAContext`) | Face ID / Touch ID / Optic ID |
| State | `@Observable` (Observation framework) | Modern, less boilerplate than Combine |
| Navigation | `NavigationStack` + `NavigationPath` | Programmatic, type-safe |
| Image loading | `AsyncImage` | Built-in |
| Persistence | SwiftData (later phases for offline) | Native, iCloud-ready |
| Charts | Swift Charts (later phases) | Native, accessible |
| On-device AI | Foundation Models framework | Summarize sessions, smart search, no cloud cost |
| Speech | `SpeechRecognizer` (on-device models) | Voice-to-prompt without network |
| Testing | XCTest + Swift Testing | Built-in |
| Project Management | **XcodeGen** (`project.yml` → `.xcodeproj`) | No Xcode GUI needed, git-friendly |
| Build (remote) | **Limrun** (`lim xcode build`) | Cloud Xcode from Linux |
| Build (CI) | GitHub Actions (macOS runner) | Automated builds + TestFlight |
| MCP (optional) | Xcode Build MCP ([`xcodebuild-mcp`](https://github.com/redne-w/xcodebuild-mcp)) | AI-assisted build/test/sim management |

**Zero external Swift dependencies for MVP.** Everything uses Apple-native frameworks. This keeps the binary small, avoids dependency risk, and aligns with App Store review preferences.

> **iOS 26 exclusive:** We intentionally do NOT support iOS 18 or earlier. This frees us to use Liquid Glass, Foundation Models, the new `SpeechRecognizer`, and all latest SwiftUI APIs without conditional compilation or backward-compat shims.

---

## 10a. iOS 26 Design Language & Modern Features

### Liquid Glass — Design System

Liquid Glass is iOS 26's unified design language. It provides a translucent, adaptive material for navigational and overlay elements. Key principles:

- **Glass sits on top of content** — toolbars, tab bars, floating action buttons, sheets. Never use it as a background for primary content areas.
- **Automatically adapts** — changes from light to dark based on underlying content as you scroll.
- **Controls come alive** — toggles, sliders, segmented pickers transform into Liquid Glass during interaction.

**SwiftUI APIs we'll use:**

| API | Where Used |
|---|---|
| `.glassEffect()` | Floating action buttons (create session), custom overlays |
| `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` | Primary action buttons |
| `GlassEffectContainer` | Group glass elements for optimized rendering + morphing transitions |
| `.glassEffectID()` | Smooth morphing between glass elements during navigation |
| `.tabBarMinimizeBehavior(.onScrollDown)` | Tab bar collapses while scrolling session lists |
| `Tab(role: .search)` + `.searchable()` | Search tab transforms tab bar into live text field |
| Navigation subtitle (`.navigationSubtitle()`) | Show session status under title |
| `.scrollEdgeEffectStyle(.soft)` | Blur/fade content under toolbars |

### iOS 26 Features We'll Leverage

| Feature | Use Case in Our App | Phase |
|---|---|---|
| **Liquid Glass** tab bar + toolbars | App-wide navigation, session actions | MVP |
| **SF Symbols 7** (draw-on animations) | Status badges, action confirmations, loading states | MVP |
| **`@Animatable` macro** | Smooth transitions between session states | MVP |
| **WebView** (native SwiftUI) | Preview Devin session web URLs in-app | Tier 2 |
| **Rich TextEditor** (AttributedString) | Compose session prompts with formatting | Tier 2 |
| **Foundation Models** (on-device LLM) | Summarize session output, suggest prompts, smart search | Tier 3 |
| **`SpeechRecognizer`** (on-device) | Voice-to-prompt: dictate session tasks hands-free | Tier 3 |
| **Section index labels** | Alphabetical jump in Knowledge notes list | Tier 2 |
| **Sheet morphing** | Smooth transitions from list items to detail sheets | MVP |

### Design Reference: Devin Mobile Web

The app's information architecture mirrors Devin's mobile web experience:
- **Session list** = primary view (like the web's session dashboard)
- **Session detail** = chat + status + actions (like the web's session view)
- **Create session** = prompt + config (like the web's "New Session" dialog)

But expressed natively: Liquid Glass navigation, haptic feedback, SF Symbol animations, system-native gesture patterns.

---

## 10b. No-Xcode Development Workflow

> **Goal: Never open Xcode.** The entire project is managed via text files, CLI tools, and AI agents.

### Project Structure (XcodeGen)

We use [XcodeGen](https://github.com/yonaskolb/XcodeGen) to define the project in a YAML file. The `.xcodeproj` is generated on-demand and never committed to git.

```yaml
# project.yml — the single source of truth for our Xcode project
name: DevinCommandCenter
options:
  bundleIdPrefix: com.devincommand
  deploymentTarget:
    iOS: "26.0"
  xcodeVersion: "26.0"

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete

targets:
  DevinCommandCenter:
    type: application
    platform: iOS
    sources: [Sources]
    resources: [Resources]
    settings:
      base:
        INFOPLIST_FILE: Sources/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.devincommand.app
    dependencies: []

  DevinCommandCenterTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies:
      - target: DevinCommandCenter

  DevinCommandCenterUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: DevinCommandCenter

schemes:
  DevinCommandCenter:
    build:
      targets:
        DevinCommandCenter: all
    run:
      config: Debug
    test:
      targets:
        - DevinCommandCenterTests
        - DevinCommandCenterUITests
```

### File Layout

```
DevinCommandCenter/
├── project.yml                    # XcodeGen spec (committed)
├── .gitignore                     # *.xcodeproj, DerivedData/, etc.
├── Sources/
│   ├── App/
│   │   └── DevinCommandCenterApp.swift
│   ├── Views/
│   ├── ViewModels/
│   ├── Services/
│   ├── Models/
│   └── Info.plist
├── Tests/
├── UITests/
├── Resources/
│   └── Assets.xcassets
├── scripts/
│   ├── generate                   # xcodegen generate
│   ├── build                      # lim xcode build . (or xcodebuild)
│   ├── test                       # lim xcode build . --scheme Tests
│   └── lint                       # swiftlint
└── .agents/
    └── skills/
        └── ios-development/
            └── SKILL.md           # Devin skill for this project
```

### Development Loop (Devin's Perspective)

```bash
# 1. Write/edit Swift files directly (no Xcode needed)
vim Sources/Views/SessionListView.swift

# 2. Generate .xcodeproj from YAML (only needed if targets/settings change)
xcodegen generate

# 3. Build remotely via Limrun
lim xcode build . --scheme DevinCommandCenter

# 4. Test in cloud simulator
lim ios element-tree              # read UI state
lim ios screenshot ./proof.png    # capture for PR
lim ios tap-element --ax-label "Sessions"  # interact

# 5. Run unit tests
lim xcode build . --scheme DevinCommandCenterTests
```

### Xcode Build MCP (Optional Enhancement)

The [Xcode Build MCP](https://github.com/redne-w/xcodebuild-mcp) exposes `xcodebuild` and `xcrun simctl` as MCP tools. If running on a macOS host (or via Limrun's sandbox), it provides:

| Tool | What It Does |
|---|---|
| `xcode_build` | Build project with structured error output |
| `xcode_test` | Run tests with filtering and detailed failure reports |
| `list_simulators` | Show available iOS simulators |
| `boot_simulator` | Boot a specific simulator |
| `install_app` | Install built app on simulator |
| `launch_app` | Launch app in simulator |
| `simulator_screenshot` | Capture simulator screen |

This is complementary to Limrun — Limrun handles the cloud case (building from Linux), while Xcode Build MCP handles the local macOS case if someone needs it.

### What We Never Commit to Git

- `.xcodeproj` / `.xcworkspace` (generated on-demand via `xcodegen generate`)
- `DerivedData/`
- `xcuserdata/`
- `.DS_Store`

### What We Always Commit

- `project.yml` (source of truth)
- All `.swift` source files
- `Info.plist`, `Assets.xcassets`
- `scripts/` directory
- `.agents/skills/` (Devin SKILL.md files)

---

## 11. Data Flow Architecture

```
┌──────────────┐     ┌───────────────────┐     ┌─────────────────┐
│   SwiftUI    │────▶│   ViewModel       │────▶│  DevinAPIClient │
│   Views      │◀────│   (@Observable)   │◀────│  (URLSession)   │
└──────────────┘     └───────────────────┘     └────────┬────────┘
                              │                         │
                     ┌────────▼────────┐       ┌────────▼────────┐
                     │  KeychainService│       │  api.devin.ai   │
                     │  (credentials)  │       │  (REST v3)      │
                     └─────────────────┘       └─────────────────┘
```

- **Unidirectional data flow:** Views observe ViewModels → ViewModels call API client → API client returns typed responses → ViewModels update published state → Views re-render.
- **No singletons:** Dependency injection via environment or init params.
- **Error propagation:** API errors bubble up to ViewModels which expose user-friendly error states.

---

## 12. Testing & Development Workflow

### 12.1 The Core Challenge

Devin runs on **Linux**. iOS apps require **macOS + Xcode** to build and simulate. This means we need an external build/test path. The goal: Devin writes code, builds it, tests it in a simulator, and provides visual proof in each PR — all without a local Mac.

### 12.2 Recommended Approach: Limrun

[**Limrun**](https://docs.limrun.com/docs) is cloud infrastructure specifically designed for this exact use case — letting coding agents on Linux VMs build and test iOS apps. It provides:

| Capability | How It Works |
|---|---|
| **Xcode Build Sandbox** | A real Mac running `xcodebuild` in the cloud. Devin syncs source code, builds remotely, gets logs back. |
| **iOS Simulator** | A real iOS simulator running on that Mac. The built app is auto-installed on successful build. |
| **Programmatic Control** | `lim ios element-tree` reads the accessibility tree; `lim ios tap-element` / `lim ios type` drive the UI. No flaky pixel coordinates. |
| **Screenshots & Video** | `lim ios screenshot` captures the screen; `lim ios record start/stop` captures video of interactions. |
| **Shareable Preview URL** | Each instance has a **Signed Stream URL** — a live view of the simulator in any browser. Attach to PRs so reviewers can open the running app themselves. |

**The Devin workflow per task:**

```
1. lim ios create --xcode --reuse-if-exists    # Boot simulator + Mac sandbox
2. lim xcode build .                           # Sync source, build, auto-install
3. lim ios element-tree                        # Read current screen state
4. lim ios screenshot ./proof.png              # Capture for PR
5. lim ios tap-element --ax-label "Connect"    # Drive the UI
6. lim ios record start → (interactions) → lim ios record stop -o demo.mp4
7. Attach screenshots + video + Signed Stream URL to PR
```

**Setup required (one-time, added to Devin environment):**

```bash
npm install --global lim
export LIM_API_KEY=lim_...  # stored as org secret
lim skills install           # installs Limrun skill in .agents/skills/
```

### 12.3 Alternative Build Options (Compared)

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **Limrun** | Purpose-built for agents, CLI-driven, preview URLs, element-tree testing, video recording | Requires `LIM_API_KEY`, usage-based cost | **Primary choice** — closest to what we need |
| **GitHub Actions (macOS runner)** | Free 2000 min/month (public repos), standard CI, mature | Build-only (no interactive simulation), $0.077/min for private repos, slow (~5 min per build) | **Secondary — CI/CD pipeline** for automated builds + unit tests on push |
| **Codemagic** | 500 free min/month (M2), good for indie devs, TestFlight integration | Similar limitations to GH Actions for interactive testing | Possible alternative to GH Actions |
| **no-mac-ios-starter template** | Proven pattern for building/deploying without a Mac | Template-based, less control, Capacitor-oriented | Reference architecture only |
| **Remote Mac (MacStadium/AWS EC2)** | Full macOS control, run anything | Expensive ($50+/month always-on), complex SSH management | Overkill — Limrun solves this better |

**Recommendation:** Limrun for interactive development/testing, GitHub Actions for CI/CD (automated build + unit test on every push).

### 12.4 Testing Strategy — Two Layers

We use a **mock-first + real-integration** hybrid approach:

#### Layer 1: Mock API (Deterministic UI Testing)

A mock Devin API lets Devin put the app into any state instantly — no real sessions needed.

**Implementation: Swift `URLProtocol` mock**

```swift
// MockURLProtocol.swift — intercepts URLSession requests in tests
class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else { fatalError("No handler") }
        let (response, data) = try! handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

**What mock testing covers:**

| Test Scenario | Mock Response | What It Validates |
|---|---|---|
| Happy path — session list loads | Return 5 sessions in various statuses | List renders correctly, status badges match |
| Empty state — no sessions | Return empty array | "No sessions" placeholder shown |
| Auth failure | Return 401 | App shows re-auth prompt, clears credential |
| Rate limited | Return 429 with `Retry-After` | Exponential backoff triggers, user sees "Rate limited" |
| Network offline | Return URLError.notConnectedToInternet | Offline state shown, retry button works |
| Session waiting for user | Return session with `status_detail: waiting_for_user` | Notification badge, typing indicator correct |
| Long message list | Return 100+ messages (paginated) | Cursor pagination loads correctly, scroll perf OK |
| Malformed response | Return invalid JSON | App shows error gracefully, no crash |

**When to use mocks:**
- Unit tests (XCTest / Swift Testing) — always
- UI tests (XCUITest) — for deterministic scenario coverage
- Devin's self-testing in Limrun — for validating UI layouts and flows without real API state

#### Layer 2: Real Devin Account (Integration Testing)

Use your personal Devin account's API key to validate real end-to-end flows.

**What real testing covers:**

| Test Scenario | Action | What It Validates |
|---|---|---|
| Auth works for real | Enter real `cog_` key + org ID | `GET /v3/self` returns real identity |
| Sessions load from real API | Fetch sessions | Real data renders correctly, pagination works |
| Create a real session | Submit a prompt via `POST /sessions` | Session appears in list, status transitions work |
| Send a message | Chat in a real session | Message delivered, Devin responds, polling picks it up |
| Terminate a session | Tap terminate | Session status moves to `exit` |

**When to use real API:**
- Integration smoke tests — run after a build passes mock tests
- Demo recordings — show the app working with actual data for PR reviews
- Polling/notification testing — verify timing behavior against the real API

#### Testing Cadence Per PR

Every PR Devin submits will include:

```
✓ Unit tests pass (mocked API, run via `xcodebuild test` in Limrun)
✓ Screenshot(s) showing the feature working (captured via `lim ios screenshot`)
✓ Video recording for interaction-heavy features (captured via `lim ios record`)
✓ Signed Stream URL (optional — for reviewer to interact with live simulator)
✓ Integration smoke test result (real API call logged)
```

### 12.5 Mock Server Architecture

Beyond `URLProtocol` for unit tests, we'll also build a lightweight **mock Devin API server** that runs alongside the app in a "demo mode":

```swift
// MockDevinServer — in-app, debug-only fake API
// Activated via: Settings > Developer > Use Mock API
//
// Returns canned responses for every endpoint:
// - GET /v3/self → mock identity
// - GET /sessions → configurable session list (0, 1, 5, 50 sessions)
// - GET /sessions/:id/messages → configurable chat history
// - POST /sessions → creates a fake session that transitions through statuses over time
// - POST /sessions/:id/messages → echoes back after 2 seconds
```

This lets us:
1. **Test without network** — airplane mode testing works
2. **Screenshot any state** — instantly show "5 running, 2 waiting" without creating real sessions
3. **Demo the app** — App Store screenshots, demo videos, investor pitches
4. **Devin self-tests efficiently** — no API calls needed per test cycle, faster iteration

### 12.6 Verifying Devin-as-a-Feature (Testing Our Own API Integration)

Since the app's core purpose is managing Devin sessions, and we're building with Devin, we have a unique recursive testing opportunity:

- **Create a dedicated "test org" or use your personal account** with a service user API key stored as a Devin org secret (`DEVIN_TEST_API_KEY`).
- **Integration test flow:** Build the app → install in simulator → enter test key → create a session → verify it appears in the web dashboard → send a message → verify Devin responds → terminate.
- **This is the ultimate proof-of-correctness:** if Devin can build the app, install it in a simulator, use it to create another Devin session, and verify that session works, the app is working.

### 12.7 CI/CD Pipeline

```
┌──────────────────────────────────────────────────────────────────────┐
│                          On Every Push / PR                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────────────┐   │
│  │ Lint & Format│───▶│ Unit Tests   │───▶│ Build (Limrun/GH       │   │
│  │ (SwiftLint)  │    │ (Mock API)   │    │ Actions macOS runner)  │   │
│  └─────────────┘    └──────────────┘    └────────────┬───────────┘   │
│                                                      │               │
│                                          ┌───────────▼────────────┐  │
│                                          │ Install in Simulator   │  │
│                                          │ (Limrun iOS instance)  │  │
│                                          └───────────┬────────────┘  │
│                                                      │               │
│                                          ┌───────────▼────────────┐  │
│                                          │ UI Smoke Test          │  │
│                                          │ (element-tree + taps)  │  │
│                                          └───────────┬────────────┘  │
│                                                      │               │
│                                          ┌───────────▼────────────┐  │
│                                          │ Screenshot + Video     │  │
│                                          │ (attached to PR)       │  │
│                                          └────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 13. What to Build First — Sprint 0

**Before Sprint 1, we validate the entire toolchain with a Hello World app.**

### Sprint 0 (Day 1-2): Hello Build

**Deliverable:** A minimal SwiftUI app that builds via Limrun, runs in a cloud simulator, and produces a screenshot — proving the full Devin → Xcode → Simulator pipeline works.

- [ ] Create Xcode project structure (Swift Package Manager or `project.yml` for XcodeGen)
- [ ] Single `ContentView.swift` with "Hello, Devin Command Center" text
- [ ] Set up Limrun: `npm install -g lim`, configure `LIM_API_KEY`
- [ ] Run `lim ios create --xcode --reuse-if-exists`
- [ ] Run `lim xcode build .` — verify build succeeds
- [ ] Run `lim ios screenshot ./hello.png` — capture proof
- [ ] Run `lim ios element-tree` — verify accessibility tree shows our text
- [ ] Attach screenshot + Signed Stream URL to PR
- [ ] Document any issues with the build pipeline in the PR description

**Why Sprint 0 matters:**
- Proves Devin can write Swift code and get it compiled without a Mac
- Validates the Limrun integration before we invest in feature development
- Catches Xcode project configuration issues early (signing, SDK targets, etc.)
- Establishes the PR deliverable format for all future sprints

> **The rest of the sprints remain the same (Sprint 1-4),** but every sprint now includes testing artifacts in each PR.

---

## 14. Revised Sprint Plan (with Testing Built In)

### Sprint 1 (Week 1-2): Foundation + Auth + Session List

**Deliverable:** App that authenticates and shows a list of sessions.

PR deliverables for each task:
- Screenshot of LoginView with fields visible
- Screenshot of session list with mock data
- Integration test video: real API key → real session list

Tasks:

- [ ] Xcode project setup (SwiftUI, iOS 17+, Swift 6)
- [ ] Set up `MockURLProtocol` test infrastructure
- [ ] Define `Session`, `PaginatedResponse`, `Message`, `Playbook` Codable models
- [ ] Build `DevinAPIClient` with async/await + generic request method
- [ ] Build `KeychainService` for secure credential storage
- [ ] Build `AuthenticationService` for Face ID / Touch ID via `LAContext`
- [ ] `LoginView` — API key + org ID text fields, "Connect" button, validation via `GET /v3/self`
- [ ] `BiometricUnlockView` — Face ID prompt on cold launch
- [ ] `SessionListView` — paginated list with pull-to-refresh
- [ ] `SessionRowView` — status badge (color-coded), prompt preview, time ago, ACUs
- [ ] Status filter bar (All / Running / Waiting / Finished / Error)
- [ ] Navigation via `NavigationStack` with `.navigationDestination`
- [ ] App icon and launch screen (Devin branding)
- [ ] Unit tests: API client (all mock scenarios), Keychain CRUD, model decoding
- [ ] UI test: Login → session list flow (mock API)
- [ ] Integration test: Login with real key → verify session list loads

### Sprint 2 (Week 3-4): Session Detail + Chat + Create

**Deliverable:** Full session lifecycle — view, chat, create, terminate.

PR deliverables for each task:
- Screenshot of session detail view
- Video of chat interaction (send message → Devin responds)
- Integration test video: create a real session, verify it appears

Tasks:

- [ ] `SessionDetailView` — header (status, ACUs, time), PR links, tags, category
- [ ] `SessionChatView` — message list with user/Devin message bubbles
- [ ] "Devin is working..." typing indicator (when `status_detail == "working"`)
- [ ] Send message input bar with send button
- [ ] `CreateSessionView` — prompt field, repo picker, playbook picker, mode toggle, tags
- [ ] Playbook list fetching and picker integration
- [ ] Swipe-to-terminate on session list
- [ ] Session detail → terminate button with confirmation
- [ ] Session archiving
- [ ] Error handling: network errors, 401 → re-auth, 429 → retry-after
- [ ] Empty states and loading skeletons
- [ ] Settings view — account info, masked API key display, logout
- [ ] Unit tests: message parsing, create session request body, pagination cursors
- [ ] UI test: Full chat flow with mock API
- [ ] Integration test: Create session → send message → verify response

### Sprint 3 (Week 5-6): Notifications + Widgets

- [ ] Background App Refresh registration (`BGAppRefreshTask`)
- [ ] Local notification scheduling on session status transitions
- [ ] Notification actions: "View Session", "Send Message"
- [ ] WidgetKit: `ActiveSessions` widget (small + medium)
- [ ] Timeline provider that fetches session counts
- [ ] Deep link from widget tap → session detail
- [ ] Tests: Notification trigger logic, widget timeline provider

### Sprint 4 (Week 7-8): Live Activities + Knowledge + Attachments

- [ ] Live Activity for tracked sessions (lock screen + Dynamic Island)
- [ ] Update Live Activity state via polling
- [ ] Knowledge notes list view
- [ ] Create/edit/delete knowledge notes
- [ ] Session attachments list + Quick Look preview
- [ ] Share attachment files via iOS share sheet
- [ ] Tests: Live Activity state updates, Knowledge CRUD

---

## 15. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| PATs remain in closed beta ([source](https://docs.devin.ai/api-reference/personal-access-tokens)) | Users must use service user keys (less intuitive for personal use) | In-app guided onboarding, clipboard detection for `cog_` tokens, deep link auth transfer from desktop |
| No webhook/push support from Devin API | Notifications delayed ~15-30 min when backgrounded | Local notifications for MVP (acceptable); optional remote push backend in Tier 4 if latency becomes a complaint |
| API rate limiting | Aggressive polling could hit 429s | Exponential backoff, adaptive polling intervals, local caching |
| App Store rejection | Apple may flag "developer tool" apps | Ensure rich UI, follow HIG, avoid "thin client" appearance |
| API breaking changes | v3 is current but could evolve | Version the API client, abstract behind protocol, monitor release notes |
| Multi-org complexity | Enterprise users have many orgs | Defer to Phase 3, design data model to support from day 1 |
| Limrun dependency | Single vendor for build/test pipeline | Fallback: GitHub Actions macOS runner for builds. Keep project buildable via `xcodebuild` directly (no Limrun lock-in). |
| No streaming API for messages | Can't show Devin "typing" in real-time | Typing indicator from session status + instant appearance on next poll (5s). See Section 12.4 note. |

---

## 16. Success Metrics

| Metric | Target (MVP) | Target (6 months) |
|---|---|---|
| Session list load time | < 1 second | < 500ms (with cache) |
| Time to create session | < 15 seconds | < 5 seconds (Siri/template) |
| Daily active users | Internal dogfooding | 500+ |
| App Store rating | N/A | 4.5+ |
| Crash-free rate | 99% | 99.9% |
| Notification delivery latency | ~15 min (local, backgrounded) / instant (foregrounded) | < 30 sec (with optional APNs relay) |

---

## 17. Summary: The Path from MVP to Vision

```
DAY   1-2   ██          Sprint 0: Hello Build (toolchain validation via Limrun)
WEEK  1-4   ██████████  MVP: Auth + Session List + Chat + Create
WEEK  5-8   ██████████  Notifications + Widgets + Live Activities + Knowledge
WEEK  9-14  ██████████  Siri + Share Sheet + Universal Links + Schedules
WEEK 15-20  ██████████  Analytics + Team View + Enterprise + Watch
WEEK 20+    ──────────  Offline mode, Remote push backend (optional), Voice, App Clip
```

The MVP is intentionally narrow: **authenticate, list sessions, view details, chat, create new sessions.** This covers the core loop that every Devin user needs on mobile. Everything else layers on top without rearchitecting.
