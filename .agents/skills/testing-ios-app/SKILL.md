---
name: testing-ios-app
description: Test the Devin Command Center iOS app end-to-end using Limrun simulator. Use when verifying UI changes, auth flows, or session list behavior.
---

# Testing the iOS App via Limrun

## Devin Secrets Needed

- `LIM_API_KEY` — Limrun API key for cloud Xcode builds and simulator access
- (Optional) A Devin API key for integration testing the full auth → session list flow

## Build & Launch

```bash
cd /home/ubuntu/research/DevinCommandCenter
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

## Key Testing Patterns

### Login Screen Validation
1. Verify Connect button is disabled initially (`enabled: false` in element-tree)
2. Type invalid key (no `cog_` prefix) → button stays disabled
3. Type valid `cog_` key + org ID → button becomes enabled
4. Tap Connect with fake credentials → error message appears in red

### Verifying Error Messages
After triggering an error, wait ~3 seconds then check:
```bash
lim ios element-tree | grep -i "error\|invalid\|insufficient"
```

The Devin API returns:
- 401 → "Invalid or expired API key"
- 403 → "Insufficient permissions"
- 429 → "Rate limited. Please try again later."

### TextFields
TextFields in SwiftUI often have `AXLabel: null` — use coordinates from the element tree's `frame` field to tap them. The AXValue shows the placeholder text or current content.

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
