---
name: swiftui-conventions
description: SwiftUI coding conventions for the Cog iOS app. Enforces accessibility and style rules for buttons, labels, and other UI components.
---

# SwiftUI Conventions

## Icon-Only Buttons

**Never** use a bare `Image` as a `Button` label. Always use a `Label` with `.labelStyle(.iconOnly)` instead. This ensures every button has accessible text for VoiceOver while still rendering as icon-only visually.

Bad:
```swift
Button {
    doSomething()
} label: {
    Image(systemName: "gearshape")
}
```

Good:
```swift
Button {
    doSomething()
} label: {
    Label("Settings", systemImage: "gearshape")
        .labelStyle(.iconOnly)
}
```

For dynamic icons, put the accessible title in the `Label` and remove any redundant `.accessibilityLabel`:

```swift
Button {
    toggleMic()
} label: {
    Label(isRecording ? "Stop dictation" : "Start dictation",
          systemImage: isRecording ? "mic.fill" : "mic")
        .labelStyle(.iconOnly)
}
```

Style modifiers (`.font`, `.foregroundStyle`, `.symbolEffect`, etc.) go directly on the `Label`, just as they would on an `Image`.
