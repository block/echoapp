# Debug Menu Plugin

View and control the connected app's debug menu remotely. Toggle feature flags, switch API environments, trigger debug actions, and set custom values — all without touching the device.

## Features

- **Toggle switches**: Enable/disable feature flags, debug overlays, and other boolean settings
- **Picker controls**: Switch between environments (Production, Staging, Dev), select configurations
- **Action buttons**: Trigger one-shot operations like clearing caches, resetting state, or forcing syncs
- **Text inputs**: Set custom API URLs, override values, or enter debug parameters
- **Search**: Filter debug menu items by name, description, or tags
- **CLI commands**: All debug menu operations are available via `echoapp debugmenu` for agent automation

## CLI Commands

```bash
# List all debug menu items
echoapp debugmenu list

# Filter by section, search, or type
echoapp debugmenu list --section "Feature Flags"
echoapp debugmenu list --search "checkout"
echoapp debugmenu list --type toggle

# Toggle a feature flag
echoapp debugmenu set-toggle enable-new-checkout --on

# Select a picker option (zero-based index)
echoapp debugmenu select api-env 1

# Execute a debug action
echoapp debugmenu execute clear-cache

# Set a text input value
echoapp debugmenu set-text custom-api-url "https://staging.example.com"
```
