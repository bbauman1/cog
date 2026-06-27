# Cog Master Plan v2 — API-First Mobile App

## What Changed from v1

The original plan was organized around iOS-native features (Live Activities, Siri, Widgets, Watch app). This revision **re-anchors the plan on what the Devin API actually supports today** and deprioritizes iOS-specific features (Live Activities, Siri, Watch, etc.) to a later phase.

**Key finding:** The Automations REST API (`/v3/organizations/{org_id}/automations`) is **not available** to service user API keys (returns 404). Automations are currently a web-only feature. We cannot build an automations tab until Cognition exposes a public API. Schedules, however, work fine and are the API-accessible subset of automations.

---

## API Surface — Confirmed Working (Tested Live)

| Domain | Base Path | Operations | Status |
|---|---|---|---|
| **Auth** | `/v3/self` | Verify credentials | Working |
| **Sessions** | `/v3/organizations/{org_id}/sessions` | List, get, create, terminate, archive, messages (list + send), attachments (list + upload) | Working |
| **Session Insights** | `/v3/organizations/{org_id}/sessions/{id}/insights` | Get insights (analysis, timeline, issues, action items, suggested prompts, session size) | Working |
| **Insights Generate** | `.../insights/generate` | Trigger on-demand analysis | Working |
| **Knowledge Notes** | `/v3/organizations/{org_id}/knowledge/notes` | Full CRUD (list, create, update, delete) + folders, enable/disable, pinned_repo | Working |
| **Playbooks** | `/v3/organizations/{org_id}/playbooks` | Full CRUD (list, create, get, update, delete) | Working |
| **Schedules** | `/v3/organizations/{org_id}/schedules` | Full CRUD (list, create, update, delete) with frequency, playbook, tags, enabled toggle | Working |
| **Secrets** | `/v3/organizations/{org_id}/secrets` | List metadata, create, delete (values never returned) | Working |
| **Metrics** | `/v3/organizations/{org_id}/metrics/sessions` | Aggregated session metrics (ACUs, counts by origin/size, PR merge counts). Max 100-day window. | Working |
| **Repositories** | `/v3beta1/organizations/{org_id}/repositories` | List repos with indexing status | Working |
| **Attachments** | `/v3/organizations/{org_id}/attachments` | Upload files (multipart) | Working |
| **Automations** | `/v3/organizations/{org_id}/automations` | N/A | **404 — Not available** |
| **Enterprise** | `/v3/enterprise/*` | Orgs, members, audit logs, billing | Requires enterprise admin PAT |

---

## Current App State — What Already Exists

| Feature | Status | Notes |
|---|---|---|
| Login (API key + org ID → Keychain) | Built | Basic single-screen flow; Apple-style onboarding and Face ID not yet implemented |
| Session List (paginated, pull-to-refresh, status filter) | Built | Has category filter, origin filter |
| Session Detail + Chat (messages, send) | Built | Has copy-on-tap, input bar on suspended |
| Create Session (prompt, repo picker, playbook picker, mode, tags, attachments) | Built | Full-featured |
| Terminate / Archive Session | Built | Swipe actions + buttons |
| Playbook List (picker for session creation) | Built | Read-only, used in create flow |
| Knowledge List (browse) | Built | Read-only list |
| Repository List (picker) | Built | Search + recent repos |
| Attachment Upload | Built | Camera + photo library |
| Settings (account info, logout) | Built | Basic |
| Home Screen Widget | Built | Active sessions widget |
| Background Refresh | Built | BGAppRefreshTask polling |
| Speech-to-Text | Built | Dictation for message input |

**Not yet built:** Apple-style onboarding, Knowledge CRUD, Playbook CRUD, Schedules, Secrets, Analytics/Metrics, Session Insights, Tab-based navigation, Face ID lock.

---

## Stack-Ranked Priority List

### P0 — Core App Completeness (Foundation for everything else)

These make the app feel like a real Devin command center, not just a session viewer.

#### P0.0: Execution Prep & API Contracts

**Why:** Before adding CRUD surfaces, confirm the current app builds, the test harness exists, and the API request/response shapes match the models. This prevents Phase 1 from getting derailed by pre-existing build failures or small contract mismatches like `title/body` vs. `name/instructions`.

**Tasks:**
1. Run a preflight build on the current app and record whether any failures are pre-existing
2. Confirm or create an XCTest target with a reusable mock `URLProtocol`
3. Validate Knowledge and Playbook API shapes against real responses or captured fixtures
4. Align model and request naming before UI work begins
5. Define a shared CRUD UI pattern for Library resources: loading, empty, error, saving, delete confirmation, refresh after mutation
6. Lock the Library information architecture for Phase 1: Library → Knowledge Notes, Library → Playbooks

**Verification:**
- Preflight build result is recorded before implementation changes
- XCTest/mock API harness can run at least one smoke test
- Knowledge and Playbook fixtures decode successfully
- Shared CRUD states are documented and reused by both resource areas

**Estimate:** 1 task (small)

---

#### P0.1: Tab Bar Navigation

**Why:** The app currently renders `SessionListView()` as the only screen. Adding tabs is the prerequisite for the primary app areas, but Knowledge and Playbooks do not need dedicated tabs. They are reusable Devin resources, so they should live together behind a single Library hub rather than competing with Sessions and Schedules in the tab bar.

**Tasks:**
1. Add `TabView` in `MainTabView` with tabs: Sessions, Library, Schedules, Settings
2. Create placeholder views for each tab
3. Add `LibraryHubView` with navigation rows for Knowledge Notes and Playbooks
4. Add SF Symbol icons and tab labels
5. Persist selected tab across app launches

**Verification:**
- Limrun build → screenshot each tab
- Verify Library hub can navigate to Knowledge Notes and Playbooks
- Verify tab selection persists after backgrounding

**Estimate:** 1 task (small)

---

#### P0.2: Knowledge Notes — Full CRUD

**Why:** Knowledge is how users teach Devin patterns. Mobile CRUD lets you create/edit notes on the go (e.g., "Always use pnpm in this repo"). The API is fully available.

**API endpoints:**
- `GET /v3/organizations/{org_id}/knowledge/notes` (already wired)
- `POST .../knowledge/notes` — create (name, body, trigger, folder_id, is_enabled, pinned_repo)
- `PUT .../knowledge/notes/{note_id}` — update
- `DELETE .../knowledge/notes/{note_id}` — delete

**Tasks:**
1. Add `KnowledgeListView` reachable from `LibraryHubView`
2. Add "New Note" button → `CreateKnowledgeView` (name, trigger, body fields; optional pinned_repo picker, enabled toggle)
3. Add note detail view with edit capability → `EditKnowledgeView`
4. Add swipe-to-delete with confirmation
5. Wire up `DevinAPIClient` methods: `createKnowledge()`, `updateKnowledge()`, `deleteKnowledge()`
6. Add pull-to-refresh and pagination

**Verification:**
- Unit test: mock API → verify create/update/delete calls send correct JSON
- Limrun build → screenshot: list, create form, edit form, delete confirmation
- End-to-end: create a note via app → verify it appears in web dashboard

**Estimate:** 3-4 tasks (medium)

---

#### P0.3: Playbooks — Full CRUD

**Why:** Playbooks are reusable instruction sets. Creating/editing on mobile is valuable — you can refine a playbook right after a session that didn't go well.

**API endpoints:**
- `GET /v3/organizations/{org_id}/playbooks` (already wired)
- `POST .../playbooks` — create (title, body)
- `GET .../playbooks/{playbook_id}` — get single
- `PUT .../playbooks/{playbook_id}` — update
- `DELETE .../playbooks/{playbook_id}` — delete

**Tasks:**
1. Add `PlaybookListView` reachable from `LibraryHubView`
2. Add "New Playbook" button → `CreatePlaybookView` (title, body/instructions editor)
3. Add playbook detail view showing full instructions, with edit button
4. Add swipe-to-delete with confirmation
5. Wire up `DevinAPIClient` methods: `createPlaybook()`, `getPlaybook()`, `updatePlaybook()`, `deletePlaybook()`
6. Integrate with existing session creation flow (playbook picker already exists; add a "Manage Playbooks" path if it fits cleanly)

**Verification:**
- Unit test: mock API → verify CRUD calls
- Limrun build → screenshot: list, create, detail/edit, delete
- End-to-end: create playbook → use in session creation

**Estimate:** 3-4 tasks (medium)

---

### P1 — High-Value New Features

#### P1.1: Session Insights & Analytics

**Why:** This is the most compelling "power user" feature for mobile. The insights API returns rich AI-generated analysis: timeline of events, issues encountered, action items, suggested prompt improvements, and note usage feedback. The metrics API gives org-level stats. Together, they let you understand at a glance how Devin is performing.

**API endpoints:**
- `GET .../sessions/{devin_id}/insights` — session-level insights (analysis.timeline, analysis.issues, analysis.action_items, analysis.suggested_prompt, analysis.note_usage, session_size, num_messages)
- `POST .../sessions/{devin_id}/insights/generate` — trigger generation
- `GET .../metrics/sessions?time_after=X&time_before=Y` — org-level aggregated metrics (sessions_created_count, by_origin, by_size, merged_prs_count, avg_acus)

**Tasks:**
1. **Session Insights View** (in session detail):
   - Add "Insights" section/tab to session detail
   - Display: session size badge, message counts, timeline visualization
   - Display: issues list with impact descriptions
   - Display: action items
   - Display: suggested prompt improvements (diff-style original vs. suggested)
   - "Generate Insights" button for sessions without analysis
   - Model: `SessionInsights`, `InsightsAnalysis`, `InsightsTimeline`, `InsightsIssue`, `InsightsActionItem`, `InsightsSuggestedPrompt`

2. **Analytics Dashboard** (new tab or section in Settings):
   - Date range picker (constrained to 100-day max)
   - Summary cards: total sessions, merged PRs, avg ACU/session
   - Bar chart: sessions by origin (webapp, api, slack, etc.)
   - Bar chart: sessions by size (xs, s, m, l, xl)
   - Use Swift Charts framework

3. Wire up `DevinAPIClient` methods: `getSessionInsights()`, `generateSessionInsights()`, `getSessionMetrics()`

**Verification:**
- Unit test: mock API → verify insights model decoding
- Unit test: mock API → verify metrics model decoding with all fields
- Limrun build → screenshot: insights view with real data, analytics charts
- Verify "Generate Insights" triggers correctly and insights populate after generation

**Estimate:** 5-6 tasks (large)

---

#### P1.2: Schedules Management

**Why:** Schedules are the API-accessible part of automations. Users can manage recurring Devin sessions (e.g., daily code reviews, weekly dependency updates) from their phone. Full CRUD is available.

**API endpoints:**
- `GET /v3/organizations/{org_id}/schedules` — list
- `POST .../schedules` — create (name, prompt, frequency, schedule_type, agent, bypass_approval, playbook_id, tags, notify_on, scheduled_at)
- `PATCH .../schedules/{schedule_id}` — update (any field)
- `DELETE .../schedules/{schedule_id}` — delete

**Tasks:**
1. Add `ScheduleListView` tab showing all schedules with:
   - Name, frequency, enabled/disabled badge, last executed, error status
   - Enable/disable toggle (PATCH with `enabled` field)
2. Add `CreateScheduleView`:
   - Name, prompt, frequency picker (hourly/daily/weekly), schedule_type (recurring vs one-time)
   - Optional: playbook picker, tags, agent type (devin/data_analyst), `notify_on`
3. Add schedule detail view with edit capability
4. Add swipe-to-delete with confirmation
5. Model: `Schedule` struct matching API response
6. Wire up `DevinAPIClient` methods: `listSchedules()`, `createSchedule()`, `updateSchedule()`, `deleteSchedule()`

**Verification:**
- Unit test: mock API → verify CRUD calls
- Limrun build → screenshot: list (empty + populated), create form, detail, toggle
- End-to-end: create schedule → verify appears in web dashboard → delete

**Estimate:** 4-5 tasks (medium-large)

---

#### P1.3: Secrets Management

**Why:** View and manage org secrets from mobile. Useful for quickly checking what secrets exist, adding a new one, or cleaning up stale entries. Note: values are never returned by the API for security.

**API endpoints:**
- `GET /v3/organizations/{org_id}/secrets` — list (metadata: key, note, type, created_by, is_sensitive)
- `POST .../secrets` — create (key, value, type: cookie/key-value/totp, is_sensitive, note)
- `DELETE .../secrets/{secret_id}` — delete

**Tasks:**
1. Add `SecretsListView` (likely in Settings or its own section):
   - Show key name, note, type badge, created date
   - No values shown (API doesn't return them)
2. Add `CreateSecretView`:
   - Key name, value (secure text field), type picker, sensitivity toggle, optional note
3. Add swipe-to-delete with confirmation
4. Model: `Secret` struct
5. Wire up `DevinAPIClient` methods: `listSecrets()`, `createSecret()`, `deleteSecret()`

**Verification:**
- Unit test: mock API → verify create/delete
- Limrun build → screenshot: list, create form
- End-to-end: create secret → verify in web dashboard → delete

**Estimate:** 2-3 tasks (small-medium)

---

### P2 — Onboarding & Trust

**Why:** First launch should feel like a polished Apple-style setup experience, not a credential form. Cog needs to help users create or find the right Devin service-user API key, explain when an Organization ID is still needed, and build trust by being explicit that credentials stay on-device and all API traffic goes directly to Devin.

#### P2.1: Apple-Style Onboarding Flow

**Tasks:**
1. Replace the unauthenticated `LoginView` entry point with `OnboardingFlowView`
2. Add a welcome screen: "Welcome to Cog" and position Cog as a direct Devin mobile command center
3. Add an API key screen:
   - Explain Devin service users and API keys in plain language
   - Provide a public CTA to open `https://app.devin.ai`
   - Show steps: Settings → Devin API → Provision service user
   - Accept pasted or typed API key and validate it with `/v3/self`
4. Auto-detect Organization ID from `SelfResponse.orgId` after `/v3/self`
5. Add an Organization ID fallback screen only when `/v3/self` does not return `org_id`:
   - Ask the user to copy the Organization ID from the Devin API settings page
   - Explain that the copy button is beside the Organization ID on that page
6. Add a trust/privacy screen or inline trust panel:
   - "Your API key is saved in this device's iOS Keychain."
   - "Cog talks directly to the Devin API."
   - "Cog does not run a server, proxy your data, collect analytics, or send data anywhere except Devin."
   - "Cog is intended to become open source."
7. Add a brief success screen before entering the main app
8. Preserve clipboard API-key paste support from the existing login flow
9. Keep storing both API key and Organization ID in Keychain because all current organization-scoped API paths require `org_id`

**Verification:**
- Unit test: API-key validation succeeds and skips manual org ID when `/v3/self` returns `org_id`
- Unit test: API-key validation falls back to manual org ID when `/v3/self.org_id` is nil
- Unit test: final login still saves API key + org ID to Keychain and initializes `DevinAPIClient`
- Limrun build → screenshots for welcome, API key, org ID fallback, trust/privacy, and success screens
- Verify the external Devin CTA opens the browser
- Verify clipboard API-key paste still works
- Verify successful onboarding enters the main tab UI
- Privacy check: no analytics SDK, tracking endpoint, or non-Devin network call is introduced

**Notes:**
- Do not hardcode `https://app.devin.ai/org/bbauman1/settings/devin-api` as the public CTA because that URL is org-specific. It can remain an internal reference/example for development only.
- OAuth2 remains blocked until Cognition exposes an OAuth2 provider; this phase stays API-key based.

**Estimate:** 2-3 tasks (medium)

---

### P3 — Polish & Enhanced UX

#### P3.1: Session Detail Enrichment

**Why:** The session detail view already works, but the API returns much richer data than we currently display. Enhance it incrementally.

**Tasks:**
1. Display `structured_output` when present (formatted JSON or key-value pairs)
2. Display `subcategory` alongside category
3. Display `user_id` (who started it) and `service_user_id`
4. Display child/parent session links (navigate to child/parent sessions)
5. Add "Resume" action for suspended sessions (sending a message auto-resumes)
6. Add session attachments list view (files attached to the session)
7. Display PR links with state badges (open/merged/closed) and tap-to-open in browser

**Verification:**
- Limrun build → screenshot before/after for each enrichment
- Verify child session navigation works with real data
- Verify PR link opens correctly in browser

**Estimate:** 3-4 tasks (medium)

---

#### P3.2: Face ID / Biometric Lock

**Why:** Security feature called out in the original plan. The app stores API keys in Keychain — adding Face ID on launch is table stakes for a security-conscious mobile app.

**Tasks:**
1. Add `LAContext` biometric check on app cold launch
2. Add toggle in Settings to enable/disable
3. Show lock screen overlay when app returns from background (if enabled)

**Verification:**
- Cannot fully test biometrics in simulator (Limrun), but can verify the code compiles and the toggle appears in Settings
- Manual testing on physical device (future)

**Estimate:** 1-2 tasks (small)

---

#### P3.3: Multi-Account Support

**Why:** Users may have keys for multiple orgs. Currently the app supports one credential set.

**Tasks:**
1. Store multiple (apiKey, orgId, label) tuples in Keychain
2. Add account picker in Settings
3. Switch `DevinAPIClient` credentials when switching accounts
4. Show active account indicator in the tab bar or header

**Verification:**
- Limrun build → screenshot: account list, picker, switch
- Verify switching accounts refreshes all data

**Estimate:** 2-3 tasks (medium)

---

### P4 — iOS Platform Features (Deprioritized)

These are valuable but depend on the core features being solid first.

| Feature | Why Deprioritized | Prerequisite |
|---|---|---|
| **Live Activities** | Requires ActivityKit, complex polling, iOS 16.1+ only | P0 complete, stable polling |
| **Siri & Shortcuts (AppIntents)** | Nice-to-have, complex to implement well | P0 + P1 complete |
| **Share Sheet Extension** | Requires app extension, separate build target | P0 complete |
| **Spotlight Search** | Requires CoreSpotlight indexing | Session list working well |
| **Universal Links** | Requires Associated Domains + AASA file on devin.ai (we can't control this) | N/A — may never be possible |
| **Apple Watch** | Entirely separate target, WatchKit | Everything else done |
| **iPad Layout** | NavigationSplitView adaptation | All features working on iPhone |
| **Home Screen Widgets (enhanced)** | Already have basic widget; can enhance later | P0 + P1 done |

---

### P5 — Blocked / Future (Needs API Changes)

| Feature | Blocker | What We Need |
|---|---|---|
| **Automations Browser** | `/v3/.../automations` returns 404 | Cognition to expose automations REST API |
| **Enterprise Analytics** | Requires enterprise admin PAT | Enterprise customer use case |
| **Audit Log Viewer** | Enterprise-only endpoint | Enterprise customer use case |
| **Real-time Push Notifications** | No webhook/SSE from Devin API | WebSocket or webhook callback from Devin |
| **OAuth2 Login** | No OAuth2 server exists | Cognition to build OAuth2 provider |
| **Team Member View** | Enterprise member list API | Enterprise admin PAT + v3 member endpoints |

---

## Execution Order — Concrete Task Sequence

Each task is sized and includes its verification method.

### Phase 1: Foundation (P0)

| # | Task | Size | Verification |
|---|---|---|---|
| 0 | Execution prep: preflight build, test harness, API contract fixtures, shared CRUD pattern | S | Baseline build result + XCTest/mock API smoke test + fixture decoding |
| 1 | Tab bar navigation (Sessions, Library, Schedules, Settings) + Library hub for Knowledge/Playbooks | S | Limrun build + screenshots of all tabs + Library routes |
| 2 | Knowledge: API client methods (create, update, delete) | S | Unit tests with mock URLProtocol |
| 3 | Knowledge: Library-routed list view, detail view, create/edit forms, delete | M | Limrun build + screenshots + e2e create/verify |
| 4 | Playbook: API client methods (get single, create, update, delete) | S | Unit tests with mock URLProtocol |
| 5 | Playbook: Library-routed list view, detail view, create/edit forms, delete | M | Limrun build + screenshots + e2e create/verify |

### Phase 2: Power Features (P1)

| # | Task | Size | Verification |
|---|---|---|---|
| 6 | Session Insights: models + API client (insights, generate) | S | Unit tests with mock data |
| 7 | Session Insights: UI in session detail (timeline, issues, action items, suggested prompt) | M | Limrun build + screenshots with real session data |
| 8 | Analytics: metrics models + API client | S | Unit tests with mock data |
| 9 | Analytics: dashboard view with Swift Charts (summary cards, origin bar chart, size bar chart) | M | Limrun build + screenshots |
| 10 | Schedules: models + API client (CRUD) | S | Unit tests |
| 11 | Schedules: list view, create, edit, delete, enable/disable toggle | M | Limrun build + screenshots + e2e |
| 12 | Secrets: models + API client (list, create, delete) | S | Unit tests |
| 13 | Secrets: list view + create form + delete (in Settings) | S | Limrun build + screenshots |

### Phase 3: Onboarding & Trust (P2)

| # | Task | Size | Verification |
|---|---|---|---|
| 14 | Onboarding auth flow foundation: validate API key with `/v3/self`, auto-detect `org_id`, preserve Keychain save path | S | Unit tests for `org_id` auto-detect, manual fallback, and final login save |
| 15 | Apple-style onboarding UI: welcome, API key, optional org ID, trust/privacy, success | M | Limrun build + screenshots + browser CTA + clipboard paste check |

### Phase 4: Polish (P3)

| # | Task | Size | Verification |
|---|---|---|---|
| 16 | Session detail enrichment (structured_output, child/parent links, attachments list, PR badges) | M | Limrun build + screenshots |
| 17 | Face ID / biometric lock | S | Limrun build (compile check + settings toggle screenshot) |
| 18 | Multi-account support | M | Limrun build + screenshots of account switcher |

### Phase 5: iOS Platform (P4) — Later

| # | Task | Size | Verification |
|---|---|---|---|
| 19 | Enhanced widgets (per-session widget, analytics widget) | M | Limrun build + widget gallery screenshot |
| 20 | Siri & Shortcuts (AppIntents for create session, check status) | M | Limrun build + Shortcuts app screenshot |
| 21 | Share Sheet extension | M | Limrun build + share sheet screenshot |
| 22 | Live Activities for active sessions | L | Limrun build + lock screen screenshot |
| 23 | Spotlight Search indexing | S | Limrun build |
| 24 | iPad adaptive layout | M | Limrun build (iPad sim) |

---

## Phase 1 Done Criteria

Phase 1 is complete when the app builds, tab selection persists, Library routes to Knowledge Notes and Playbooks, Knowledge CRUD works, Playbook CRUD works, the create-session playbook picker still works, and at least one CRUD path is verified through the mock API harness and/or an end-to-end API check.

---

## Verification Strategy Summary

| Method | When Used | How |
|---|---|---|
| **Preflight Build** | Before Phase 1 changes | Run the current build first and record whether any errors are pre-existing. |
| **API Contract Fixtures** | Before each CRUD surface | Capture or hand-author representative response/request fixtures and verify model decoding plus encoded payload shape. |
| **Unit Tests (URLProtocol mocks)** | Every new API client method and model | `XCTestCase` with mock `URLProtocol` returning fixture JSON. Run via `lim xcode build . --scheme Cog --configuration Debug` (tests are part of the build target). |
| **Limrun Builds** | Every PR / task completion | `cd Cog && lim xcode build . --scheme Cog --configuration Debug` — confirms compilation. |
| **Limrun Screenshots** | Every UI change | Build → launch in simulator → `lim ios screenshot <path>` to capture each screen state. |
| **Limrun Element Tree** | Verifying accessibility & element existence | `lim ios element-tree` to inspect what's on screen without visual screenshot. |
| **Limrun Tap** | End-to-end interaction testing | `lim ios tap-element --ax-label "Label"` to navigate through flows. |
| **End-to-End API Verification** | CRUD features (knowledge, playbooks, schedules, secrets) | Create resource via app → verify exists via `curl` to Devin API → delete. |
| **Screen Recordings** | Major feature milestones | Record Devin testing the full flow and share with user. |

---

## Architecture Notes

### Authentication Entry Point (Post-P2)

```
ContentView
    authState == .unknown           → ProgressView
    authState == .unauthenticated   → OnboardingFlowView
    authState == .authenticated     → MainTabView
```

`OnboardingFlowView` replaces `LoginView` for first launch. The existing `LoginView` remains useful as an implementation reference for clipboard paste, validation, Keychain persistence, and `AppState.login(apiKey:orgId:)`, but the user-facing unauthenticated experience should be the new onboarding flow.

The onboarding auth model:

1. User enters or pastes a Devin service-user API key
2. Cog calls `/v3/self` directly against the Devin API
3. If `SelfResponse.orgId` exists, Cog skips manual Organization ID entry
4. If `SelfResponse.orgId` is nil, Cog asks the user to copy the Organization ID from Devin API settings
5. Cog saves API key + Organization ID only in iOS Keychain and initializes `DevinAPIClient`

### Navigation Structure (Post-P0.1)

```
TabView {
    SessionsTab          // Existing SessionListView → SessionDetailView (+ Insights)
    LibraryTab           // LibraryHubView → KnowledgeListView / PlaybookListView
    SchedulesTab         // ScheduleListView → ScheduleDetailView / CreateScheduleView
    SettingsTab           // SettingsView (+ Secrets, Account Switcher, Biometrics toggle)
}
```

### Library Information Architecture

```
LibraryTab
    LibraryHubView
        Knowledge Notes
            KnowledgeListView → KnowledgeDetailView → Create/EditKnowledgeView
        Playbooks
            PlaybookListView → PlaybookDetailView → Create/EditPlaybookView
```

Secrets remain in Settings for Phase 1/2 unless the app later needs Library to become a broader resource center.

### Shared Resource CRUD Pattern

Knowledge Notes and Playbooks should share the same interaction model:

1. List screen with loading, empty, error, pull-to-refresh, pagination, and swipe-to-delete
2. Detail screen with full content, metadata, edit action, and delete action
3. Create/edit form with local validation, saving state, API error display, and refresh after mutation
4. Delete confirmation before destructive requests
5. Mock API coverage for encoded request bodies, decoded responses, and common failure states

### New Models Needed

```swift
// Schedules
struct Schedule: Codable, Identifiable, Sendable { ... }

// Secrets  
struct Secret: Codable, Identifiable, Sendable { ... }

// Session Insights
struct SessionInsights: Codable, Sendable { ... }
struct InsightsAnalysis: Codable, Sendable { ... }
struct InsightsTimeline: Codable, Sendable { ... }
struct InsightsIssue: Codable, Sendable { ... }
struct InsightsActionItem: Codable, Sendable { ... }
struct InsightsSuggestedPrompt: Codable, Sendable { ... }

// Metrics
struct SessionMetrics: Codable, Sendable { ... }
struct SessionCountsByOrigin: Codable, Sendable { ... }
struct SessionCountsBySize: Codable, Sendable { ... }
```

### API Client Additions

```swift
// Knowledge CRUD
func createKnowledge(name:body:trigger:folderId:isEnabled:pinnedRepo:) async throws -> KnowledgeNote
func updateKnowledge(noteId:name:body:trigger:) async throws -> KnowledgeNote
func deleteKnowledge(noteId:) async throws

// Playbook CRUD
func getPlaybook(playbookId:) async throws -> Playbook
func createPlaybook(title:body:) async throws -> Playbook
func updatePlaybook(playbookId:title:body:) async throws -> Playbook
func deletePlaybook(playbookId:) async throws

// Schedules CRUD
func listSchedules() async throws -> ScheduleListResponse
func createSchedule(...) async throws -> Schedule
func updateSchedule(scheduleId:...) async throws -> Schedule
func deleteSchedule(scheduleId:) async throws

// Secrets
func listSecrets() async throws -> PaginatedResponse<Secret>
func createSecret(key:value:type:isSensitive:note:) async throws -> Secret
func deleteSecret(secretId:) async throws

// Insights & Metrics
func getSessionInsights(devinId:) async throws -> SessionInsights
func generateSessionInsights(devinId:) async throws
func getSessionMetrics(timeAfter:timeBefore:) async throws -> SessionMetrics
```
