import EchoPluginAPI
import EchoPluginUI
import SwiftUI

struct KeyValueStoreTableView: View {
    let store: EchoKeyValueStore
    @Binding var searchText: String
    @Binding var selectedType: EchoKeyValueType?
    @Binding var selectedEntryId: String?
    @Binding var sortOrder: [KeyPathComparator<EchoKeyValueEntry>]
    @ObservedObject var viewModel: KeyValueStoreViewModel
    
    // Performance: compute filtered entries only when needed
    private var filteredEntries: [EchoKeyValueEntry] {
        let searchTerm = searchText.lowercased()
        
        return store.entries
            .filter { entry in
                let matchesSearch = searchTerm.isEmpty ||
                    entry.key.lowercased().contains(searchTerm) ||
                    entry.displayValue.lowercased().contains(searchTerm)
                
                let matchesType = selectedType == nil || entry.type == selectedType
                
                return matchesSearch && matchesType
            }
            .sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
           
            // Main table  
            Table(filteredEntries, selection: $selectedEntryId, sortOrder: $sortOrder) {
                TableColumn("Key", value: \.key) { entry in
                    HStack {
                        Text(entry.key)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        
                        if let flash = viewModel.getFlashState(storeId: store.id, key: entry.key) {
                            changeIndicator(for: flash.type)
                        }
                    }
                    .background(flashBackground(for: entry))
                }
                .width(min: 100, ideal: 200, max: 300)

                TableColumn("Type", value: \.formattedType) { entry in
                    Text(entry.formattedType)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120, max: 150)

                TableColumn("Value") { entry in
                    Text(entry.displayValue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(entry.isEditable ? .primary : .secondary)
                        .background(flashBackground(for: entry))
                }
                .width(min: 150, ideal: 250, max: 400)
            }
            .contextMenu {
                contextMenuContent
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Key-value entries table")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Footer
            EchoListFooterView(
                itemCount: filteredEntries.count,
                itemLabel: "entry",
                itemLabelPlural: "entries",
                actionButtons: footerActionButtons,
                content: {
                    // Type filter
                    AnyView(
                        HStack {
                            Spacer()
                            Picker("Type", selection: $selectedType) {
                                Text("All Types").tag(EchoKeyValueType?.none)
                                ForEach(EchoKeyValueType.allCases, id: \.self) { type in
                                    Text(type.displayName).tag(type as EchoKeyValueType?)
                                }
                            }
                            .pickerStyle(.menu)
                            .controlSize(.small)
                            .frame(width: 120)
                            .help("Filter by value type")
                        }
                    )
                }
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        if !store.isReadOnly {
            Button("Add New Key") {
                viewModel.showingAddForm = true
            }
            .disabled(!viewModel.isConnected)
            Divider()
        }
        
        if let selectedId = selectedEntryId,
           let entry = store.entries.first(where: { $0.id == selectedId }) {
            Button("Copy Key") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.key, forType: .string)
            }
            
            Button("Copy Value") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.displayValue, forType: .string)
            }
            
            if !store.isReadOnly {
                Divider()
                Button("Delete Key") {
                    viewModel.deleteKey(storeId: store.id, key: entry.key)
                }
                .foregroundColor(.red)
                .disabled(!viewModel.isConnected)
            }
        }
    }
    
    // MARK: - Footer Actions
    
    private var footerActionButtons: [EchoListFooterView<AnyView>.ActionButton] {
        var buttons: [EchoListFooterView<AnyView>.ActionButton] = []
        
        // Add Key button (only if not read-only)
        if !store.isReadOnly {
            buttons.append(
                EchoListFooterView.ActionButton(
                    iconName: "plus",
                    text: "Add Key",
                    helpText: "Add a new key-value entry",
                    action: {
                        if viewModel.isConnected {
                            viewModel.showingAddForm = true
                        }
                    }
                )
            )
        }

        // Export button
        buttons.append(
            EchoListFooterView.ActionButton(
                iconName: "square.and.arrow.up",
                text: "Export",
                helpText: "Export store as JSON",
                action: {
                    exportStore()
                }
            )
        )
        
        return buttons
    }
    
    // MARK: - Actions
    
    private func exportStore() {
        let jsonData: [String: Any] = [
            "storeName": store.name,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "entries": store.entries.map { entry in
                [
                    "key": entry.key,
                    "value": entry.detailDisplayValue,
                    "type": entry.type.rawValue,
                    "lastModified": entry.lastModified?.timeIntervalSince1970 as Any
                ]
            }
        ]
        
        do {
            let jsonString = try JSONSerialization.data(withJSONObject: jsonData, options: [.prettyPrinted, .sortedKeys])
            if let stringData = String(data: jsonString, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(stringData, forType: .string)
            }
        } catch {
            print("Failed to export store: \(error)")
        }
    }
    
    // MARK: - Visual Effect Helpers
    
    @ViewBuilder
    private func changeIndicator(for changeType: KeyValueStoreViewModel.ChangeFlash.ChangeType) -> some View {
        switch changeType {
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundColor(.blue)
                .font(.caption)
                .transition(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 
                        .opacity : .scale.combined(with: .opacity)
                )
                .accessibilityLabel("Added")
        case .updated:
            Image(systemName: "pencil.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
                .transition(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 
                        .opacity : .scale.combined(with: .opacity)
                )
                .accessibilityLabel("Updated")
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
                .transition(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 
                        .opacity : .scale.combined(with: .opacity)
                )
                .accessibilityLabel("Deleted")
        }
    }
    
    private func flashBackground(for entry: EchoKeyValueEntry) -> Color? {
        guard let flash = viewModel.getFlashState(storeId: store.id, key: entry.key) else {
            return nil
        }
        
        switch flash.type {
        case .added:
            return Color.blue.opacity(0.3)
        case .updated:
            return Color.green.opacity(0.3)
        case .deleted:
            return Color.red.opacity(0.3)
        }
    }
}

public struct AddKeyForm: View {
    let store: EchoKeyValueStore
    @ObservedObject var viewModel: KeyValueStoreViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var keyName: String = ""
    @State private var selectedType: EchoKeyValueType = .string
    @State private var valueText: String = ""
    @State private var boolValue: Bool = false
    @State private var validationError: String?
    
    private var defaultValuesByType: [EchoKeyValueType: String] {
        [
            .string: "",
            .integer: "0",
            .double: "0.0",
            .boolean: "false",
            .array: "[]",
            .dictionary: "{}",
            .data: "",
            .date: ISO8601DateFormatter().string(from: Date()),
            .url: "https://example.com"
        ]
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add New Key")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            
            // Form content
            VStack(alignment: .leading, spacing: 16) {
                // Type picker
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Type", selection: $selectedType) {
                        ForEach(store.supportedTypesOrDefault, id: \.self) { type in
                            Text(type.displayName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.automatic)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .onChange(of: selectedType) { _, newType in
                        // Reset value when type changes
                        resetValueForType(newType)
                    }
                }
                Divider()
                // Key name field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("Enter key name", text: $keyName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if canSave {
                                saveKey()
                            }
                        }
                }
                Divider()
                // Value input - consistent for all types
                VStack(alignment: .leading, spacing: 4) {
                    Text("Value")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if selectedType == .boolean {
                        VStack {
                            Picker("", selection: $boolValue) {
                                Text("false").tag(false)
                                Text("true").tag(true)
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(4)
                    } else if selectedType == .array || selectedType == .dictionary {
                        VStack(alignment: .leading, spacing: 4) {
                            TextEditor(text: $valueText)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 80)
                                .padding(4)
                                .background(Color(NSColor.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .onChange(of: valueText) { _, _ in
                                    validateCurrentInput()
                                }
                            
                            Text(selectedType == .array ? "Enter JSON array (e.g., [\"item1\", \"item2\"])" : "Enter JSON object (e.g., {\"key\": \"value\"})")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        TextField(placeholderForType(selectedType), text: $valueText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: valueText) { _, _ in
                                validateCurrentInput()
                            }
                            .onSubmit {
                                if canSave {
                                    saveKey()
                                }
                            }
                    }
                }
                
                // Validation error
                if let error = validationError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .padding(16)
            
            Spacer()
            
            // Footer
            HStack {
                Spacer()
                Button("Add Key") {
                    saveKey()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave || !viewModel.isConnected)
            }
            .padding(16)
        }
        .frame(maxWidth: 450, minHeight: 350)
        .onAppear {
            resetValueForType(selectedType)
        }
    }
    
    private var canSave: Bool {
        !keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        validationError == nil &&
        !keyExists
    }
    
    private var keyExists: Bool {
        store.entries.contains { $0.key == keyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private func placeholderForType(_ type: EchoKeyValueType) -> String {
        switch type {
        case .string: return "Enter text value"
        case .integer: return "Enter integer (e.g., 42)"
        case .double: return "Enter decimal (e.g., 3.14)"
        case .boolean: return "" // Not used since we use Toggle
        case .url: return "Enter URL (e.g., https://example.com)"
        case .date: return "Enter ISO8601 date"
        case .data: return "Enter base64 encoded data"
        default: return "Enter value"
        }
    }
    
    private func resetValueForType(_ type: EchoKeyValueType) {
        validationError = nil
        if type == .boolean {
            boolValue = false
        } else {
            valueText = defaultValuesByType[type] ?? ""
        }
    }
    
    private func validateCurrentInput() {
        validationError = nil
        
        if keyExists {
            validationError = "Key already exists"
            return
        }
        
        switch selectedType {
        case .integer:
            if Int(valueText) == nil {
                validationError = "Invalid integer value"
            }
        case .double:
            if Double(valueText) == nil {
                validationError = "Invalid decimal value"
            }
        case .array, .dictionary:
            if let error = validateJSON(valueText) {
                validationError = error
            }
        default:
            break
        }
    }
    
    private func validateJSON(_ jsonString: String) -> String? {
        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Empty JSON"
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            return "Invalid encoding"
        }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            
            // Additional validation based on expected type
            switch selectedType {
            case .array:
                if !(jsonObject is [Any]) {
                    return "Expected JSON array"
                }
            case .dictionary:
                if !(jsonObject is [String: Any]) {
                    return "Expected JSON object"
                }
            default:
                break
            }
            
            return nil // Valid JSON
        } catch {
            return "Invalid JSON: \(error.localizedDescription)"
        }
    }
    
    private func saveKey() {
        let trimmedKey = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else { return }
        guard validationError == nil else { return }
        
        do {
            let value = try createValueForType()
            viewModel.addKey(storeId: store.id, key: trimmedKey, value: value, type: selectedType)
            dismiss()
        } catch {
            validationError = "Error creating value: \(error.localizedDescription)"
        }
    }
    
    private func createValueForType() throws -> EchoCodableValue {
        let trimmedText = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch selectedType {
        case .string, .url, .date, .data:
            return .string(trimmedText)
            
        case .integer:
            guard let intValue = Int32(trimmedText) else {
                throw ValidationError.invalidInteger
            }
            return .integer(intValue)

        case .integer16:
            guard let intValue = Int16(trimmedText) else {
                throw ValidationError.invalidInteger
            }
            return .integer16(intValue)

        case .integer64:
            guard let intValue = Int64(trimmedText) else {
                throw ValidationError.invalidInteger
            }
            return .integer64(intValue)
        
        case .float:
            guard let floatValue = Float(trimmedText) else {
                throw ValidationError.invalidFloat
            }
            return .float(floatValue)

        case .double:
            guard let doubleVal = Double(trimmedText) else {
                throw ValidationError.invalidDouble
            }
            return .double(doubleVal)
            
        case .boolean:
            return .boolean(boolValue)
            
        case .array, .dictionary:
            guard let data = trimmedText.data(using: .utf8) else {
                throw ValidationError.invalidEncoding
            }
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            return EchoCodableValue(from: jsonObject)
            
        default:
            return .string(trimmedText)
        }
    }
    
    enum ValidationError: Error {
        case invalidInteger
        case invalidFloat
        case invalidDouble
        case invalidEncoding
        
        var localizedDescription: String {
            switch self {
            case .invalidInteger: return "Invalid integer value"
            case .invalidFloat: return "Invalid float value"
            case .invalidDouble: return "Invalid double value"
            case .invalidEncoding: return "Invalid text encoding"
            }
        }
    }
}
