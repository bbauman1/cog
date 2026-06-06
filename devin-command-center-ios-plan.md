# Devin Command Center — Native SwiftUI iOS App

## Product Plan & Technical Architecture

---

## 1. Executive Summary

**Devin Command Center** is a native SwiftUI iPhone app that gives developers on-the-go control over their Devin AI sessions. Think of it as mission control for your AI engineer — monitor active sessions, spin up new work, chat with Devin, manage your knowledge base and playbooks, and get notified the instant Devin needs you or finishes a task.

The app is built on the [Devin API v3](https://docs.devin.ai/api-reference/overview) and designed to exploit native iOS capabilities (Live Activities, Widgets, push notifications, Siri, Shortcuts, biometrics) to deliver an experience that is impossible to replicate in a mobile browser.

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

This is the most critical design decision. The Devin API authenticates via bearer tokens — there is no OAuth2 flow for end-user login. We need to bridge this gap securely.

### 3.1 Recommended Approach: Hybrid Auth

**Phase 1 (MVP):** Direct API key entry + Keychain storage
- User pastes their `cog_` API key and org ID into the app.
- Key is stored in the iOS Keychain (encrypted, hardware-backed on devices with Secure Enclave).
- Protected behind Face ID / Touch ID for app unlock.
- Simple, works today, zero backend required.

**Phase 2:** QR-code pairing from Devin web dashboard
- Add a "Connect Mobile App" button to the Devin web UI that generates a time-limited QR code encoding `{ api_key, org_id, user_name }`.
- App scans QR code via `AVFoundation` camera → stores credentials in Keychain.
- Eliminates manual key entry and reduces copy-paste risk.

**Phase 3 (Long-term):** OAuth2 PKCE flow via Devin
- Once PATs are GA and/or Devin adds OAuth2 support, implement a proper Authorization Code + PKCE flow.
- `ASWebAuthenticationSession` handles the browser-based login natively.
- Refresh tokens stored in Keychain; access tokens auto-refreshed.
- This is the gold standard — no API key handling on the client at all.

### 3.2 Security Measures (All Phases)

| Layer | Implementation |
|---|---|
| Storage | iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| App lock | Require Face ID / Touch ID on every cold launch (via `LAContext`) |
| Transport | TLS 1.3 only; certificate pinning for `api.devin.ai` |
| Token display | Never show full token in UI; mask with `cog_••••••ab3f` |
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
| **Push Notifications** — session finished, error, waiting for user, PR created | Polling → local notification (or webhook → APNs if backend added) | `UNUserNotificationCenter`, rich notifications |
| **Home Screen Widgets** — active session count, latest session status | `GET /sessions` | WidgetKit (small, medium, large) |
| **Live Activities** — real-time session progress on lock screen | `GET /sessions/{id}` (poll) | ActivityKit + `LiveActivityAttributes` |
| **Session Attachments** — view/download files from sessions | `GET /sessions/{id}/attachments` | Quick Look, share sheet |
| **Knowledge Notes** — browse, create, edit, delete notes | `GET/POST/PUT/DELETE /knowledge/notes` | CRUD views with editor |

**Push Notification Architecture:**

Since the Devin API doesn't natively push to APNs, we have two options:

**Option A: Client-side polling + local notifications (no backend)**
- Background App Refresh polls every 15 minutes (iOS minimum).
- When app is foregrounded, poll every 5 seconds.
- Trigger `UNNotificationRequest` locally when status transitions are detected.
- Limitation: notifications are delayed when app is backgrounded.

**Option B: Lightweight backend relay (recommended for Tier 2)**
- Tiny server (e.g., Cloudflare Worker or AWS Lambda) polls Devin API per-user.
- On status change, sends APNs push via `apple/swift-nio` or AWS SNS.
- Device registers its push token with this relay on login.
- Enables true real-time notifications even when app is killed.

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

## 7. MVP Build Plan — Detailed Sprint Breakdown

### Sprint 1 (Week 1-2): Foundation + Auth + Session List

**Deliverable:** App that authenticates and shows a list of sessions.

- [ ] Xcode project setup (SwiftUI, iOS 17+, Swift 6)
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

### Sprint 2 (Week 3-4): Session Detail + Chat + Create

**Deliverable:** Full session lifecycle — view, chat, create, terminate.

- [ ] `SessionDetailView` — header (status, ACUs, time), PR links, tags, category
- [ ] `SessionChatView` — message list with user/Devin message bubbles
- [ ] Send message input bar with send button
- [ ] `CreateSessionView` — prompt field, repo picker, playbook picker, mode toggle, tags
- [ ] Playbook list fetching and picker integration
- [ ] Swipe-to-terminate on session list
- [ ] Session detail → terminate button with confirmation
- [ ] Session archiving
- [ ] Error handling: network errors, 401 → re-auth, 429 → retry-after
- [ ] Empty states and loading skeletons
- [ ] Settings view — account info, masked API key display, logout

### Sprint 3 (Week 5-6): Notifications + Widgets

- [ ] Background App Refresh registration (`BGAppRefreshTask`)
- [ ] Local notification scheduling on session status transitions
- [ ] Notification actions: "View Session", "Send Message"
- [ ] WidgetKit: `ActiveSessions` widget (small + medium)
- [ ] Timeline provider that fetches session counts
- [ ] Deep link from widget tap → session detail

### Sprint 4 (Week 7-8): Live Activities + Knowledge + Attachments

- [ ] Live Activity for tracked sessions (lock screen + Dynamic Island)
- [ ] Update Live Activity state via polling
- [ ] Knowledge notes list view
- [ ] Create/edit/delete knowledge notes
- [ ] Session attachments list + Quick Look preview
- [ ] Share attachment files via iOS share sheet

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

15. **Push notification backend** — Deploy lightweight relay (Cloudflare Worker / Lambda) that polls Devin API per-user and sends real APNs pushes. Eliminates background refresh delay.

16. **Voice session creation** — On-device speech-to-text (`SFSpeechRecognizer`) → directly submit as session prompt. "Record a task for Devin" workflow.

17. **Session templates** — Save frequently-used session configs (repo + playbook + tags + mode) as templates for one-tap creation.

18. **Haptic feedback language** — Distinct haptic patterns for different events: success (triple tap), error (buzz), waiting (gentle pulse).

19. **QR code pairing** — Camera-based onboarding: scan QR from Devin web dashboard to auto-configure credentials.

20. **App Clip** — Lightweight clip accessible via shared link. View a specific session's status without installing the full app.

---

## 9. Native iOS Capabilities Utilization Map

| iOS Capability | Where Used | Phase |
|---|---|---|
| **SwiftUI** | Entire UI layer | MVP |
| **Keychain Services** | API key + org ID storage | MVP |
| **LocalAuthentication** (Face ID / Touch ID) | App unlock | MVP |
| **URLSession async/await** | All API calls | MVP |
| **Pull-to-refresh** (`.refreshable`) | Session list, knowledge list | MVP |
| **Searchable** (`.searchable`) | Session list filtering | MVP |
| **NavigationStack** | App navigation | MVP |
| **WidgetKit** | Home screen session widgets | Tier 2 |
| **ActivityKit** (Live Activities) | Lock screen session tracking | Tier 2 |
| **UNUserNotificationCenter** | Local push notifications | Tier 2 |
| **Background App Refresh** | Polling when backgrounded | Tier 2 |
| **Quick Look** | Attachment preview | Tier 2 |
| **AppIntents** (Siri & Shortcuts) | Voice commands, automation | Tier 3 |
| **Share Extension** | Create session from any app | Tier 3 |
| **Core Spotlight** | Session search from home screen | Tier 3 |
| **Associated Domains** (Universal Links) | Open Devin URLs in-app | Tier 3 |
| **Swift Charts** | Analytics dashboard | Tier 4 |
| **SwiftData** | Offline cache | Tier 4 |
| **SFSpeechRecognizer** | Voice-to-prompt | Tier 4 |
| **WatchKit** | Apple Watch companion | Tier 4 |
| **AVFoundation** | QR code scanning | Tier 4 |

---

## 10. Tech Stack & Dependencies

| Layer | Choice | Rationale |
|---|---|---|
| UI Framework | SwiftUI (iOS 17+) | Declarative, native, Widgets/Activities support |
| Language | Swift 6 (strict concurrency) | Modern, safe, fast |
| Networking | `URLSession` + `async/await` | Zero deps, built-in, sufficient for REST |
| JSON | `Codable` + `JSONDecoder` | No third-party needed |
| Secure storage | Keychain Services (Security framework) | Hardware-backed encryption |
| Biometrics | LocalAuthentication (`LAContext`) | Face ID / Touch ID |
| State | `@Observable` (Observation framework) | Modern, less boilerplate than Combine |
| Navigation | `NavigationStack` + `NavigationPath` | Programmatic, type-safe |
| Image loading | `AsyncImage` (or Kingfisher if perf needed) | Built-in for MVP |
| Persistence | SwiftData (later phases for offline) | Native, iCloud-ready |
| Charts | Swift Charts (later phases) | Native, accessible |
| Testing | XCTest + Swift Testing | Built-in |
| CI/CD | Xcode Cloud or GitHub Actions + fastlane | Automated builds + TestFlight |

**Zero external dependencies for MVP.** Everything uses Apple-native frameworks. This keeps the binary small, avoids dependency risk, and aligns with App Store review preferences.

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

## 12. What to Build First

**Start with Sprint 1.** The single most important thing is:

> **A working session list that proves the API integration works end-to-end.**

Here's the exact first-day checklist:

1. `File → New Project → iOS App → SwiftUI → "DevinCommandCenter"`
2. Create `Session.swift` — Codable model matching the `SessionResponse` schema
3. Create `DevinAPIClient.swift` — generic `request<T>()` with bearer auth
4. Create `KeychainService.swift` — store/retrieve/delete API key
5. Create `LoginView.swift` — two text fields + connect button
6. Create `SessionListView.swift` — `List` of sessions with status badges
7. Wire it up: Login → validate via `GET /v3/self` → fetch sessions → display

Once you can see your real Devin sessions on your phone, everything else is incremental iteration.

---

## 13. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| PATs remain in closed beta | Users must use service user keys (less intuitive) | QR pairing flow makes service key entry seamless |
| No webhook/push support from Devin API | Real-time notifications require polling | Background refresh + lightweight relay backend (Tier 2) |
| API rate limiting | Aggressive polling could hit 429s | Exponential backoff, adaptive polling intervals, local caching |
| App Store rejection | Apple may flag "developer tool" apps | Ensure rich UI, follow HIG, avoid "thin client" appearance |
| API breaking changes | v3 is current but could evolve | Version the API client, abstract behind protocol, monitor release notes |
| Multi-org complexity | Enterprise users have many orgs | Defer to Phase 3, design data model to support from day 1 |

---

## 14. Success Metrics

| Metric | Target (MVP) | Target (6 months) |
|---|---|---|
| Session list load time | < 1 second | < 500ms (with cache) |
| Time to create session | < 15 seconds | < 5 seconds (Siri/template) |
| Daily active users | Internal dogfooding | 500+ |
| App Store rating | N/A | 4.5+ |
| Crash-free rate | 99% | 99.9% |
| Notification delivery latency | ~15 min (local) | < 30 sec (APNs relay) |

---

## 15. Summary: The Path from MVP to Vision

```
WEEK  1-4   ██████████  MVP: Auth + Session List + Chat + Create
WEEK  5-8   ██████████  Notifications + Widgets + Live Activities + Knowledge
WEEK  9-14  ██████████  Siri + Share Sheet + Universal Links + Schedules
WEEK 15-20  ██████████  Analytics + Team View + Enterprise + Watch
WEEK 20+    ──────────  Offline mode, Push backend, Voice, App Clip
```

The MVP is intentionally narrow: **authenticate, list sessions, view details, chat, create new sessions.** This covers the core loop that every Devin user needs on mobile. Everything else layers on top without rearchitecting.
