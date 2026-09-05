# Key-Value Store Plugin

A desktop plugin for viewing and editing key-value stores like UserDefaults from iOS apps.

## Overview

The Key-Value Store plugin provides a comprehensive interface for viewing and managing key-value data from client applications. It automatically discovers and displays UserDefaults suites and other key-value stores, allowing developers to inspect, edit, and monitor changes in real-time.

## Features

### 🔍 **Store Discovery**
- Automatically discovers UserDefaults suites from client apps
- Displays custom icons and names for known store types
- Shows entry counts and read-only status

### 📊 **Data Viewing**
- Tabular view of all key-value pairs
- Support for multiple data types (String, Int, Bool, Date, Array, Dictionary, etc.)
- Search and filter functionality across keys and values
- Real-time updates when client app data changes

### ✏️ **Data Editing**
- Add, update, and delete key-value pairs
- Type-safe value editing with validation
- Conflict resolution for concurrent changes
- Undo/redo support for modifications

### 🔄 **Real-Time Monitoring**
- Live updates when client app modifies values
- Change history tracking with timestamps
- Visual indicators for recent modifications
- Automatic refresh capabilities

## Data Types Supported

| Type | Description | Example |
|------|-------------|---------|
| **String** | Text values | `"Hello World"` |
| **Integer** | Whole numbers | `42` |
| **Double** | Decimal numbers | `3.14159` |
| **Boolean** | True/false values | `true` |
| **Data** | Binary data | `<1234 bytes>` |
| **Date** | Date/time values | `Dec 9, 2025 at 2:30 PM` |
| **Array** | Lists of values | `[1, 2, 3]` |
| **Dictionary** | Key-value maps | `{"key": "value"}` |
| **URL** | Web addresses | `https://example.com` |

## User Interface

### Store List (Sidebar)
- Lists all discovered key-value stores
- Shows store icons, names, and entry counts
- Indicates read-only stores
- Search functionality

### Store Detail View
- Table view of all key-value pairs
- Sortable columns (Key, Value, Type, Last Modified)
- Inline editing capabilities
- Batch operations

### Toolbar Actions
- **Refresh**: Manually refresh store data
- **Add Entry**: Create new key-value pairs
- **Export**: Export store data to JSON/plist
- **Settings**: Configure plugin preferences

## Technical Details

### Communication Protocol
The plugin uses a bidirectional communication protocol with the client:

**Client → Desktop Events:**
- `updateSnapshot`: Complete data snapshot
- `error`: Error notifications
- `changeConfirmation`: Confirms desktop-initiated changes
- `changeConflict`: Reports conflicting modifications

**Desktop → Client Events:**
- `requestSnapshot`: Request current data
- `updateValue`: Modify existing value
- `deleteKey`: Remove key-value pair
- `addKey`: Create new entry
- `requestFullRefresh`: Force complete refresh

### Conflict Resolution
The plugin implements timestamp-based conflict resolution:
1. Desktop changes include timestamps
2. Client compares with local modification times
3. Conflicts are reported back to desktop
4. User can choose resolution strategy

### Performance
- Efficient diffing for large datasets
- Debounced change notifications
- Lazy loading for complex data types
- Memory-efficient data structures

## Development

### Plugin Structure
```
KeyValueStoreDesktopPlugin/
├── Plugin.swift              # Main plugin implementation
├── KeyValueStoreView.swift    # Primary UI view
├── KeyValueStoreViewModel.swift # Business logic and state
├── PluginInfo.plist          # Plugin metadata
└── README.md                 # This documentation
```

### Building
The plugin is automatically built as part of the Echo desktop application. It uses:
- SwiftUI for the user interface
- Combine for reactive data flows
- EchoPluginAPI for client communication
- EchoPluginUI for shared UI components

### Testing
- Unit tests for data models and business logic
- Integration tests for client-desktop communication
- UI tests for user interactions
- Performance tests for large datasets

## Troubleshooting

### Common Issues

**No stores appear in the sidebar:**
- Ensure client app is connected
- Check that client has KeyValueStore plugin enabled
- Verify network connectivity

**Changes don't persist:**
- Check if store is marked as read-only
- Verify client app permissions
- Look for error messages in the status bar

**Performance issues with large stores:**
- Use search/filtering to narrow results
- Consider exporting/importing data for bulk operations
- Check client app memory usage

### Debug Information
The plugin logs detailed information to the Echo console:
- Connection events
- Data synchronization
- Error conditions
- Performance metrics

## Version History

### 1.0.0
- Initial release with core functionality
- UserDefaults support
- Real-time monitoring
- Basic editing capabilities

## Related

- [EchoApp](../../../../../README.md)
- [EchoPluginAPI](../../../../../Sources/EchoPluginAPI/)
- [KeyValueStore Client Plugin](../../../../../Sources/OptionalPlugins/KeyValueStorePlugin/)
