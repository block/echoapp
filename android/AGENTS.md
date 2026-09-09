# Adding a new client plugin

## Project structure

The codebase is organized into three product modules:

- `client/` - Core EchoClient implementation for making apps discoverable and managing connections
- `plugin-api/` - Plugin APIs and built-in plugins (analytics, logging, networking, accessibility, etc.)
- `sample/` - Sample Android app demonstrating Echo integration with Jetpack Compose UI

Build-only KSP processors live under `build-support/sealed-swift-compat/`.
They keep the public build self-contained and must not be published as EchoApp
runtime dependencies.

All Kotlin source files are located under `src/main/java/` and tests under `src/test/java/` following standard Android conventions.

## Plugin Development

When creating new plugins:
1. Define sealed interfaces for client and desktop events with `@JsonClass` annotations
2. Implement `ClientPlugin` or `BufferedClientPlugin` interface
3. Use `pluginIdentifier` that matches the desktop plugin exactly (case-sensitive)
4. Handle connection lifecycle in `onConnect()` with provided `CoroutineScope`
5. Use `connection.send()` for events and `connection.onEventReceived()` for receiving

Use the built-in plugins in `plugin-api/src/main/java/xyz/block/echoapp/plugin/` as implementation examples.

# Code style conventions and code formatting tasks

## Formatting code

To format code (required before committing):

```bash
./gradlew ktfmtFormat
```

To simply check formatting without changing anything:

```bash
./gradlew ktfmtCheck
```

CI runs the same Gradle tasks: `./gradlew build ktfmtCheck test`.

## Coding style & naming conventions

- **Formatter:** ktfmt with Google style, max width 103 characters
- **Indentation:** 2 spaces (enforced by ktfmt)
- **Naming:** Standard Kotlin conventions - camelCase for functions/properties, PascalCase for classes
- **Coroutines:** All async operations use Kotlin coroutines with proper scope management
- **JSON serialization:** Moshi with `@JsonClass(generateAdapter = true, generator = "sealed-swift-compat")` for cross-platform compatibility

Always run `./gradlew ktfmtFormat` before committing to ensure consistent formatting across the codebase.

# Keep rules and README.md up to date

When project structure, dependencies, plugins, or guidelines are changed: check if any `AGENTS.md` content is stale, or if anything needs to be added. 
Also check if `README.md` needs any updates.

# Test guidelines and how to run tests

## Running tests

To run tests, execute this Gradle task:

```bash
./gradlew test --continue
```

## Testing guidelines

- **Framework:** JUnit 4 with Truth assertions and [Turbine](https://github.com/cashapp/turbine) for Flow testing
- **Test location:** Tests mirror source structure under `src/test/java/`
- **Coroutines testing:** Use `kotlinx-coroutines-test` for testing suspend functions
- **Plugin debug logging:** Use `EchoDebugLoggerRule` JUnit rule to capture plugin logs in tests
