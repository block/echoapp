# AnalyticsDesktopPlugin

The AnalyticsDesktopPlugin is a real-time analytics monitoring tool that helps developers track and debug analytics events in their applications. It provides a structured view of analytics events with powerful filtering and search capabilities.


## Features

### 1. Real-Time Analytics Monitoring
- Live streaming of analytics events
- Buffer capacity of 2000 events for optimal performance
- Automatic event logging
- Chronological event tracking

### 2. Structured Event Display
The plugin provides a clear, tabular view of analytics events with the following columns:
- **Time**: Timestamp of the event (100px width)
- **Source**: Origin of the analytics event (80px width, filterable)
- **Event**: Name of the tracked event (300px width)
- **Properties**: Detailed event properties and parameters

### 3. Event Analysis Tools
- **Event Filtering**: Filter events by name or type
- **Search Functionality**: Search through event data
- **Detailed Inspection**: Click any event to view full details
- **Property Examination**: Inspect all event properties and metadata

### 4. Deep Linking Support
Access specific analytics views using deep links:
```
echo://plugin/com.echo.plugin.analytics/search?query=YourEventName
```

### 5. Interactive Features
- Real-time event monitoring
- Click events for detailed inspection
- Filter and search capabilities
- Customizable column widths

## Usage

### Basic Monitoring
1. Connect to your running application
2. Watch analytics events appear in real-time
3. Use the search bar to find specific events
4. Click on events to view detailed properties

### Event Analysis
- Filter events by name to track specific interactions
- Use the search functionality to find patterns
- Examine event properties for debugging
- Track event timing and sequence

### Tips for Effective Analysis
1. Use consistent event naming conventions
2. Monitor event frequency and patterns
3. Check event properties for accuracy
4. Use filters to focus on specific event types

## Integration with Development Workflow
The AnalyticsDesktopPlugin helps developers:
- Verify analytics implementation
- Debug tracking issues
- Monitor user interactions
- Validate event properties
- Ensure data quality

Perfect for:
- Analytics debugging
- Event validation
- Implementation verification
- Quality assurance testing
