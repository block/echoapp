# Crash Reporting Plugin - Agent Guide

## Overview

The Crash Reporting plugin displays crash reports captured from the connected mobile app. The Android counterpart (`CrashReportingPlugin` in echo-android) persists uncaught exceptions to disk and sends them as JSON-encoded `CrashReport` objects when the device reconnects to Echo.

## Plugin ID

- **Bundle ID**: `com.echo.plugin.crash-reporting`
- **Sanitized ID**: `crash-reporting`

## Data Format

Each incoming message is a JSON-encoded `CrashReport`:

```json
{
  "timestamp": 1710512000000,
  "exceptionClass": "java.lang.NullPointerException",
  "message": "Attempt to invoke virtual method on a null object reference",
  "stackTrace": "at com.example.MyActivity.onCreate(MyActivity.kt:42)\n...",
  "threadName": "main",
  "threadId": 1,
  "causeChain": [
    {
      "exceptionClass": "java.lang.IllegalStateException",
      "message": "Required value was null",
      "stackTrace": "at com.example.Repository.fetch(Repository.kt:15)\n..."
    }
  ]
}
```

## Architecture Notes

- Desktop plugin class: `CrashReportingDesktopPlugin` in `Plugin.swift`.
- `CrashReportingViewModel` holds `@Published crashReports` as `[CrashReport]`.
- Communication is unidirectional: the mobile client sends crash reports, the desktop plugin receives and displays them.
- Crash history persists across reconnects within a session (not cleared on disconnect).
- The view uses a custom SwiftUI `List` with `DisclosureGroup` for expandable stack traces, rather than `EchoTableView`, since stack traces are multi-line.
