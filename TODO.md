# Devin Command Center — Master TODO

> Living backlog for the iOS app. Items are ordered by priority within each phase.
> Mark items `[x]` as completed. Add new items as needed.

---

## Sprint 0: Hello Build (Toolchain Validation)

- [x] Create SwiftUI project targeting iOS 26 / Swift 6
- [x] Set up `.xcodeproj` (committed directly, XcodeGen `project.yml` as reference)
- [x] Build successfully via `lim xcode build .`
- [x] App runs on Limrun cloud iOS Simulator
- [x] Capture screenshot as proof
- [x] Limrun API key stored as Devin org secret
- [x] Environment blueprint configured (`npm install -g lim`)

---

## Sprint 1: Foundation + Auth + Session List (Week 1-2)

**Goal:** App authenticates with Devin API and shows a live session list.

### Infrastructure & Models

- [ ] Set up `MockURLProtocol` test infrastructure for deterministic unit tests
- [ ] Define Codable models: `Session`, `PaginatedResponse`, `Message`, `Playbook`, `Knowledge`, `Schedule`
- [ ] Build `DevinAPIClient` — generic async/await request method, error handling, pagination
- [ ] Build `KeychainService` — store/retrieve/delete API key + org ID securely
- [ ] Build `AuthenticationService` — Face ID / Touch ID via `LAContext`
- [ ] Adaptive polling service (5s foreground, 30s+ inactive)

### Views

- [ ] `LoginView` — API key + org ID text fields, "Connect" button, clipboard detection for `cog_` prefix
- [ ] `LoginView` — validation via `GET /v3/self`, error states (invalid key, network error)
- [ ] `BiometricUnlockView` — Face ID/Touch ID prompt on cold launch
- [ ] `SessionListView` — paginated list with pull-to-refresh (`.refreshable`)
- [ ] `SessionRowView` — status badge (color-coded SF Symbol), prompt preview, time ago, ACU count
- [ ] Status filter bar: All / Running / Waiting / Finished / Error
- [ ] `Tab(role: .search)` — searchable session list via Liquid Glass search tab
- [ ] `NavigationStack` with `.navigationDestination` for session detail routing
- [ ] App icon and launch screen (Devin branding)
- [ ] Liquid Glass tab bar with sessions + settings tabs
- [ ] `.tabBarMinimizeBehavior(.onScrollDown)` for session list scrolling

### Testing (Sprint 1)

- [ ] Unit tests: API client (happy path, 401, 429, timeout, malformed JSON)
- [ ] Unit tests: Keychain CRUD operations
- [ ] Unit tests: Model decoding (all session states)
- [ ] UI test: Login → session list flow (mock API)
- [ ] Integration test: Login with real API key → verify session list loads
- [ ] Screenshot: LoginView with fields visible
- [ ] Screenshot: Session list with data
- [ ] Video: Full login → session list flow

---

## Sprint 2: Session Detail + Chat + Create (Week 3-4)

**Goal:** Full session lifecycle — view details, chat with Devin, create new sessions, terminate.

### Views

- [ ] `SessionDetailView` — header with status, ACUs, time, PR links, tags, category
- [ ] `SessionChatView` — message list with user/Devin bubbles, timestamps
- [ ] "Devin is working..." typing indicator (when `status_detail == "working"`)
- [ ] `.navigationSubtitle()` showing current session status
- [ ] Send message input bar with send button
- [ ] `CreateSessionView` — prompt field, repo picker, playbook picker, mode toggle, tags
- [ ] Playbook list fetching and selection
- [ ] Session termination — swipe-to-terminate on list + button in detail with confirmation alert
- [ ] Session archiving
- [ ] `SettingsView` — account info, masked API key, org name, logout button
- [ ] Error handling: network errors, 401 → re-auth flow, 429 → retry-after display
- [ ] Empty states for all views (no sessions, no messages)
- [ ] Loading skeletons / shimmer placeholders
- [ ] Sheet morphing (`.glassEffectID()`) for list → detail transitions

### Testing (Sprint 2)

- [ ] Unit tests: message parsing, create session request body, pagination cursors
- [ ] Unit tests: session state machine transitions
- [ ] UI test: Full chat flow with mock API (send → receive → display)
- [ ] Integration test: Create session → send message → verify response
- [ ] Screenshot: Session detail view
- [ ] Video: Chat interaction (send message → Devin responds on next poll)
- [ ] Video: Create session → appears in list

---

## Sprint 3: Notifications + Widgets (Week 5-6)

**Goal:** Know when Devin needs you even when the app is backgrounded.

- [ ] Background App Refresh registration (`BGAppRefreshTask`)
- [ ] Polling service that runs during background refresh
- [ ] Local notification scheduling on session status transitions
  - [ ] `waiting_for_user` → "Devin needs your input" notification
  - [ ] `finished` → "Session complete" notification
  - [ ] `error` → "Session failed" notification
- [ ] Notification actions: "View Session", "Send Message" (quick reply)
- [ ] Notification tap deep-links to specific session
- [ ] WidgetKit: `ActiveSessions` widget (small: count, medium: top 3 sessions)
- [ ] Timeline provider that fetches session data
- [ ] Widget deep link → session detail
- [ ] Widget configuration intent (filter by status)

### Testing (Sprint 3)

- [ ] Unit tests: Notification trigger logic, background refresh scheduling
- [ ] Unit tests: Widget timeline provider
- [ ] Screenshot: Widget on home screen
- [ ] Integration test: Session finishes → local notification fires

---

## Sprint 4: Live Activities + Knowledge + Attachments (Week 7-8)

**Goal:** Lock screen awareness + knowledge/playbook management.

- [ ] Live Activity for actively tracked sessions (lock screen + Dynamic Island)
- [ ] Live Activity state updates via polling (status, latest message preview)
- [ ] "Track this session" toggle in session detail
- [ ] Knowledge notes list view (paginated, searchable)
- [ ] Create/edit/delete knowledge notes
- [ ] Knowledge note detail editor
- [ ] Session attachments list
- [ ] Quick Look preview for attachments (`.quickLookPreview()`)
- [ ] Share attachments via iOS share sheet
- [ ] Playbook list + detail view (read-only initially, then CRUD)

### Testing (Sprint 4)

- [ ] Unit tests: Live Activity state update logic
- [ ] Unit tests: Knowledge CRUD operations
- [ ] Screenshot: Live Activity on lock screen
- [ ] Video: Track session → see updates on lock screen
- [ ] Integration test: Create/edit/delete knowledge note via real API

---

## Phase 2: Power User Features (Post-MVP)

> Each item below is ~1-2 weeks of work. Prioritize based on user feedback after MVP launch.

- [ ] **Siri Shortcuts** — `AppIntents` for "Create Devin Session", "Check Status", "List Active"
- [ ] **Share Extension** — share URL/text from any app → create Devin session
- [ ] **Universal Links** — register `app.devin.ai` domain, deep link into app
- [ ] **Spotlight indexing** — `CSSearchableItem` for session search from home screen
- [ ] **Schedule management** — visual cron builder (day/time picker), toggle on/off
- [ ] **Automation browser** — read-only view of configured automations, enable/disable toggle
- [ ] **WebView** (native SwiftUI iOS 26) — preview Devin session web URLs in-app
- [ ] **Rich TextEditor** (AttributedString) — formatted prompt composition
- [ ] **Section index labels** — alphabetical jump for Knowledge notes list

---

## Phase 3: Team & Org Features

- [ ] **Multi-org support** — org switcher, per-org credentials in Keychain
- [ ] **Team activity feed** — all sessions across org, filter by team member
- [ ] **ACU analytics dashboard** — Swift Charts: daily burn rate, trends, category breakdown
- [ ] **PR integration** — surface PRs from sessions, one-tap open in GitHub Mobile
- [ ] **Audit log viewer** (enterprise) — searchable trail, filter by action/user/date
- [ ] **Foundation Models integration** — on-device LLM for session summaries, smart search, prompt suggestions
- [ ] **Voice session creation** — `SpeechRecognizer` (on-device) → dictate task for Devin

---

## Phase 4: Advanced & Experimental

- [ ] **Apple Watch companion** — complication (active count), haptic alerts, quick terminate
- [ ] **iPad multi-column layout** — `NavigationSplitView`, keyboard shortcuts (Cmd+N, Cmd+R)
- [ ] **Offline mode** — SwiftData cache, queue messages for send on reconnect
- [ ] **Remote push notifications** — Cloudflare Worker relay, real APNs push (<30s latency)
- [ ] **Session templates** — save configs (repo + playbook + tags + mode) for one-tap creation
- [ ] **Haptic feedback language** — distinct patterns: success (triple tap), error (buzz), waiting (pulse)
- [ ] **Cross-device credential transfer** — Apple universal clipboard or `devincommand://auth?token=...&org=...`
- [ ] **App Clip** — lightweight session status viewer accessible via shared link

---

## Infrastructure & Maintenance (Ongoing)

- [ ] Set up SwiftLint (lint on every PR)
- [ ] GitHub Actions CI: build + test on macOS runner (backup to Limrun)
- [ ] TestFlight distribution for beta testing
- [ ] App Store listing preparation (screenshots, description, keywords)
- [ ] Privacy policy and terms of service
- [ ] App Store submission

---

## Design Principles (Reference)

- **iOS 26 Liquid Glass everywhere** — tab bars, toolbars, floating buttons, sheets use `.glassEffect()`
- **SF Symbols 7** — all icons are system symbols with draw-on animations
- **Follow Devin mobile web UX** — same information architecture, native expression
- **5-second polling in foreground** — adaptive (slow down when inactive)
- **Optimistic UI** — messages appear instantly, confirm on next poll

---

*Last updated: Sprint 0 complete (June 2026)*
