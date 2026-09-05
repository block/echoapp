import ArgumentParser
import DebugMenuPluginAPI
import EchoConnection
import Foundation

// MARK: - DebugCommand

struct DebugCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debugmenu",
        abstract: "View and control the connected app's debug menu.",
        discussion: """
            Interact with the debug menu of a connected mobile app. Discover what \
            knobs exist, read their current value, and flip them — all from the \
            command line. Designed for both humans and agents.

            Discovery is progressive:
              • `list` with no argument prints just the sections.
              • `list <section>` expands one section into a table of items.
              • `find <query>` searches across id / alias / title / description.
              • `describe <id|alias>` returns the full record for one item,
                including the exact mutate command to run.

            Items can be addressed by either their full id (slugified breadcrumb \
            like `Features_Example-Feature`) or by an author-supplied `alias` \
            (short handle like `example-feature`). All mutation subcommands accept \
            either.

            Mutation subcommands (set-toggle, select, execute, set-text) require \
            a live `echoapp connect` session.

            EXAMPLES:
                echoapp debugmenu list
                echoapp debugmenu list Features
                echoapp debugmenu find moneybot
                echoapp debugmenu describe example-feature
                echoapp debugmenu set-toggle example-feature --on
                echoapp debugmenu select API-Environment_API-Endpoint 1
                echoapp debugmenu execute Remote-Configurations_Feature-Eligibility_Reset-Feature-Eligibility-Cache
            """,
        subcommands: [
            DebugListCommand.self,
            DebugFindCommand.self,
            DebugDescribeCommand.self,
            DebugSetToggleCommand.self,
            DebugSelectCommand.self,
            DebugExecuteCommand.self,
            DebugSetTextCommand.self,
            DebugWatchCommand.self,
        ]
        // No `defaultSubcommand:` — when set, swift-argument-parser routes
        // `debugmenu --help` to the default subcommand's help, hiding the
        // mutation subcommands from agents that introspect via `--help`.
    )
}

// MARK: - List

struct DebugListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List sections, or expand one section into a table of items.",
        discussion: """
            With no argument, prints the section index (just titles + item counts) \
            so agents can pick which section to drill into. Pass a section title or \
            id to expand it.

            For free-text search, use `find <query>` instead.
            """,
    )

    @Argument(help: "Section title or id to expand. Omit to list section names.")
    var section: String?

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: DebugOutputFormat = .text

    @Flag(name: .long, help: "Request a fresh snapshot from the device before reading. Use when on-device mutations or restarts may have invalidated the cached snapshot.")
    var refresh: Bool = false

    func run() throws {
        let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: session)
        try assertDebugMenuPluginAvailable(at: sessionURL)
        if refresh {
            let jsonlURL = sessionJSONLURL(sessionURL)
            let preRequestOffset = currentFileSize(jsonlURL)
            try sendDebugEvent(.requestSnapshot, sessionID: session)
            if !awaitSnapshot(jsonlURL: jsonlURL, fromByteOffset: preRequestOffset, timeout: defaultAckTimeout) {
                FileHandle.standardError.write(
                    "Warning: requestSnapshot timed out — falling back to last cached snapshot.\n"
                        .data(using: .utf8)!,
                )
            }
        }
        guard let snapshot = try readLatestSnapshot(from: sessionURL) else {
            print("No debug menu data available. Make sure the connected app sends debug menu snapshots.")
            return
        }

        let sections = snapshot.sections

        if let section {
            guard let matched = findSection(matching: section, in: sections) else {
                print("No section matched '\(section)'. Run `echoapp debugmenu list` to see available sections.")
                throw ExitCode(1)
            }
            switch format {
            case .text: printSectionDetail(matched)
            case .json: try printJSON(["section": encodableAsAnyJSON(matched)])
            }
        } else {
            switch format {
            case .text: printSectionIndex(sections)
            case .json: try printJSON(["sections": sections.map(sectionSummary)])
            }
        }
    }

    private func findSection(matching query: String, in sections: [EchoDebugMenuSection]) -> EchoDebugMenuSection? {
        let q = query.lowercased()
        // Prefer exact id match, then exact title, then case-insensitive substring of either.
        if let exact = sections.first(where: { $0.id.lowercased() == q }) {
            return exact
        }
        if let exactTitle = sections.first(where: { $0.title.lowercased() == q }) {
            return exactTitle
        }
        return sections.first { s in
            s.id.lowercased().contains(q) || s.title.lowercased().contains(q)
        }
    }

    private func sectionSummary(_ section: EchoDebugMenuSection) -> [String: Any] {
        [
            "id": section.id,
            "title": section.title,
            "leaf_item_count": countLeafItems(in: section),
        ]
    }

    private func printSectionIndex(_ sections: [EchoDebugMenuSection]) {
        let summaries = sections.map { (id: $0.id, title: $0.title, count: countLeafItems(in: $0)) }
        guard !summaries.isEmpty else {
            print("No sections in current snapshot.")
            return
        }
        let titleWidth = max("SECTION".count, summaries.map { $0.title.count }.max() ?? 0)
        let header = "\(pad("SECTION", titleWidth))  ITEMS"
        print(header)
        print(String(repeating: "-", count: header.count))
        for row in summaries {
            let countStr = row.count == 1 ? "1 item" : "\(row.count) items"
            print("\(pad(row.title, titleWidth))  \(countStr)")
        }
        print("")
        print("Tip:")
        print("  echoapp debugmenu list <section>     expand one section")
        print("  echoapp debugmenu find <query>       search by id/alias/title/description")
        print("  echoapp debugmenu describe <id>      full record for one item")
    }

    private func printSectionDetail(_ section: EchoDebugMenuSection) {
        let rows = flattenLeaves(section: section)
        let countStr = rows.count == 1 ? "1 item" : "\(rows.count) items"
        print("\(section.title) (\(countStr))")
        print("")
        guard !rows.isEmpty else { return }
        printItemTable(rows)
        print("")
        print("Tip:")
        print("  echoapp debugmenu describe <id|alias>   full record + mutate command")
    }
}

// MARK: - Find

struct DebugFindCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Search items by id, alias, title, or description (case-insensitive substring).",
    )

    @Argument(help: "Query string. Substring-matched against id, alias, title, and description.")
    var query: String

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    @Option(name: .long, help: "Filter by item type: toggle, picker, action, textInput, info.")
    var type: String?

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: DebugOutputFormat = .text

    func run() throws {
        let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: session)
        try assertDebugMenuPluginAvailable(at: sessionURL)
        guard let snapshot = try readLatestSnapshot(from: sessionURL) else {
            print("No debug menu data available.")
            return
        }
        let q = query.lowercased()
        let typeFilter = type?.lowercased()
        var matches: [FlattenedItem] = []
        for section in snapshot.sections {
            for item in flattenLeaves(section: section) {
                if let typeFilter, item.typeName.lowercased() != typeFilter { continue }
                if itemMatches(item, query: q) {
                    matches.append(item)
                }
            }
        }
        switch format {
        case .text: printFindResults(matches, query: query)
        case .json: try printJSON(["query": query, "results": matches.map(\.json)])
        }
    }

    private func itemMatches(_ item: FlattenedItem, query: String) -> Bool {
        item.id.lowercased().contains(query)
            || (item.alias?.lowercased().contains(query) ?? false)
            || item.title.lowercased().contains(query)
            || (item.itemDescription?.lowercased().contains(query) ?? false)
            || item.tags.contains(where: { $0.lowercased().contains(query) })
    }

    private func printFindResults(_ matches: [FlattenedItem], query: String) {
        if matches.isEmpty {
            print("No items matched '\(query)'.")
            return
        }
        let label = matches.count == 1 ? "result" : "results"
        print("\(matches.count) \(label) for '\(query)':")
        print("")
        for item in matches {
            var header = "  \(item.id)"
            if let alias = item.alias {
                header += "  (alias: \(alias))"
            }
            print(header)
            let valuePart = valueDescription(item.type)
            let desc = item.itemDescription ?? item.title
            print("    \(item.typeName)  \(valuePart.isEmpty ? "" : "\(valuePart)  ")\(desc)")
        }
    }
}

// MARK: - Describe

struct DebugDescribeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Show the full record for one item, including the mutate command.",
    )

    @Argument(help: "Item id or alias.")
    var reference: String

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: DebugOutputFormat = .text

    func run() throws {
        let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: session)
        try assertDebugMenuPluginAvailable(at: sessionURL)
        guard let snapshot = try readLatestSnapshot(from: sessionURL) else {
            print("No debug menu data available.")
            throw ExitCode(1)
        }
        let resolved = try resolveReference(reference, in: snapshot)
        switch format {
        case .text: printDescribe(resolved)
        case .json: try printJSON(resolved.json)
        }
    }

    private func printDescribe(_ item: FlattenedItem) {
        let lines: [(String, String)] = [
            ("id", item.id),
            ("alias", item.alias ?? "-"),
            ("title", item.title),
            ("section", item.sectionTitle),
            ("type", item.typeName),
            ("current", valueDescription(item.type)),
            ("description", item.itemDescription ?? "(none — author should add one)"),
            ("tags", item.tags.isEmpty ? "(none)" : item.tags.joined(separator: ", ")),
        ]
        let labelWidth = lines.map { $0.0.count }.max() ?? 0
        for (label, value) in lines {
            print("\(pad(label + ":", labelWidth + 2)) \(value)")
        }
        if let mutate = mutateHint(for: item) {
            print("")
            print("To mutate:")
            print("  \(mutate)")
        }
    }

    private func mutateHint(for item: FlattenedItem) -> String? {
        let handle = item.alias ?? item.id
        switch item.type {
        case let .toggle(isOn):
            return "echoapp debugmenu set-toggle \(handle) --\(isOn ? "off" : "on")"
        case let .picker(options, _):
            return "echoapp debugmenu select \(handle) <0..\(max(options.count - 1, 0))>"
        case .action:
            return "echoapp debugmenu execute \(handle)"
        case .textInput:
            return "echoapp debugmenu set-text \(handle) <value>"
        case .info, .subsection:
            return nil
        }
    }
}

// MARK: - Set Toggle

struct DebugSetToggleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-toggle",
        abstract: "Set a debug menu toggle on or off. Accepts an id or alias.",
    )

    @Argument(help: "Item id or alias of the toggle.")
    var reference: String

    @Flag(name: .long, help: "Turn the toggle on.")
    var on: Bool = false

    @Flag(name: .long, help: "Turn the toggle off.")
    var off: Bool = false

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    func validate() throws {
        if !on && !off {
            throw ValidationError("Specify --on or --off.")
        }
        if on && off {
            throw ValidationError("Cannot use both --on and --off.")
        }
    }

    func run() throws {
        let resolved = try resolveItem(reference, sessionID: session)
        guard case .toggle = resolved.type else {
            throw DebugCommandError.sendFailed(
                "Item '\(resolved.id)' is a \(resolved.typeName), not a toggle. Use `echoapp debugmenu describe \(resolved.id)` to inspect.",
            )
        }
        try sendAndReport(
            event: .setToggle(itemId: resolved.id, isOn: on),
            item: resolved,
            sessionID: session,
            successMessage: "Toggle '\(resolved.id)' set to \(on ? "ON" : "OFF").",
        )
    }
}

// MARK: - Select Option

struct DebugSelectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "select",
        abstract: "Select an option from a picker. Accepts an id or alias.",
    )

    @Argument(help: "Item id or alias of the picker.")
    var reference: String

    @Argument(help: "Zero-based index of the option to select.")
    var index: Int

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    func validate() throws {
        guard index >= 0 else {
            throw ValidationError("Index must be non-negative.")
        }
    }

    func run() throws {
        let resolved = try resolveItem(reference, sessionID: session)
        guard case let .picker(options, _) = resolved.type else {
            throw DebugCommandError.sendFailed(
                "Item '\(resolved.id)' is a \(resolved.typeName), not a picker. Use `echoapp debugmenu describe \(resolved.id)` to inspect.",
            )
        }
        guard (0..<options.count).contains(index) else {
            throw DebugCommandError.sendFailed(
                "Index \(index) is out of range; picker has \(options.count) option(s) (valid: 0..<\(options.count)).",
            )
        }
        try sendAndReport(
            event: .selectOption(itemId: resolved.id, selectedIndex: index),
            item: resolved,
            sessionID: session,
            successMessage: "Picker '\(resolved.id)' set to index \(index).",
        )
    }
}

// MARK: - Execute Action

struct DebugExecuteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "execute",
        abstract: "Execute a debug menu action. Accepts an id or alias.",
    )

    @Argument(help: "Item id or alias of the action.")
    var reference: String

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    func run() throws {
        let resolved = try resolveItem(reference, sessionID: session)
        guard case .action = resolved.type else {
            throw DebugCommandError.sendFailed(
                "Item '\(resolved.id)' is a \(resolved.typeName), not an action. Use `echoapp debugmenu describe \(resolved.id)` to inspect.",
            )
        }
        // Actions can take longer (e.g. cache resets, network flushes); give
        // the device more headroom before reporting timeout.
        try sendAndReport(
            event: .executeAction(itemId: resolved.id),
            item: resolved,
            sessionID: session,
            successMessage: "Action '\(resolved.id)' executed.",
            timeout: 8.0,
        )
    }
}

// MARK: - Set Text

struct DebugSetTextCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-text",
        abstract: "Set a text-input value. Accepts an id or alias.",
    )

    @Argument(help: "Item id or alias of the text input.")
    var reference: String

    @Argument(help: "The text value to set.")
    var value: String

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    func run() throws {
        let resolved = try resolveItem(reference, sessionID: session)
        guard case .textInput = resolved.type else {
            throw DebugCommandError.sendFailed(
                "Item '\(resolved.id)' is a \(resolved.typeName), not a text input. Use `echoapp debugmenu describe \(resolved.id)` to inspect.",
            )
        }
        try sendAndReport(
            event: .setTextValue(itemId: resolved.id, value: value),
            item: resolved,
            sessionID: session,
            successMessage: "Text input '\(resolved.id)' set to \"\(value)\".",
        )
    }
}

// MARK: - Watch

struct DebugWatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Tail the connected device's debug menu and print changes as they happen.",
        discussion: """
            Streams `updateSnapshot`, `itemUpdated`, `actionCompleted`, and `error` \
            events from the active session's JSONL log. For snapshots, diffs \
            against the previous snapshot and only prints changed leaf items.

            Requires a live `echoapp connect` session. Press Ctrl-C to exit.
            """,
    )

    @Option(name: .long, help: "Session ID. Defaults to the current active session.")
    var session: String?

    @Option(name: .long, help: "How long to wait between polls, in milliseconds. Defaults to 100ms.")
    var pollMS: Int = 100

    func run() throws {
        let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: session)
        try assertDebugMenuPluginAvailable(at: sessionURL)
        let jsonlURL = sessionJSONLURL(sessionURL)
        // Start from end of file so we only report new events, not history.
        var offset = currentFileSize(jsonlURL)
        let decoder = clientEventDecoder()
        var previousSnapshot: EchoDebugMenuSnapshot?

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        print("Watching session at \(sessionURL.lastPathComponent) (Ctrl-C to exit)...")
        print("")

        let pollInterval = max(0.01, Double(pollMS) / 1000.0)
        while true {
            while let event = readNextMatchingEvent(
                jsonlURL: jsonlURL,
                fromByteOffset: &offset,
                decoder: decoder,
                predicate: { _ in true },
            ) {
                let stamp = formatter.string(from: Date())
                switch event {
                case let .updateSnapshot(snapshot):
                    printSnapshotDiff(prev: previousSnapshot, next: snapshot, stamp: stamp)
                    previousSnapshot = snapshot
                case let .itemUpdated(itemId, newType):
                    print("[\(stamp)] itemUpdated  \(itemId) -> \(valueDescription(newType))")
                case let .actionCompleted(itemId, success, message):
                    let status = success ? "ok" : "FAIL"
                    let detail = message.map { "  \($0)" } ?? ""
                    print("[\(stamp)] actionCompleted  \(itemId)  [\(status)]\(detail)")
                case let .error(message):
                    print("[\(stamp)] error  \(message)")
                }
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private func printSnapshotDiff(
        prev: EchoDebugMenuSnapshot?,
        next: EchoDebugMenuSnapshot,
        stamp: String,
    ) {
        let prevItems = prev.map(flattenAllItems) ?? [:]
        let nextItems = flattenAllItems(next)
        if prev == nil {
            print("[\(stamp)] updateSnapshot  (\(nextItems.count) leaf items)")
            return
        }
        let prevKeys = Set(prevItems.keys)
        let nextKeys = Set(nextItems.keys)
        let added = nextKeys.subtracting(prevKeys).sorted()
        let removed = prevKeys.subtracting(nextKeys).sorted()
        var changed: [(String, EchoDebugMenuItemType, EchoDebugMenuItemType)] = []
        for id in nextKeys.intersection(prevKeys) {
            if let p = prevItems[id], let n = nextItems[id], p != n {
                changed.append((id, p, n))
            }
        }
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            print("[\(stamp)] updateSnapshot  (no leaf changes)")
            return
        }
        print("[\(stamp)] updateSnapshot")
        for id in added { print("  +  \(id)") }
        for id in removed { print("  -  \(id)") }
        for (id, p, n) in changed.sorted(by: { $0.0 < $1.0 }) {
            print("  ~  \(id):  \(valueDescription(p))  ->  \(valueDescription(n))")
        }
    }

    private func flattenAllItems(_ snapshot: EchoDebugMenuSnapshot) -> [String: EchoDebugMenuItemType] {
        var out: [String: EchoDebugMenuItemType] = [:]
        for section in snapshot.sections {
            walk(section.items, into: &out)
        }
        return out
    }

    private func walk(_ items: [EchoDebugMenuItem], into out: inout [String: EchoDebugMenuItemType]) {
        for item in items {
            if case let .subsection(child) = item.type {
                walk(child.items, into: &out)
            } else {
                out[item.id] = item.type
            }
        }
    }
}

// MARK: - Output Format

enum DebugOutputFormat: String, ExpressibleByArgument {
    case text
    case json
}

// MARK: - Snapshot Helpers

private struct LatestSnapshot {
    let sections: [EchoDebugMenuSection]
}

/// Flattened representation of a leaf item: the typed item plus the title of
/// the top-level section it lives under (preserved across subsection descent
/// for breadcrumb-style display).
private struct FlattenedItem {
    let item: EchoDebugMenuItem
    let sectionTitle: String

    var id: String { item.id }
    var alias: String? { item.alias }
    var title: String { item.title }
    var itemDescription: String? { item.itemDescription }
    var tags: [String] { item.tags ?? [] }
    var type: EchoDebugMenuItemType { item.type }

    var typeName: String {
        switch item.type {
        case .toggle: return "toggle"
        case .picker: return "picker"
        case .action: return "action"
        case .textInput: return "textInput"
        case .subsection: return "subsection"
        case .info: return "info"
        }
    }

    var json: [String: Any] {
        var out: [String: Any] = [
            "id": id,
            "title": title,
            "section": sectionTitle,
            "type": typeName,
            "tags": tags,
        ]
        if let payload = try? encodableAsAnyJSON(item.type) {
            out["type_payload"] = payload
        }
        if let alias { out["alias"] = alias }
        if let itemDescription { out["description"] = itemDescription }
        return out
    }
}

private func readLatestSnapshot(from sessionURL: URL) throws -> LatestSnapshot? {
    let pluginName = PluginID.sanitize(debugMenuPluginID)
    let fileURL = sessionURL.appendingPathComponent("\(pluginName).jsonl")
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
    let decoder = clientEventDecoder()
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inner = entry["data"],
              let innerData = try? JSONSerialization.data(withJSONObject: inner),
              let event = try? decoder.decode(EchoDebugMenuClientEvent.self, from: innerData) else {
            continue
        }
        if case let .updateSnapshot(snapshot) = event {
            return LatestSnapshot(sections: snapshot.sections)
        }
    }
    return nil
}

/// Snapshot timestamps are encoded as integer milliseconds (see
/// `sendDebugEvent` below and the client encoder). Match that on decode so
/// `EchoDebugMenuSnapshot.timestamp` doesn't choke on the wire format.
private func clientEventDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        if let ms = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        if let s = try? container.decode(String.self), let ms = Double(s) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected numeric (ms) timestamp",
        )
    }
    return decoder
}

/// Walks one section recursively, yielding a FlattenedItem per leaf.
/// `.subsection` cases are descended into so the breadcrumb section title
/// stays anchored to the top-level section name.
private func flattenLeaves(section: EchoDebugMenuSection) -> [FlattenedItem] {
    collectLeaves(items: section.items, sectionTitle: section.title)
}

private func collectLeaves(items: [EchoDebugMenuItem], sectionTitle: String) -> [FlattenedItem] {
    var out: [FlattenedItem] = []
    for item in items {
        if case let .subsection(child) = item.type {
            out.append(contentsOf: collectLeaves(items: child.items, sectionTitle: sectionTitle))
            continue
        }
        out.append(FlattenedItem(item: item, sectionTitle: sectionTitle))
    }
    return out
}

private func countLeafItems(in section: EchoDebugMenuSection) -> Int {
    flattenLeaves(section: section).count
}

private func valueDescription(_ type: EchoDebugMenuItemType) -> String {
    switch type {
    case let .toggle(isOn):
        return isOn ? "ON" : "OFF"
    case let .picker(options, selectedIndex):
        let selected = (0..<options.count).contains(selectedIndex) ? options[selectedIndex] : "?"
        return "\(selected) [\(options.joined(separator: " | "))]"
    case .action:
        return "(action)"
    case let .textInput(value, _):
        return value.isEmpty ? "(empty)" : "\"\(value)\""
    case .subsection:
        return "(subsection)"
    case let .info(value):
        if let value, !value.isEmpty {
            return "\"\(value)\""
        }
        return "(read-only)"
    }
}

private func printItemTable(_ rows: [FlattenedItem]) {
    // Columns: TYPE | VALUE | ALIAS | DESCRIPTION. Description is truncated to
    // fit the terminal width; full text lives in `describe`.
    let typeWidth = max("TYPE".count, rows.map { $0.typeName.count }.max() ?? 0)
    let valueCells = rows.map { valueDescription($0.type) }
    let valueWidth = max("VALUE".count, min(20, valueCells.map(\.count).max() ?? 0))
    let aliasCells = rows.map { $0.alias ?? "-" }
    let aliasWidth = max("ALIAS".count, aliasCells.map(\.count).max() ?? 0)
    let descWidth = 80

    let header = "\(pad("TYPE", typeWidth))  \(pad("VALUE", valueWidth))  \(pad("ALIAS", aliasWidth))  DESCRIPTION"
    print("  " + header)
    print("  " + String(repeating: "-", count: header.count))
    for (idx, row) in rows.enumerated() {
        let value = truncate(valueCells[idx], to: valueWidth)
        let alias = pad(aliasCells[idx], aliasWidth)
        let desc = truncate(row.itemDescription ?? row.title, to: descWidth)
        print("  \(pad(row.typeName, typeWidth))  \(pad(value, valueWidth))  \(alias)  \(desc)")
    }
}

private func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

private func truncate(_ s: String, to width: Int) -> String {
    s.count <= width ? s : String(s.prefix(width - 1)) + "…"
}

private func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    if let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

/// Round-trip an `Encodable` through JSON so it composes with the existing
/// `[String: Any]` -> JSONSerialization output path used by `printJSON`.
private func encodableAsAnyJSON<T: Encodable>(_ value: T) throws -> Any {
    let data = try JSONEncoder().encode(value)
    return try JSONSerialization.jsonObject(with: data)
}

// MARK: - Reference Resolution (id or alias)

/// Resolves an arbitrary reference (id or alias) to the canonical item id and
/// payload from the latest snapshot. Throws if neither matches.
private func resolveItem(_ reference: String, sessionID: String?) throws -> FlattenedItem {
    let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: sessionID)
    try assertDebugMenuPluginAvailable(at: sessionURL)
    guard let snapshot = try readLatestSnapshot(from: sessionURL) else {
        throw DebugCommandError.sendFailed("No snapshot found. Run `echoapp connect` first.")
    }
    return try resolveReference(reference, in: snapshot)
}

private func resolveReference(_ reference: String, in snapshot: LatestSnapshot) throws -> FlattenedItem {
    let allItems = snapshot.sections.flatMap { flattenLeaves(section: $0) }
    if let exact = allItems.first(where: { $0.id == reference }) {
        return exact
    }
    let aliasMatches = allItems.filter { $0.alias == reference }
    if aliasMatches.count > 1 {
        let ids = aliasMatches.map(\.id).joined(separator: ", ")
        throw DebugCommandError.sendFailed("Alias '\(reference)' is ambiguous; matched: \(ids).")
    }
    if let aliasMatch = aliasMatches.first {
        return aliasMatch
    }
    throw DebugCommandError.sendFailed(
        "No item matches '\(reference)'. Use `echoapp debugmenu find <query>` to search.",
    )
}

// MARK: - JSONL Tail (acks + snapshot refresh)

private enum DebugAck {
    /// itemUpdated for our itemId, or a fresh updateSnapshot — both prove the
    /// device received and processed the mutation.
    case acknowledged
    case actionCompleted(success: Bool, message: String?)
    case error(String)
    case timeout
}

private func sessionJSONLURL(_ sessionURL: URL) -> URL {
    sessionURL.appendingPathComponent("\(PluginID.sanitize(debugMenuPluginID)).jsonl")
}

/// Throws if the session metadata records a client handshake (`clientPluginIDs`
/// is non-nil) AND the DebugMenu plugin id is not in the list. Stays silent
/// when the handshake hasn't arrived yet (older sessions, or the device hasn't
/// connected back since the writer started) so we don't false-positive a
/// not-yet-handshaken connection as "not implemented."
private func assertDebugMenuPluginAvailable(at sessionURL: URL) throws {
    guard let metadata = SessionDirectory.readMetadata(at: sessionURL),
          let advertised = metadata.clientPluginIDs
    else {
        return
    }
    if advertised.contains(debugMenuPluginID) { return }
    throw DebugCommandError.sendFailed(
        """
        The connected client does not implement the DebugMenu ClientPlugin \
        (\(debugMenuPluginID)). The device advertised \(advertised.count) \
        plugin(s) on connect but DebugMenu was not among them. Verify the \
        device is running a debug build with `DebugMenuClientPlugin` registered.
        """,
    )
}

private func currentFileSize(_ url: URL) -> UInt64 {
    guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attr[.size] as? NSNumber else { return 0 }
    return size.uint64Value
}

/// Tail the plugin JSONL from `startOffset`, decode each new line as an
/// `EchoDebugMenuClientEvent`, and return the first event that matches the
/// mutation contract. Polls every 50ms until `timeout` elapses.
private func awaitAck(
    itemId: String,
    jsonlURL: URL,
    fromByteOffset startOffset: UInt64,
    timeout: TimeInterval,
) -> DebugAck {
    let deadline = Date().addingTimeInterval(timeout)
    let decoder = clientEventDecoder()
    var offset = startOffset

    while Date() < deadline {
        if let event = readNextMatchingEvent(
            jsonlURL: jsonlURL,
            fromByteOffset: &offset,
            decoder: decoder,
            predicate: { event in
                switch event {
                case .updateSnapshot:
                    // An untargeted `updateSnapshot` is *not* a valid ack — concurrent or periodic
                    // snapshot traffic can land before the targeted mutation, and accepting it
                    // would report success before the device actually applied the change. Wait for
                    // the explicit `actionCompleted` / `itemUpdated` for `itemId` (or an `error`).
                    return false
                case let .itemUpdated(id, _):
                    return id == itemId
                case let .actionCompleted(id, _, _):
                    return id == itemId
                case .error:
                    return true
                }
            },
        ) {
            switch event {
            case .updateSnapshot:
                // Filtered out by the predicate above; switch is exhaustive over enum cases.
                continue
            case .itemUpdated:
                return .acknowledged
            case let .actionCompleted(_, success, message):
                return .actionCompleted(success: success, message: message)
            case let .error(message):
                return .error(message)
            }
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return .timeout
}

/// Returns true if a fresh `updateSnapshot` lands within `timeout`. Used by
/// `list --refresh` to wait for the device's response after `requestSnapshot`.
private func awaitSnapshot(
    jsonlURL: URL,
    fromByteOffset startOffset: UInt64,
    timeout: TimeInterval,
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    let decoder = clientEventDecoder()
    var offset = startOffset

    while Date() < deadline {
        if let _ = readNextMatchingEvent(
            jsonlURL: jsonlURL,
            fromByteOffset: &offset,
            decoder: decoder,
            predicate: { event in
                if case .updateSnapshot = event { return true }
                return false
            },
        ) {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

/// Reads any new bytes from `jsonlURL` past `offset`, splits on newlines,
/// decodes each line as `EchoDebugMenuClientEvent`, and returns the first
/// event satisfying `predicate`. `offset` is advanced *only* past consumed
/// (matched or skipped) lines — any lines after the match are preserved for
/// the next call so concurrent writes in the same batch don't get silently
/// dropped (e.g. `debugmenu watch` would miss bursts otherwise).
private func readNextMatchingEvent(
    jsonlURL: URL,
    fromByteOffset offset: inout UInt64,
    decoder: JSONDecoder,
    predicate: (EchoDebugMenuClientEvent) -> Bool,
) -> EchoDebugMenuClientEvent? {
    guard FileManager.default.fileExists(atPath: jsonlURL.path),
          let handle = try? FileHandle(forReadingFrom: jsonlURL) else {
        return nil
    }
    defer { try? handle.close() }
    do {
        try handle.seek(toOffset: offset)
    } catch {
        return nil
    }
    let new = (try? handle.readToEnd()) ?? Data()
    guard !new.isEmpty else { return nil }

    var cursor = new.startIndex
    while cursor < new.endIndex {
        // Find the end of the current line. If there's no trailing newline
        // we have a partial write — leave it for next call and bail.
        guard let nl = new[cursor...].firstIndex(of: 0x0A) else { break }
        let lineLen = UInt64(nl - cursor) + 1 // include the newline
        let line = new[cursor..<nl]
        if !line.isEmpty,
           let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
           let inner = entry["data"],
           let innerData = try? JSONSerialization.data(withJSONObject: inner),
           let event = try? decoder.decode(EchoDebugMenuClientEvent.self, from: innerData),
           predicate(event) {
            offset += lineLen
            return event
        }
        offset += lineLen
        cursor = new.index(after: nl)
    }
    return nil
}

/// Pretty-prints the ack outcome for mutation subcommands. Throws on device
/// error / negative actionCompleted so the CLI's exit code reflects failure.
///
/// `expectingNoAck` is set for items tagged `restart_on_change`, where the
/// device is known to sever the WebSocket before it can echo an ack — so
/// timeout in that case is the success path and we suppress the warning.
private func reportAck(
    _ ack: DebugAck,
    itemId: String,
    successMessage: String,
    expectingNoAck: Bool,
) throws {
    switch ack {
    case .acknowledged:
        print(successMessage)
    case let .actionCompleted(success, message):
        if success {
            print(message ?? successMessage)
        } else {
            throw DebugCommandError.sendFailed(
                "Action '\(itemId)' failed on device: \(message ?? "no message")",
            )
        }
    case let .error(message):
        throw DebugCommandError.sendFailed("Device reported error: \(message)")
    case .timeout:
        print(successMessage)
        guard !expectingNoAck else { return }
        // Payload was forwarded (HTTP 200) but no ack arrived. Surface to stderr
        // so callers know the mutation may not have applied on device.
        FileHandle.standardError.write(
            "Warning: no device ack within \(Int(defaultAckTimeout))s; mutation may not have applied.\n"
                .data(using: .utf8)!,
        )
    }
}

/// Sends a mutation event and waits for the device ack, with special handling
/// for items tagged `restart_on_change` (silent timeout, shorter window, and
/// a heads-up to the operator that the connection will drop).
private func sendAndReport(
    event: EchoDebugMenuDesktopEvent,
    item: FlattenedItem,
    sessionID: String?,
    successMessage: String,
    timeout: TimeInterval = defaultAckTimeout,
) throws {
    let sessionURL = try SessionDirectory.resolveSessionURL(sessionID: sessionID)
    let jsonlURL = sessionJSONLURL(sessionURL)
    let preSendOffset = currentFileSize(jsonlURL)
    let restartCoupled = item.tags.contains(EchoDebugMenuItem.restartOnChangeTag)
    if restartCoupled {
        FileHandle.standardError.write(
            "Note: '\(item.id)' is tagged \(EchoDebugMenuItem.restartOnChangeTag); the app will restart and the Echo connection will drop.\n"
                .data(using: .utf8)!,
        )
    }
    try sendDebugEvent(event, sessionID: sessionID)
    let effectiveTimeout = restartCoupled ? 0.5 : timeout
    let ack = awaitAck(
        itemId: item.id,
        jsonlURL: jsonlURL,
        fromByteOffset: preSendOffset,
        timeout: effectiveTimeout,
    )
    try reportAck(
        ack,
        itemId: item.id,
        successMessage: successMessage,
        expectingNoAck: restartCoupled,
    )
}

private let defaultAckTimeout: TimeInterval = 3.0

// MARK: - Send

private let debugMenuPluginID = "com.echo.plugin.debugmenu"

private func sendDebugEvent(_ event: EchoDebugMenuDesktopEvent, sessionID: String?) throws {
    let port = try resolveServerPort(sessionID: sessionID)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(Int(date.timeIntervalSince1970 * 1_000))
    }
    let eventData = try encoder.encode(event)
    let payload = PluginPayload(pluginID: debugMenuPluginID, data: eventData)
    let payloadData = try JSONEncoder().encode(payload)

    let url = URL(string: "http://127.0.0.1:\(port)/api/send")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = payloadData

    let semaphore = DispatchSemaphore(value: 0)
    var responseError: Error?
    var statusCode: Int?
    URLSession.shared.dataTask(with: request) { _, response, error in
        responseError = error
        statusCode = (response as? HTTPURLResponse)?.statusCode
        semaphore.signal()
    }.resume()
    // Bound the wait so a wedged or unresponsive CLI server doesn't hang the
    // caller indefinitely (matters for agent/automation contexts).
    if semaphore.wait(timeout: .now() + .seconds(5)) == .timedOut {
        throw DebugCommandError.sendFailed("Timed out waiting for echoapp server response.")
    }

    if let error = responseError {
        throw DebugCommandError.sendFailed("Could not reach echoapp server: \(error.localizedDescription)")
    }
    if let code = statusCode {
        switch code {
        case 200: break
        case 503: throw DebugCommandError.sendFailed("No connected device. Make sure the app is running and connected via echoapp connect.")
        default: throw DebugCommandError.sendFailed("Server returned status \(code)")
        }
    }
}

private func resolveServerPort(sessionID: String?) throws -> Int {
    // Resolve the caller's target session dir so we can pick the matching
    // registry entry. When multiple `echoapp connect` processes are live,
    // we must route mutations to the same session whose snapshot we resolved
    // the item id from -- otherwise the command can mutate the wrong device.
    let targetSessionPath = try SessionDirectory.resolveSessionURL(sessionID: sessionID)
        .standardizedFileURL.path
    let registryDir = SessionDirectory.registryURL
    guard FileManager.default.fileExists(atPath: registryDir.path) else {
        throw DebugCommandError.noLiveSession
    }
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: registryDir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles],
    ) else {
        throw DebugCommandError.noLiveSession
    }
    for entry in entries {
        guard entry.pathExtension == "json",
              let data = try? Data(contentsOf: entry),
              let registryEntry = try? JSONDecoder().decode(SessionRegistryEntry.self, from: data) else {
            continue
        }
        let entrySessionPath = URL(fileURLWithPath: registryEntry.sessionDir).standardizedFileURL.path
        guard entrySessionPath == targetSessionPath else { continue }
        if kill(registryEntry.pid, 0) == 0 {
            return registryEntry.port
        }
    }
    throw DebugCommandError.noLiveSession
}

// MARK: - Errors

enum DebugCommandError: Error, CustomStringConvertible {
    case noLiveSession
    case sendFailed(String)

    var description: String {
        switch self {
        case .noLiveSession:
            return "No live echoapp connect session found. Start one with: echoapp connect <device>."
        case let .sendFailed(message):
            return "Failed to send command: \(message)"
        }
    }
}
