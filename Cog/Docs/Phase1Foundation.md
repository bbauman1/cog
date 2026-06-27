# Phase 1 Foundation Notes

## Preflight Build

- Date: 2026-06-27
- Command: `xcodebuild -project Cog/Cog.xcodeproj -scheme Cog -configuration Debug -destination generic/platform=iOS\ Simulator -derivedDataPath Cog/build/DerivedData/preflight-escalated build`
- Result: Succeeded under unsandboxed local Xcode execution.
- Existing warnings: the app icon asset catalog reports unassigned children.

## Wiki CRUD Pattern

Knowledge Notes and Playbooks share the same resource flow:

1. List screens load through an authenticated `DevinAPIClient`, show loading, empty, and error states, support pull-to-refresh, paginate at the end of the list, and confirm deletes before calling the API.
2. Detail screens show full content and metadata, expose edit and delete actions, and refresh their parent list after mutations.
3. Create/edit forms validate required title/name fields locally, show saving state, display API errors inline, and dismiss only after a successful API response.
4. Contract tests use `MockURLProtocol` to verify request paths, HTTP methods, encoded JSON bodies, and fixture decoding for Knowledge and Playbook API shapes.

## Phase 1 Information Architecture

The tab bar is:

- Sessions
- Wiki
- Automations
- Settings

Wiki routes to:

- Knowledge Notes
- Playbooks
