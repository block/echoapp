import ArgumentParser
import Foundation

struct PluginsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plugins",
        abstract: "List and inspect installed EchoApp desktop plugins.",
        subcommands: [
            ListPluginsCommand.self,
            PluginInfoCommand.self,
        ],
        defaultSubcommand: ListPluginsCommand.self
    )
}

// MARK: - List

struct ListPluginsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all installed desktop plugins.",
        discussion: """
            Use --format agent to output a concise skill-tree summary designed for \
            AI agent consumption. This format describes what each plugin captures, \
            how to query its data via echoapp, and what fields are available -- \
            without requiring the agent to explore plugin internals.
            """
    )

    enum Format: String, ExpressibleByArgument {
        case text
        case json
        case agent
    }

    @Option(name: .long, help: "Output format: text, json, or agent.")
    var format: Format = .text

    func run() throws {
        let catalog = PluginCatalog.scan()

        if catalog.plugins.isEmpty {
            switch format {
            case .json:
                print("[]")
            case .agent:
                print("# EchoApp Plugins")
                print("")
                print("No plugins installed.")
            case .text:
                print("No plugins found in ~/Library/Application Support/Echo/Plugins/")
            }
            return
        }

        switch format {
        case .json:
            let output: [[String: Any]] = catalog.plugins.map { plugin in
                var entry: [String: Any] = [
                    "sanitized_id": plugin.sanitizedID,
                    "bundle_identifier": plugin.bundleIdentifier,
                    "display_name": plugin.displayName,
                    "path": plugin.bundleURL.path,
                    "has_agents_md": plugin.agentsMarkdown != nil,
                ]
                if let version = plugin.version {
                    entry["version"] = version
                }
                if let desc = plugin.pluginDescription {
                    entry["description"] = desc
                }
                return entry
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)

        case .text:
            for plugin in catalog.plugins.sorted(by: { $0.displayName < $1.displayName }) {
                let versionStr = plugin.version.map { " v\($0)" } ?? ""
                let docsStr = plugin.agentsMarkdown != nil ? " [docs]" : ""
                print("  \(plugin.displayName)\(versionStr)\(docsStr)")
                print("    ID: \(plugin.sanitizedID)")
                print("    Bundle: \(plugin.bundleIdentifier)")
                if let desc = plugin.pluginDescription {
                    print("    Description: \(desc)")
                }
                print("")
            }

        case .agent:
            printAgentFormat(catalog: catalog)
        }
    }

    // MARK: - Agent Format

    private func printAgentFormat(catalog: PluginCatalog) {
        let sorted = catalog.plugins.sorted { $0.displayName < $1.displayName }

        print("""
        # EchoApp Plugins

        Echo captures live debug data from connected iOS/Android devices.
        Each plugin captures a specific category of data. Use the CLI commands
        below to inspect, query, and stream plugin data without opening the GUI.

        ## CLI reference

        ```
        echoapp status                              # session info (add --format json for structured output)
        echoapp tail <plugin-id>                     # last 10 entries from a plugin
        echoapp tail <plugin-id> -l 50               # last 50 entries
        echoapp tail <plugin-id> -f                  # follow live (like tail -f)
        echoapp query <plugin-id>                    # query with filters (outputs one JSON object per line)
        echoapp query <plugin-id> --last 5m          # entries from the last 5 minutes
        echoapp query <plugin-id> --last 1h --limit 100
        echoapp query <plugin-id> --format compact   # one-line summaries instead of full JSON
        echoapp plugins info <plugin-id>             # full AGENTS.md documentation for a plugin
        ```

        ### Plugin-specific query filters

        ```
        echoapp query network --url /api/v2          # filter by URL substring
        echoapp query network --method POST          # filter by HTTP method
        echoapp query network --status 500           # filter by HTTP status code
        echoapp query analytics --event AppNavigate  # filter by analytics event name
        echoapp query logging --level error          # filter by log level (error, warning, info, debug)
        ```

        ### Example output

        `echoapp query network --last 5m --limit 2`:
        ```json
        {"plugin_id":"network","timestamp":"2025-01-15T10:30:00Z","data":{"url":"https://api.example.com/2.0/example/get-profile","method":"GET","statusCode":200,"duration_ms":142}}
        {"plugin_id":"network","timestamp":"2025-01-15T10:30:01Z","data":{"url":"https://api.example.com/2.0/example/get-balance","method":"GET","statusCode":200,"duration_ms":89}}
        ```

        `echoapp query analytics --event AppNavigate --limit 1`:
        ```json
        {"plugin_id":"analytics","timestamp":"2025-01-15T10:30:05Z","data":{"columnItems":[{"key":"Event","value":"AppNavigate"},{"key":"Source","value":"native"}]}}
        ```

        `echoapp tail logging -l 1`:
        ```json
        {"plugin_id":"logging","timestamp":"2025-01-15T10:30:10Z","data":{"level":"error","message":"Failed to fetch config","subsystem":"com.example.app"}}
        ```

        ## Installed plugins

        """.components(separatedBy: "\n").map { line in
            // Remove leading whitespace from heredoc indentation
            let trimmed = line.drop(while: { $0 == " " })
            return String(trimmed)
        }.joined(separator: "\n"))

        for plugin in sorted {
            print("<plugin>")
            print("  <name>\(plugin.displayName)</name>")
            print("  <id>\(plugin.sanitizedID)</id>")
            if let desc = plugin.pluginDescription {
                print("  <description>\(desc)</description>")
            }

            // Extract purpose and data contract from AGENTS.md if available
            if let agents = plugin.agentsMarkdown {
                let summary = extractAgentSummary(from: agents)
                if !summary.isEmpty {
                    print("  <summary>")
                    for line in summary {
                        print("    \(line)")
                    }
                    print("  </summary>")
                }
            }

            // CLI usage
            print("  <cli>")
            print("    echoapp tail \(plugin.sanitizedID) -l 20")
            print("    echoapp tail \(plugin.sanitizedID) -f")
            print("    echoapp query \(plugin.sanitizedID) --last 5m")
            if let agents = plugin.agentsMarkdown {
                let filters = extractQueryFilters(from: agents, pluginID: plugin.sanitizedID)
                for filter in filters {
                    print("    echoapp query \(plugin.sanitizedID) \(filter)")
                }
            }
            print("  </cli>")

            if plugin.agentsMarkdown != nil {
                print("  <docs>echoapp plugins info \(plugin.sanitizedID)</docs>")
            }
            print("</plugin>")
            print("")
        }
    }

    /// Extracts the Purpose and Data Contract sections from an AGENTS.md file
    /// into a compact summary for inline display.
    private func extractAgentSummary(from markdown: String) -> [String] {
        var lines: [String] = []
        let sections = ["## Purpose", "## Data Contract", "## Primary Raw Data"]
        let allLines = markdown.components(separatedBy: "\n")

        for section in sections {
            guard let startIdx = allLines.firstIndex(where: { $0.hasPrefix(section) }) else {
                continue
            }
            // Collect lines until next heading or end
            for i in (startIdx + 1)..<allLines.count {
                let line = allLines[i]
                if line.hasPrefix("## ") { break }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }
        }
        return lines
    }

    /// Extracts query filter hints from an AGENTS.md "## CLI Filters" section.
    /// Each non-empty line under that heading (until the next ## heading) is
    /// returned as a filter string. This keeps filter docs co-located with
    /// each plugin rather than hardcoded in the CLI.
    private func extractQueryFilters(from markdown: String, pluginID: String) -> [String] {
        let allLines = markdown.components(separatedBy: "\n")
        guard let startIdx = allLines.firstIndex(where: { $0.hasPrefix("## CLI Filters") }) else {
            return []
        }
        var filters: [String] = []
        for i in (startIdx + 1)..<allLines.count {
            let line = allLines[i]
            if line.hasPrefix("## ") { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                filters.append(trimmed)
            }
        }
        return filters
    }
}

// MARK: - Info

struct PluginInfoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show detailed info about an installed plugin."
    )

    @Argument(help: "Plugin name or ID (e.g., 'analytics', 'KeyValueStore', or full bundle ID).")
    var plugin: String

    func run() throws {
        let catalog = PluginCatalog.scan()

        guard let found = catalog.resolve(plugin) else {
            print("Plugin '\(plugin)' not found.")
            print("")
            print("Available plugins:")
            for p in catalog.plugins.sorted(by: { $0.displayName < $1.displayName }) {
                print("  \(p.displayName) (\(p.sanitizedID))")
            }
            throw ExitCode.failure
        }

        print("Plugin: \(found.displayName)")
        print("ID: \(found.sanitizedID)")
        print("Bundle: \(found.bundleIdentifier)")
        print("Path: \(found.bundleURL.path)")
        if let version = found.version {
            print("Version: \(version)")
        }
        if let desc = found.pluginDescription {
            print("Description: \(desc)")
        }

        if let agents = found.agentsMarkdown {
            print("")
            print("--- AGENTS.md ---")
            print(agents)
        } else {
            print("")
            print("No AGENTS.md documentation found for this plugin.")
        }
    }
}
