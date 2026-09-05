# CrashReportingDesktopPlugin

Displays crash reports captured from a connected mobile app. The Android counterpart persists uncaught exceptions to disk and sends them as JSON-encoded `CrashReport` objects when the device reconnects to Echo.

## Features

- Real-time crash report display as they arrive from the connected device
- Expandable stack traces with monospaced formatting
- Full cause chain display for chained exceptions
- Crash history persists across reconnects within a session
- Clear button to dismiss viewed reports

## Data Model

Each crash report contains:
- **timestamp** — when the crash occurred (milliseconds since epoch)
- **exceptionClass** — the exception type (e.g., `NullPointerException`)
- **message** — optional exception message
- **stackTrace** — full stack trace string
- **threadName** / **threadId** — the thread where the crash occurred
- **causeChain** — optional array of chained cause exceptions
