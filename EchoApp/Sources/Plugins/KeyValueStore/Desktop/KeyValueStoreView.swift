
import EchoPluginAPI
import EchoPluginUI
import SwiftUI

public struct KeyValueStoreView: View {
    @StateObject private var viewModel: KeyValueStoreViewModel
    
    public init(viewModel: KeyValueStoreViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    public var body: some View {
        GeometryReader { geometry in
            HSplitView {
                // Left column: Stores list
                storesListColumn
                    .frame(
                        minWidth: geometry.size.width * 0.20,
                        idealWidth: geometry.size.width * 0.25,
                        maxWidth: geometry.size.width * 0.35
                    )
                
                // Middle column: Table view for selected store
                tableColumn
                    .frame(
                        minWidth: geometry.size.width * 0.30,
                        idealWidth: geometry.size.width * 0.45,
                        maxWidth: geometry.size.width * 0.60
                    )
                    .layoutPriority(1)
                
                // Right column: Detail view
                rightPanel
                    .frame(
                        minWidth: geometry.size.width * 0.25,
                        idealWidth: geometry.size.width * 0.30,
                        maxWidth: geometry.size.width * 0.45
                    )
            }
        }
        .frame(minWidth: 600, minHeight: 600)
        .sheet(isPresented: $viewModel.showingAddForm) {
            if let selectedStore = viewModel.selectedStore {
                AddKeyForm(store: selectedStore, viewModel: viewModel)
            }
        }
    }
    
    private var storesListColumn: some View {
        VStack(spacing: 0) {
            if viewModel.stores.isEmpty {
                EchoNullStateView(
                    iconName: "tablecells",
                    message: viewModel.isLoading 
                        ? "Loading stores..."
                        : "No stores available.\nConnect a client app."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Stores list
                List(viewModel.stores, selection: $viewModel.selectedStoreId) { store in
                    storeListItem(for: store)
                        .tag(store.id)
                }
                .listStyle(.sidebar)
                .onAppear {
                    // Select first store if none selected
                    if viewModel.selectedStoreId == nil && !viewModel.stores.isEmpty {
                        viewModel.selectedStoreId = viewModel.stores.first?.id
                    }
                }
                
                // Footer - consistent with table view style  
                EchoListFooterView(
                    itemCount: viewModel.stores.count,
                    itemLabel: "store",
                    itemLabelPlural: "stores",
                    actionButtons: [
                        .init(
                            iconName: "arrow.clockwise",
                            helpText: "Refresh all stores",
                            action: {
                                viewModel.requestSnapshot()
                            }
                        )
                    ]
                ) {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        AnyView(EmptyView())
                    }
                }
            }
        }
    }
    
    private var tableColumn: some View {
        Group {
            if let selectedStore = viewModel.selectedStore {
                KeyValueStoreTableView(
                    store: selectedStore,
                    searchText: $viewModel.searchText,
                    selectedType: $viewModel.selectedType,
                    selectedEntryId: $viewModel.selectedEntryId,
                    sortOrder: $viewModel.sortOrder,
                    viewModel: viewModel
                )
                .searchable(text: $viewModel.searchText, prompt: "Search \(selectedStore.name)")
                .onChange(of: viewModel.selectedStoreId) { _, _ in
                    // Clear selection and search when switching stores
                    viewModel.selectedEntryId = nil
                    viewModel.searchText = ""
                    viewModel.selectedType = nil
                }
            } else {
                EchoNullStateView(
                    iconName: "tablecells",
                    message: "Select a store from the left to view its key-value entries."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func storeListItem(for store: EchoKeyValueStore) -> some View {
        HStack(spacing: 8) {
            // Store icon
            Image(systemName: store.sfSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 14, height: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                // Store name
                Text(store.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Entry count and read-only status
                HStack(spacing: 8) {
                    Text("\(store.entries.count) entries")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if store.isReadOnly {
                        Text("• Read-only")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
    
    private var rightPanel: some View {
        Group {
            if let selectedEntry = viewModel.stores.first(where: { $0.id == viewModel.selectedStoreId })?.entries.first(where: {$0.id == viewModel.selectedEntryId }) {
                KeyValueEntryDetailView(
                    entry: selectedEntry,
                    store: viewModel.selectedStore!,
                    onUpdateValue: viewModel.updateValue,
                    onDeleteKey: viewModel.deleteKey,
                    viewModel: viewModel
                )
            } else {
                EchoNullStateView(
                    iconName: "filemenu.and.cursorarrow",
                    message: "Select a key-value entry to view and edit its details."
                )
            }
        }
    }
}
