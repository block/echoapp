import EchoPluginAPI
import SwiftUI

public struct RowInspector<Footer: View>: View {
    var row: EchoTableRow?
    let languageForKeys: [String: String]
    let titleKey: String?
    let itemLabel: String
    let footer: (EchoTableRow?) -> Footer

    public init(
        row: EchoTableRow? = nil,
        titleKey: String?,
        languageForKeys: [String: String],
        itemLabel: String = "item",
        @ViewBuilder footer: @escaping (EchoTableRow?) -> Footer
    ) {
        self.row = row
        self.titleKey = titleKey
        self.languageForKeys = languageForKeys
        self.itemLabel = itemLabel
        self.footer = footer
    }

    public var body: some View {
        if let row {
            VStack(spacing: 0) {
                // Header
                if let titleKey, let title = row.columnItems[titleKey] {
                    HStack(alignment: .center) {
                        Text(title)
                            .font(.headline)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
                // Body
                ScrollView {
                    ForEach(row.columnItems.sorted(by: <).filter { $0.key != titleKey}, id: \.key) { key, value in
                        VStack(alignment: .leading) {
                            highlightedSyntaxViewForValue(key: key, value: value)
                        }
                        Divider().padding(.vertical, 8)
                    }
                }
                // Footer
                footer(row)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EchoNullStateView(
                iconName: "filemenu.and.cursorarrow",
                message: "Select a row to view its details"
            )
        }
    }

    private func highlightedSyntaxViewForValue(key: String, value: String) -> HighlightedSyntaxView {
        let language = languageForKeys[key] ?? "json"
        let formattedValue: String = language == "json" ? value.prettyPrintedJSONString : value
        return HighlightedSyntaxView(
            code: formattedValue,
            language: language,
            headerLabel: key
        )
    }
}
