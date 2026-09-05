import EchoPluginAPI
import EchoPluginUI
import SwiftUI
import AppKit

struct KeyValueEntryDetailView: View {
    let entry: EchoKeyValueEntry
    let store: EchoKeyValueStore
    let onUpdateValue: (String, String, EchoCodableValue, EchoKeyValueType) -> Void
    let onDeleteKey: (String, String) -> Void
    @ObservedObject var viewModel: KeyValueStoreViewModel
    
    @State private var editedValue: String = ""
    @State private var isEditing = false
    @State private var hasChanges = false
    @State private var showingHistory = false
    
    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.key)
                    .font(.headline)
                    .monospaced()
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                                
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 0) {
                            // Header is always shown
                            syntaxViewHeader
                            
                            // Content changes based on edit mode
                            if isEditing && entry.isEditable && !store.isReadOnly {
                                editableValueField
                            } else {
                                // Content without header (we provide our own)
                                if entry.type == .array || entry.type == .dictionary {
                                    HighlightedSyntaxView(
                                        code: entry.detailDisplayValue,
                                        language: "json",
                                        showHeader: false
                                    )
                                } else {
                                    HighlightedSyntaxView(
                                        code: entry.detailDisplayValue,
                                        language: languageForType(entry.type),
                                        showHeader: false
                                    )
                                }
                            }
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            detailMetadata()
            detailFooter()
        }
        .onAppear {
            editedValue = entry.detailDisplayValue
        }
        .onChange(of: entry.detailDisplayValue) { _, newValue in
            if !isEditing {
                editedValue = newValue
            }
        }
    }
    
    @ViewBuilder
    private var editableValueField: some View {
        switch entry.type {
        case .boolean:
            VStack {
                Picker("", selection: Binding(
                    get: {
                        hasChanges ?
                        editedValue == "true" :
                        entry.value == .boolean(true)
                    },
                    set: {
                        editedValue = String($0)
                        hasChanges = true
                    }
                )) {
                    Text("false").tag(false)
                    Text("true").tag(true)
                }
                .pickerStyle(.menu)
            }
            .padding(12)
        case .integer:
            TextEditor(text: Binding(
                get: { editedValue },
                set: { 
                    editedValue = $0
                    hasChanges = true 
                }
            ))
            .scrollIndicators(.hidden)
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(minHeight: 60)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 0))
            
        case .double:
            TextEditor(text: Binding(
                get: { editedValue },
                set: { 
                    editedValue = $0
                    hasChanges = true 
                }
            ))
            .scrollIndicators(.hidden)
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(minHeight: 60)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 0))
            
        case .array, .dictionary:
            TextEditor(text: Binding(
                get: { editedValue },
                set: { 
                    editedValue = $0
                    hasChanges = true 
                }
            ))
            .scrollIndicators(.hidden)
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(minHeight: 150)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 0))
            
        default:
            TextEditor(text: Binding(
                get: { editedValue },
                set: { 
                    editedValue = $0
                    hasChanges = true 
                }
            ))
            .scrollIndicators(.hidden)
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(minHeight: 80)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }
    
    private var syntaxViewHeader: some View {
        HStack {
            // Type label on the left
            Text(entry.formattedType)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Buttons on the right - different based on editing state
            if isEditing && entry.isEditable && !store.isReadOnly {
                HStack(spacing: 8) {
                    // JSON validation warning (for arrays/dictionaries)
                    if (entry.type == .array || entry.type == .dictionary) && hasChanges && validateJSON(editedValue) != nil {
                        Text("Invalid JSON")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if hasChanges {
                        Button("Save") {
                            saveChanges()
                        }
                        .buttonStyle(HoverButtonStyle(
                            textColor: .white,
                            backgroundColor: .accentColor,
                            hoverTextColor: .white,
                            hoverBackgroundColor: .accentColor.opacity(0.8)
                        ))
                        .disabled((entry.type == .array || entry.type == .dictionary) && validateJSON(editedValue) != nil)
                        .opacity((entry.type == .array || entry.type == .dictionary) && validateJSON(editedValue) != nil ? 0.5 : 1.0)
                    }
                    
                    Button("Cancel") {
                        editedValue = entry.detailDisplayValue
                        hasChanges = false
                        isEditing = false
                    }
                    .buttonStyle(HoverButtonStyle(
                        textColor: .controlText,
                        backgroundColor: .clear,
                        hoverTextColor: .link,
                        hoverBackgroundColor: Color(white: 0.5, opacity: 0.2)
                    ))
                }
            } else {
                HStack(spacing: 8) {
                    if entry.isEditable && !store.isReadOnly {
                        Button("Edit") {
                            isEditing = true
                            editedValue = entry.detailDisplayValue
                            hasChanges = false
                        }
                        .buttonStyle(HoverButtonStyle())
                    }
                    
                    Button("Copy") {
                        copyToClipboard(entry.detailDisplayValue)
                    }
                    .buttonStyle(HoverButtonStyle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.quaternarySystemFill))
        .overlay(
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func saveChanges() {
        // Convert editedValue back to appropriate type and save
        do {
            let convertedValue = try convertStringToValue(editedValue, type: entry.type)
            onUpdateValue(store.id, entry.key, convertedValue, entry.type)
            isEditing = false
            hasChanges = false
        } catch {
            // Show error to user
            // TODO: Implement error display
        }
    }
    
    private func convertStringToValue(_ string: String, type: EchoKeyValueType) throws -> EchoCodableValue {
        switch type {
        case .string: 
            return .string(string)
        case .integer: 
            guard let value = Int32(string) else {
                throw EchoKeyValueStoreError.invalidType("Invalid integer32: \(string)")
            }
            return .integer(value)
        case .integer16:
            guard let value = Int16(string) else {
                throw EchoKeyValueStoreError.invalidType("Invalid integer16: \(string)")
            }
            return .integer16(value)
        case .integer64:
            guard let value = Int64(string) else {
                throw EchoKeyValueStoreError.invalidType("Invalid integer64: \(string)")
            }
            return .integer64(value)
        case .float:
            guard let value = Float(string) else {
                throw EchoKeyValueStoreError.invalidType("Invalid float: \(string)")
            }
            return .float(value)
        case .double:
            guard let value = Double(string) else {
                throw EchoKeyValueStoreError.invalidType("Invalid double: \(string)")
            }
            return .double(value)
        case .boolean: 
            guard let value = Bool(string) else {
                throw EchoKeyValueStoreError.invalidType("Invalid boolean: \(string)")
            }
            return .boolean(value)
        case .array, .dictionary:
            // Try to parse as JSON
            guard let data = string.data(using: .utf8) else {
                throw EchoKeyValueStoreError.invalidType("Invalid UTF8 string")
            }
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            return EchoCodableValue(from: jsonObject)
        default: 
            return .string(string)
        }
    }
    
    // MARK: - Helper Functions
    
    private func editableDisplayValue(for entry: EchoKeyValueEntry) -> String {
        switch entry.type {
        case .array, .dictionary:
            // For arrays and dictionaries, return the pretty-printed JSON
            return entry.detailDisplayValue
        default:
            // For simple types, return the raw value for editing
            return entry.detailDisplayValue
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
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return nil // Valid JSON
        } catch {
            return "Invalid JSON: \(error.localizedDescription)"
        }
    }
    
    private func formatJSON() {
        guard let data = editedValue.data(using: .utf8) else { return }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            
            if let formattedString = String(data: formattedData, encoding: .utf8) {
                editedValue = formattedString
                hasChanges = true
            }
        } catch {
            // JSON is invalid, don't format
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func iconForType(_ type: EchoKeyValueType) -> String {
        switch type {
        case .string: return "textformat"
        case .integer, .integer16, .integer64: return "number"
        case .float, .double: return "number.circle"
        case .boolean: return "switch.2"
        case .data: return "doc.on.doc"
        case .date: return "calendar"
        case .array: return "list.bullet"
        case .dictionary: return "curlybraces"
        case .url: return "link"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func colorForType(_ type: EchoKeyValueType) -> Color {
        switch type {
        case .string: return .blue
        case .integer, .integer16, .integer64, .float, .double: return .green
        case .boolean: return .purple
        case .data: return .orange
        case .date: return .red
        case .array: return .indigo
        case .dictionary: return .teal
        case .url: return .cyan
        case .unknown: return .gray
        }
    }
    
    private func languageForType(_ type: EchoKeyValueType) -> String {
        switch type {
        case .array, .dictionary: return "json"
        case .url: return "http"
        case .data: return "base64"
        default: return "text"
        }
    }
    
        // MARK: - Helper Views
    
    func detailMetadata() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lastModified = entry.lastModified {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Modified")
                        .foregroundColor(.secondary)
                    Text(lastModified.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.body, design: .monospaced))
                }
            }
            
            if !entry.modificationHistory.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Modification History")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(showingHistory ? "Hide" : "Show") {
                            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                                showingHistory.toggle()
                            } else {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showingHistory.toggle()
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    
                    if showingHistory {
                        modificationHistoryView
                    }
                }
            }
        }
    }
    
    func detailFooter() -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center) {
                HStack {
                    Text("Type")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text(entry.formattedType)
                        .font(.callout)
                        .bold()
                    Spacer()
                }
                Spacer()
                if entry.isEditable && !store.isReadOnly {
                    Button("Delete Entry") {
                        onDeleteKey(store.id, entry.key)
                    }
                    .font(.body)
                    .foregroundColor(.red)
                    .buttonStyle(FooterButtonStyle())
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 16.0)
        }
    }

    @ViewBuilder
    private var modificationHistoryView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // Show most recent first
                ForEach(entry.modificationHistory.reversed()) { modification in
                    modificationRow(modification)
                }
            }
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }
    
    @ViewBuilder
    private func modificationRow(_ modification: EchoValueModification) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Source badge
                Text(modification.source.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(sourceColor(for: modification.source).opacity(0.2))
                    .foregroundColor(sourceColor(for: modification.source))
                    .cornerRadius(4)
                
                Spacer()
                
                // Timestamp
                Text(modification.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Change description
            Text(modification.changeDescription)
                .font(.caption)
                .foregroundColor(.primary)
            
            // Value change (if not too long)
            if let oldValue = modification.oldValue,
               oldValue.displayValue.count < 50 &&
               modification.newValue.displayValue.count < 50 {
                HStack(spacing: 4) {
                    Text(oldValue.displayValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .strikethrough()
                    
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(modification.newValue.displayValue)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }
    
    private func sourceColor(for source: EchoValueModification.ModificationSource) -> Color {
        switch source {
        case .app: return .blue
        case .desktop: return .green
        case .system: return .orange
        case .unknown: return .gray
        }
    }
}
