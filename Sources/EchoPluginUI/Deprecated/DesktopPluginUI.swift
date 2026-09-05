import Combine
import EchoPluginAPI
import SwiftUI

/// Represents the main UI for the Echo Plugin Table.
@available(*, deprecated, message: "This component is deprecated, use EchoTableView instead.")
public struct DesktopPluginTableUI<InspectorFooter: View>: View {
    @ObservedObject var viewModel: DesktopPluginTableUIViewModel
    let inspectorFooter: (EchoTableRow) -> InspectorFooter

    /// Initializes the `DesktopPluginTableUIViewModel` with a view model and optional inspector footer view.
    /// - Parameters:
    ///   - viewModel: The `DesktopPluginTableUIViewModel` managing the table state.
    ///   - inspectorFooter: An optional footer view for the inspector, default is an empty view.
    public init(
        viewModel: DesktopPluginTableUIViewModel,
        @ViewBuilder inspectorFooter: @escaping (EchoTableRow) -> InspectorFooter = { _ in EmptyView() }
    ) {
        self.viewModel = viewModel
        self.inspectorFooter = inspectorFooter
    }

    /// The body of the `EchoPluginTableUI` view, defining the layout and structure.
    public var body: some View {
        // If available, use TableColumnForEach to create columns from columnItems.
        // and inspector() for detailView
        if #available(macOS 14.4, *) {
            VStack(spacing: 0) {
                EchoTable(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                EchoTableFooter(viewModel: viewModel)
            }
            .inspector(isPresented: $viewModel.inspectorPresented) {
                RowInspector(
                    row: viewModel.selectedRow,
                    titleKey: viewModel.configuration.detailViewTitleKey,
                    languageForKeys: [:],
                    footer: { row in
                        if let row {
                            inspectorFooter(row)
                        } else {
                            EmptyView()
                        }
                    }
                )
                .inspectorColumnWidth(min: 400, ideal: 500, max: 1200)
            }
            .toolbar {
                Button {
                    viewModel.inspectorPresented.toggle()
                } label: {
                    Label("Toggle Inspector", systemImage: "sidebar.right")
                }
            }
            .onHotKeyEvent(key: "k", modifierFlags: .command) {
                viewModel.clearRows()
            }
        } else {
            VStack(spacing: 0) {
                Text("Update your computer to MacOS 14.4+ for a better plugin UI experience!")
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color.yellow)
                    .multilineTextAlignment(.center)
                Table(viewModel.filteredRows, selection: $viewModel.selectedRowID) {
                    TableColumn("ID", value: \.id)
                    TableColumn("Column Items") { row in
                        Text(String(describing: row.columnItems))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Represents a dynamic table view using SwiftUI, available in macOS 14.4 and later.
    @available(macOS 14.4, *)
    private struct EchoTable: View {
        @ObservedObject var viewModel: DesktopPluginTableUIViewModel
        @SceneStorage("EchoTable-ColumnCustomizations")
        private var columnCustomization: TableColumnCustomization<EchoTableRow>

        /// The body of the `EchoTable` view, defining the layout and structure.
        public var body: some View {
            Table(
                viewModel.filteredRows,
                selection: $viewModel.selectedRowID,
                columnCustomization: $columnCustomization
            ) {
                TableColumnForEach(viewModel.columnKeys()) { columnKey in
                    TableColumn(columnKey.id) { row in
                        if let value = row.columnItems[columnKey.id] {
                            Text(value)
                                .font(viewModel.configuration.monospacedFont ? .system(size: 11, design: .monospaced) : .body )
                        } else {
                            Text("")
                        }
                    }
                    .width(min: 50, ideal: columnKey.width, max: 600)
                    .customizationID("\(viewModel.pluginId)-\(columnKey.id)")
                }
                .alignment(.leading)
            }
            .searchable(text: $viewModel.searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private struct EchoTableFooter: View {
        @ObservedObject var viewModel: DesktopPluginTableUIViewModel

        /// The body of the `EchoTable` view, defining the layout and structure.
        public var body: some View {
            HStack(alignment: .center) {
                Button {
                    viewModel.isPaused.toggle()
                } label: {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                }
                .help("Pause. New items will be dropped until unpaused.")
                .buttonStyle(HoverButtonStyle(textColor: .secondaryLabel))
                if viewModel.isPaused {
                    Text("PAUSED")
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white)
                        .background(Color.red)
                        .cornerRadius(4.0)
                }
                Button {
                    viewModel.clearRows()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .help("⌘ + K")
                }
                .help("Clear all")
                .buttonStyle(HoverButtonStyle(textColor: .secondaryLabel))
                Text(viewModel.itemCountLabel())
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(Color.tertiaryLabel)
                    ForEach(viewModel.filterableColumns) { column in
                        Picker(
                            column.id,
                            selection: bindingForColumn(column: column)
                        ) {
                            ForEach(viewModel.valuesForColumn(columnKey: column)) { value in
                                Text(value.id)
                                    .tag(value.id)
                            }
                        }
                        .frame(maxWidth: 120)
                        .pickerStyle(.menu)
                        .tint(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help("Select a filter for \(column.id)")
                        if viewModel.currentFilters[column.id] != nil {
                            Button {
                                viewModel.currentFilters.removeValue(forKey: column.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                    }
                }
            }
            .padding(8)
        }

        private func bindingForColumn(column: EchoColumnKey) -> Binding<String> {
            Binding(
                get: {
                    viewModel.currentFilters[column.id] ?? column.id
                },
                set: { newValue in
                    viewModel.currentFilters[column.id] = newValue
                }
            )
        }
    }

}
