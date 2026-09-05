# Navigation Plugin

Visualizes the navigation stack of the connected mobile app in real-time, showing the current screen, backstack, and navigation metadata.

## Features

- **Current Screen Display**: Prominently shows the active screen with title, route, class name, and parameters
- **Backstack Visualization**: Lists all screens users can navigate back to, numbered in reverse order
- **Real-time Updates**: Receives immediate updates on navigation events (forward, back, finish)
- **Metadata**: Displays navigation flow type, timestamp, and total screen count

## Data Format

The mobile app should send `NavigationSnapshot` objects containing:

```json
{
  "currentScreen": {
    "id": "screen-uuid",
    "title": "Home",
    "route": "/home",
    "className": "HomeViewController",
    "parameters": {
      "userId": "123",
      "tab": "feed"
    },
    "timestamp": 1707736200000
  },
  "backstack": [
    {
      "id": "screen-uuid-2",
      "title": "Login",
      "route": "/login",
      "className": "LoginViewController",
      "parameters": null,
      "timestamp": 1707736100000
    }
  ],
  "navigationType": "push",
  "timestamp": 1707736200000
}
```

## Integration

### iOS

1. Track navigation events in your navigation coordinator or router
2. Create a `NavigationSnapshot` with the current screen and backstack
3. Send snapshots via Echo's `PluginConnection` whenever navigation changes

### Android

The Android implementation uses an event-driven listener pattern:

1. **BackStackEventProducer** (SandboxedScope): Manages listeners and broadcasts navigation changes
2. **BackStackEventListener**: Interface for components to receive backstack updates
3. **NavigationPlugin**: Implements the listener, receives `(backStack, currentScreen)` and sends snapshots to desktop
4. **BackStackManager Decorator**: Intercepts navigation events (`onNewScreen`, `onBack`, `onFinish`) and notifies the producer

The architecture ensures:
- Immediate notifications on all navigation events (no polling)
- Current screen is passed explicitly (not extracted from backstack)
- Plugin persists across activity recreations (SandboxedScope)
- Backstack contains only previous screens, current screen is separate

## Usage

1. Connect your mobile app with navigation tracking enabled
2. Navigate through your app - the plugin updates automatically in real-time
3. View the current screen card showing title, route, class name, and parameters
4. Review the backstack to see navigation history
5. Check metadata for navigation flow type and timestamps

## Notes

- This is a read-only visualization plugin
- The plugin displays snapshots sent from the mobile app - no navigation commands are sent back
- Parameters are displayed as key-value pairs for debugging
- Backstack is shown in reverse chronological order (most recent at top)
