---
name: testing-ios-app
description: Test the Devin Command Center iOS app end-to-end using Limrun simulator. Use when verifying UI changes, auth flows, or session list behavior.
---

# Testing the iOS App via Limrun

## Devin Secrets Needed

- `LIM_API_KEY` — Limrun API key for cloud Xcode builds and simulator access
- `DEVIN_API_KEY` — Devin API key for integration testing (service user with org `org-ef33adaca3a84b72839816853d18d23f`)

## Build & Launch

```bash
cd /home/ubuntu/repos/research/DevinCommandCenter
lim xcode build . --scheme DevinCommandCenter --configuration Debug --ios
```

The `--ios` flag creates a simulator-backed instance, builds, and installs the app automatically.

## Interacting with the Simulator

### Screenshots
```bash
lim ios screenshot output.png
```

### Inspect UI (Accessibility Tree)
```bash
lim ios element-tree
```
Returns JSON with all UI elements including:
- `AXLabel` — text label (use for `tap-element`)
- `AXValue` — current value (for text fields, shows placeholder when empty)
- `enabled` — whether element is interactive
- `frame` — coordinates for tap-by-position
- `traits` — includes "NotEnabled", "Button", "Link", "TextEntry", etc.

### Tap Elements
```bash
# By accessibility label:
lim ios tap-element --ax-label "Connect"

# By coordinates (when label is null, e.g. TextFields):
lim ios tap 201 410
```

### Type Text
```bash
lim ios type "cog_test_key_12345"
```
Types into the currently focused text field.

**IMPORTANT:** `lim ios type` inserts text at the UIKit layer but does NOT trigger SwiftUI `@Binding` updates. After using `lim ios type`, you MUST follow up with `lim ios press-key space` (or another key) to force the binding to sync. Without this, buttons that depend on text field content (e.g. "Create" button checking `isFormValid`) will remain disabled even though the text is visible in the field.

### Select All + Replace
```bash
lim ios press-key a --modifier command   # Select all
lim ios type "new_text"                   # Replaces selected text
```

### Press Keys
```bash
lim ios press-key enter
lim ios press-key backspace
lim ios press-key a --modifier command  # Cmd+A
```

### Swipe Gestures (for swipe actions on list rows)
There is no `lim ios swipe` command. Use `lim ios perform` with touch gestures:
```bash
lim ios perform \
  --action type=touchDown,x=350,y=248 \
  --action type=wait,durationMs=100 \
  --action type=touchMove,x=200,y=248 \
  --action type=wait,durationMs=50 \
  --action type=touchMove,x=100,y=248 \
  --action type=wait,durationMs=50 \
  --action type=touchUp,x=100,y=248
```
Adjust x/y coordinates based on the row position from `lim ios element-tree`.

### Scrolling
```bash
lim ios scroll up
lim ios scroll down
lim ios scroll left
lim ios scroll right
lim ios scroll down --amount 500  # Custom scroll amount in pixels
```

## Key Testing Patterns

### Login Flow
1. Take screenshot to verify login screen is showing
2. Use `lim ios element-tree` to find text field coordinates (TextFields have `AXLabel: null`)
3. Tap API Key field → `lim ios type "${DEVIN_API_KEY}"`
4. Tap Org ID field → `lim ios type "org-ef33adaca3a84b72839816853d18d23f"`
5. Dismiss keyboard: `lim ios press-key enter`
6. Tap Connect button (verify it's enabled first via element-tree)
7. Wait ~2s → dismiss "Save Password?" dialog if it appears (tap "Not Now")
8. Verify session list loads with real sessions

### Session Detail & Chat
1. Tap a session row to navigate to detail view
2. Verify nav title shows session name, ellipsis menu button in top-right
3. Check for chat messages (blue = user, gray = Devin) or "No messages yet" empty state
4. If session is active: message input bar should be visible at bottom
5. Send a message: tap input field, type text + `press-key space`, tap send button
6. Verify optimistic message appears immediately as blue bubble
7. Verify "Devin is working..." typing indicator appears when session is working

### Create Session
1. Tap "+" button in top-right of session list
2. Verify Create Session sheet with Cancel/Create buttons
3. Verify Create button is DISABLED when prompt is empty
4. Type prompt text + `press-key space` to trigger binding
5. Verify Create button becomes ENABLED
6. Tap Create → sheet dismisses, new session appears in list

### Terminate Session
- **Via swipe:** Use `lim ios perform` touch gestures to swipe left on active session row
- **Via menu:** Tap ellipsis (⋯) button in detail view → Terminate Session
- Both show confirmation alert: "Terminate Session?" with Cancel/Terminate

### Settings
1. Tap Settings tab
2. Verify: masked API key (e.g. `cog_----477q`), org ID, auth type, version/build
3. Tap "Log Out" → confirmation alert with Cancel/Log Out

### Toolbar Buttons
Toolbar buttons (Cancel, Create, ellipsis menu) may NOT appear in `lim ios element-tree`. Use coordinates from screenshots to tap them. Typical positions:
- Cancel button: ~(55, 100)
- Create button: ~(338, 100)
- Ellipsis menu: ~(365, 83)
- Back button: ~(37, 83)

## Cleanup

Always delete Limrun instances when done:
```bash
lim ios list          # See active instances
lim ios delete <id>   # Clean up
lim xcode list        # See Xcode targets  
lim xcode delete <id> # Clean up
```

## Known Limitations

- Face ID/Touch ID cannot be tested programmatically via Limrun
- The Devin API may return 403 (not 401) for invalid tokens — both are handled correctly
- Session list testing requires a valid Devin API key to reach the authenticated state
- Simulator runs remotely, so desktop screen recording won't capture it — use `lim ios screenshot` for evidence instead
- `lim ios type` does NOT sync SwiftUI bindings — always follow with `lim ios press-key` to force sync
- Toolbar buttons are not always in the accessibility element tree — use coordinate-based taps
- There is no `lim ios swipe` command — use `lim ios perform` with touchDown/touchMove/touchUp
