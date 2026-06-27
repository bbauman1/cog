# Phase 2 Power Features Notes

## Scope

Implemented Phase 2 / P1 from `cog-master-plan-v2.md`:

- Session Insights models, API methods, and a Chat / Insights switch in session detail.
- Analytics dashboard in Settings with date-range selection, summary metrics, and Swift Charts bar charts.
- Schedules tab with list, create/edit form, detail view, enable/disable action, and delete confirmation.
- Secrets in Settings with metadata list, create form, and delete confirmation. Secret values remain hidden after creation.

## API Notes

- `getSessionMetrics(timeAfter:timeBefore:)` sends `time_after` and `time_before` as Unix seconds. A live authenticated check returned HTTP 422 when ISO8601 timestamps were used.
- Insights decoders accept both compact string arrays and richer object arrays for timeline, issues, action items, suggested prompt, and note usage.
- Schedule list decoding accepts either a paginated object or a bare array, and handles live `scheduled_session_id` identifiers.
- Schedule creation sends cron expressions for `frequency`, defaults `scheduled_at` into the future, and uses Devin's accepted `notify_on` values: `always`, `failure`, or `never`.

## Verification

- Simulator build/run via XcodeBuildMCP succeeded.
- XCTest via XcodeBuildMCP succeeded: 18 passed, 0 failed.
- Authenticated UI checks:
  - Session detail loaded live Insights and successfully regenerated insights for an existing session.
  - Schedules tab loaded from the live API.
  - Created temporary schedule `Codex Test Schedule 2026-06-27`, verified it decoded into the list and opened detail with live schedule ID `sched-68824c58c3234a80aaa411bf5b0dae7d`, then deleted it and confirmed the list returned to the empty state.
  - Analytics loaded live metrics after switching metrics query parameters to Unix seconds.
  - Secrets loaded live metadata without exposing values.
  - Created temporary secret `CODEX_TEST_SECRET_20260627`, verified it appeared as metadata only, then deleted it through the row swipe action and confirmation alert.
