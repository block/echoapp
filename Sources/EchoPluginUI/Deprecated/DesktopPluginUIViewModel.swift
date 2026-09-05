import Combine
import EchoPluginAPI
import Foundation

@available(*, deprecated, message: "This component is deprecated, use EchoTableViewViewModel instead.")
public class DesktopPluginTableUIViewModel: ObservableObject {

    /// Configuration for the `DesktopPluginTableUIViewModel`, controlling the table's behavior and appearance.
    public struct Configuration {
        /// An ordered set of keys to specify which columns to display. If nil, columns are dynamically generated from the first row's columnItems.
        public let customColumnConfiguration: [EchoColumnKey]?

        /// The maximum number of rows to keep in memory and display. Rows are discarded in FIFO order when this limit is exceeded.
        public let maxRowCount: Int

        /// The key used to find a title for the detail view header. If nil, the header will be omitted.
        public let detailViewTitleKey: String?

        /// Whether the table should use monospacedFont
        public let monospacedFont: Bool

        /// Initializes a `Configuration` for `DesktopPluginTableUIViewModel`.
        /// - Parameters:
        ///   - customColumnConfiguration: An optional array of `EchoColumnKey` for custom column order and configuration.
        ///   - maxRowCount: The maximum number of rows to keep in memory, default is 5000.
        ///   - detailViewTitleKey: An optional key for the detail view header title.
        public init(
            customColumnConfiguration: [EchoColumnKey]? = nil,
            maxRowCount: Int = 5000,
            detailViewTitleKey: String? = nil,
            monospacedFont: Bool = false
        ) {
            self.customColumnConfiguration = customColumnConfiguration
            self.maxRowCount = maxRowCount
            self.detailViewTitleKey = detailViewTitleKey
            self.monospacedFont = monospacedFont
        }
    }

    public let configuration: Configuration
    public let pluginId: String

    public init(
        configuration: Configuration = .init(),
        pluginId: String
    ) {
        self.configuration = configuration
        self.pluginId = pluginId
    }

    @Published var rows = [EchoTableRow]()
    @Published var selectedRowID: String?
    @Published var searchText: String = ""
    @Published var inspectorPresented: Bool = true
    @Published var currentFilters: [EchoColumnKey.ID: String] = [:]

    private var cachedColumnKeys: [EchoColumnKey]?

    /// Returns an array of `EchoColumnKey` objects representing the keys for each column in the table.
    /// - Returns: An array of `EchoColumnKey` based on custom configuration or the first row's columnItems.
    func columnKeys() -> [EchoColumnKey] {
        if let cachedColumnKeys {
            return cachedColumnKeys
        }

        if let firstRow = self.rows.first {
            let firstRowColumnKeys = firstRow.columnItems.keys.map { EchoColumnKey(id: $0) }
            if let customColumnOverrides = configuration.customColumnConfiguration {

                let validCustomOverrides = customColumnOverrides.filter {
                    firstRowColumnKeys.map {$0.id} .contains($0.id)
                }

                let remainingKeys = firstRowColumnKeys.filter { 
                    !customColumnOverrides.map { $0.id }.contains($0.id)
                }

                let combinedColumns = validCustomOverrides + remainingKeys

                cachedColumnKeys = combinedColumns
                return combinedColumns
            }

            cachedColumnKeys = firstRowColumnKeys
            return firstRowColumnKeys
        }

        return []
    }

    // MARK: - Row Management

    /// Inserts a new row at the beginning of the table unless the insertion is paused.
    /// - Parameter row: The `EchoTableRow` to be inserted.
    @MainActor
    public func insertRow(row: EchoTableRow) {
        if isPaused {
            return
        }

        while rows.count >= configuration.maxRowCount {
            rows.removeLast()
        }

        rows.insert(row, at: 0)
    }

    /// Returns the currently selected row, if any.
    var selectedRow: EchoTableRow? {
        if let selectedRowID {
            return rows.first(where: { $0.id == selectedRowID })
        } else {
            return nil
        }
    }

    var filteredRows: [EchoTableRow] {
        rows.filter { [weak self] row in
            guard let self = self else { return false }

            // Check if search text is empty and if not, filter by search text
            if !self.searchText.isEmpty {
                // Check if the row matches the search text
                let matchesSearchText = String(describing: row)
                    .lowercased()
                    .contains(self.searchText.lowercased())

                // If it does not match the search text, filter it out
                if !matchesSearchText {
                    return false
                }
            }

            // If there are filterable columns, check if row matches the filter criteria
            if !self.filterableColumns.isEmpty {
                let matchesFilters = self.filterableColumns.allSatisfy { column in
                    if let filterValue = self.currentFilters[column.id], filterValue != "None" {
                        return row.columnItems[column.id] == filterValue
                    }
                    return true // If no filter is applied or filter is "None", include the row
                }
                return matchesFilters
            }

            return true // If there are no filters, include the row
        }
    }

    var filterableColumns: [EchoColumnKey] {
        columnKeys().filter { $0.isFilterable }
    }

    public func valuesForColumn(columnKey: EchoColumnKey) -> [IdentifiableColumnValue] {
        Array(
            Set(rows
                .compactMap { $0.columnItems[columnKey.id] }))
                .sorted()
                .map { IdentifiableColumnValue(value: $0) }
    }

    // MARK: - Table Footer

    public func itemCountLabel() -> String {
        "\(rows.count) \(rows.count == 1 ? "item" : "items")"
    }

    /// Boolean indicating whether row insertion is paused.
    @Published var isPaused: Bool = false

    /// Clears all rows from the table.
    public func clearRows() {
        rows.removeAll()
    }

    /// Toggles the paused state for row insertion.
    public func togglePaused() {
        isPaused.toggle()
    }

    // MARK: - Search

    public func setSearchText(searchText: String) {
        self.searchText = searchText
    }

    public func setSelectedRowID(selectedRowID: String?) {
        self.selectedRowID = selectedRowID
    }

    // MARK: - Connection

    private var cancellable: AnyCancellable?

    public func connect(connection: PluginConnection) {
        cancellable = connection
        .receiveEchoTableRows()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] tableRow in
            MainActor.assumeIsolated {
                self?.insertRow(row: tableRow)
            }
        }
    }

    public func disconnect() {
        cancellable = nil
    }
}
