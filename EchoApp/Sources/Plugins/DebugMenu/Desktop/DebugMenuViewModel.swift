import Combine
import DebugMenuPluginAPI
import EchoPluginAPI
import Foundation

final class DebugMenuViewModel: ObservableObject {
    @Published var sections: [EchoDebugMenuSection] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastActionResult: ActionResult?
    @Published private(set) var isConnected = false

    private var connection: PluginConnection?
    private var cancellables = Set<AnyCancellable>()

    struct ActionResult: Identifiable {
        let id = UUID()
        let itemId: String
        let success: Bool
        let message: String?
        let timestamp: Date
    }

    // MARK: - Filtered Items

    /// During search, flatten the whole tree (including nested subsections)
    /// and return matching leaves in a single synthetic section. Outside of
    /// search, render the unmodified hierarchy so the navigation UX matches
    /// the on-device debug menu.
    var filteredSections: [EchoDebugMenuSection] {
        guard !searchText.isEmpty else { return sections }
        let query = searchText.lowercased()
        let matches = sections.flatMap { collectLeafMatches(in: $0, query: query, parentBreadcrumb: nil) }
        guard !matches.isEmpty else { return [] }
        return [
            EchoDebugMenuSection(
                id: "search-results",
                title: "Results",
                icon: nil,
                items: matches
            )
        ]
    }

    private func collectLeafMatches(
        in section: EchoDebugMenuSection,
        query: String,
        parentBreadcrumb: String?
    ) -> [EchoDebugMenuItem] {
        let breadcrumb = [parentBreadcrumb, section.title.isEmpty ? nil : section.title]
            .compactMap { $0 }
            .joined(separator: " > ")
        var results: [EchoDebugMenuItem] = []
        for item in section.items {
            if case .subsection(let child) = item.type {
                results.append(contentsOf: collectLeafMatches(
                    in: child,
                    query: query,
                    parentBreadcrumb: breadcrumb.isEmpty ? nil : breadcrumb
                ))
                continue
            }
            if matches(item: item, query: query) {
                let displaySubtitle = item.subtitle ?? breadcrumb
                results.append(EchoDebugMenuItem(
                    id: item.id,
                    alias: item.alias,
                    title: item.title,
                    subtitle: displaySubtitle.isEmpty ? nil : displaySubtitle,
                    itemDescription: item.itemDescription,
                    type: item.type,
                    tags: item.tags
                ))
            }
        }
        return results
    }

    private func matches(item: EchoDebugMenuItem, query: String) -> Bool {
        item.title.lowercased().contains(query)
            || (item.alias?.lowercased().contains(query) ?? false)
            || (item.subtitle?.lowercased().contains(query) ?? false)
            || (item.itemDescription?.lowercased().contains(query) ?? false)
            || (item.tags?.contains(where: { $0.lowercased().contains(query) }) ?? false)
    }

    // MARK: - Connection

    @MainActor
    func setupConnection(_ connection: PluginConnection) {
        self.connection = connection
        isConnected = true

        // The class is @MainActor, so `.receive(on: .main)` lands the sink
        // body on the right actor synchronously. No `Task { @MainActor }`
        // hop — that one reorders rapid event pairs (e.g. `updateSnapshot`
        // immediately followed by `itemUpdated`).
        connection
            .receive(EchoDebugMenuClientEvent.self)
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handleClientEvent(event)
                }
            })
            .store(in: &cancellables)
    }

    @MainActor
    func disconnect() {
        connection = nil
        isConnected = false
        cancellables.removeAll()
        sections = []
        isLoading = false
        errorMessage = nil
        lastActionResult = nil
    }

    func requestSnapshot() {
        Task { @MainActor in
            isLoading = true
            // Reset loading immediately on send failure: no client event will arrive to clear
            // the flag otherwise (e.g. during connect/reconnect races when the socket is gone).
            if !sendDesktopEvent(.requestSnapshot) {
                isLoading = false
            }
        }
    }

    // MARK: - Actions

    @MainActor
    func setToggle(itemId: String, isOn: Bool) {
        // Apply optimistically, then revert if the send fails: the device echoes
        // a fresh snapshot on success, so a successful send eventually overwrites
        // this anyway; a failed send leaves no incoming snapshot to correct the UI.
        guard let previous = findItem(id: itemId) else { return }
        applyLocalUpdate(itemId: itemId, newType: .toggle(isOn: isOn))
        if !sendDesktopEvent(.setToggle(itemId: itemId, isOn: isOn)) {
            applyLocalUpdate(itemId: itemId, newType: previous.type)
        }
    }

    @MainActor
    func selectOption(itemId: String, selectedIndex: Int) {
        guard let previous = findItem(id: itemId) else { return }
        if case .picker(let options, _) = previous.type {
            applyLocalUpdate(itemId: itemId, newType: .picker(options: options, selectedIndex: selectedIndex))
        }
        if !sendDesktopEvent(.selectOption(itemId: itemId, selectedIndex: selectedIndex)) {
            applyLocalUpdate(itemId: itemId, newType: previous.type)
        }
    }

    @MainActor
    func executeAction(itemId: String) {
        _ = sendDesktopEvent(.executeAction(itemId: itemId))
    }

    @MainActor
    func setTextValue(itemId: String, value: String) {
        guard let previous = findItem(id: itemId) else { return }
        if case .textInput(_, let placeholder) = previous.type {
            applyLocalUpdate(itemId: itemId, newType: .textInput(value: value, placeholder: placeholder))
        }
        if !sendDesktopEvent(.setTextValue(itemId: itemId, value: value)) {
            applyLocalUpdate(itemId: itemId, newType: previous.type)
        }
    }

    // MARK: - Item Lookup

    func findItem(id: String) -> EchoDebugMenuItem? {
        for section in sections {
            if let item = findItem(id: id, in: section) {
                return item
            }
        }
        return nil
    }

    private func findItem(id: String, in section: EchoDebugMenuSection) -> EchoDebugMenuItem? {
        for item in section.items {
            if item.id == id { return item }
            if case .subsection(let child) = item.type,
               let nested = findItem(id: id, in: child) {
                return nested
            }
        }
        return nil
    }

    /// Re-resolve a section by id from the current snapshot, walking nested
    /// subsections. Used by pushed detail views to re-bind to live state
    /// after the device sends a new snapshot.
    func findSection(id: String) -> EchoDebugMenuSection? {
        for section in sections {
            if let match = findSection(id: id, in: section) {
                return match
            }
        }
        return nil
    }

    private func findSection(id: String, in section: EchoDebugMenuSection) -> EchoDebugMenuSection? {
        if section.id == id { return section }
        for item in section.items {
            if case .subsection(let child) = item.type {
                if let match = findSection(id: id, in: child) {
                    return match
                }
            }
        }
        return nil
    }

    // MARK: - Event Handling

    @MainActor
    private func handleClientEvent(_ event: EchoDebugMenuClientEvent) {
        switch event {
        case let .updateSnapshot(snapshot):
            sections = snapshot.sections
            isLoading = false
            errorMessage = nil

        case let .itemUpdated(itemId, newType):
            applyLocalUpdate(itemId: itemId, newType: newType)

        case let .actionCompleted(itemId, success, message):
            lastActionResult = ActionResult(
                itemId: itemId,
                success: success,
                message: message,
                timestamp: Date()
            )

        case let .error(message):
            errorMessage = message
            isLoading = false
        }
    }

    @MainActor
    private func applyLocalUpdate(itemId: String, newType: EchoDebugMenuItemType) {
        sections = sections.map { updateSection($0, itemId: itemId, newType: newType) }
    }

    private func updateSection(
        _ section: EchoDebugMenuSection,
        itemId: String,
        newType: EchoDebugMenuItemType
    ) -> EchoDebugMenuSection {
        let updatedItems = section.items.map { item -> EchoDebugMenuItem in
            if item.id == itemId {
                return EchoDebugMenuItem(
                    id: item.id,
                    alias: item.alias,
                    title: item.title,
                    subtitle: item.subtitle,
                    itemDescription: item.itemDescription,
                    type: newType,
                    tags: item.tags
                )
            }
            if case .subsection(let child) = item.type {
                let updatedChild = updateSection(child, itemId: itemId, newType: newType)
                return EchoDebugMenuItem(
                    id: item.id,
                    alias: item.alias,
                    title: item.title,
                    subtitle: item.subtitle,
                    itemDescription: item.itemDescription,
                    type: .subsection(updatedChild),
                    tags: item.tags
                )
            }
            return item
        }
        return EchoDebugMenuSection(
            id: section.id,
            title: section.title,
            icon: section.icon,
            items: updatedItems
        )
    }

    @discardableResult @MainActor
    private func sendDesktopEvent(_ event: EchoDebugMenuDesktopEvent) -> Bool {
        guard let connection else {
            errorMessage = "Connect a mobile app before sending debug menu commands."
            return false
        }

        do {
            try connection.send(event)
            return true
        } catch {
            errorMessage = "Failed to send command: \(error.localizedDescription)"
            return false
        }
    }
}
