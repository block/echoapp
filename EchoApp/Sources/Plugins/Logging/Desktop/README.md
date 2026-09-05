# LoggingDesktopPlugin

The LoggingDesktopPlugin is a real-time log monitoring tool that provides a structured view of application logs with powerful filtering and search capabilities. It helps developers track and debug application behavior through comprehensive log management.


## Features

### 1. Real-Time Log Monitoring
- Live streaming of application logs
- Maximum buffer of 2000 entries for optimal performance
- Automatic scrolling with new log entries
- Monospaced font for better log readability

### 2. Structured Log Display
- **Time**: Timestamp of log entries (100px width)
- **Level**: Log level indicator (50px width)
- **Priority**: Message priority (50px width)
- **Message**: Detailed log content (300px width)

### 3. Advanced Filtering
- Filter by log level
- Filter by priority
- Search within log messages
- Multiple filter combinations

### 4. Interactive Interface
- Click entries to view detailed information
- Column-based organization
- Adjustable column widths
- Clear visual hierarchy

### 5. Deep Linking Support
- Direct navigation to specific log searches
- URL-based filtering
- Integrated with application navigation

## Usage

### Basic Monitoring
1. Connect to your running application
2. Watch real-time logs appear in the structured table
3. Use column filters to focus on specific log levels or priorities

### Search and Filter
- Use the search bar to find specific log messages
- Filter by log level to focus on errors or debug information
- Combine filters for precise log analysis

### Deep Link Integration
Access specific log views using deep links:
```
echo://logging/search?query=your_search_term
```

## Tips for Effective Log Analysis
1. Use log levels appropriately to categorize messages
2. Utilize priority filters for critical issues
3. Combine search and filters for detailed debugging
4. Keep an eye on timestamp patterns for sequence analysis

## Integration with Development Workflow
- Monitor application behavior in real-time
- Debug issues with structured log information
- Track system events and user interactions
- Analyze application performance and errors