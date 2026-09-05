import EchoPluginUI
import SwiftUI

struct Scope: Identifiable, Hashable {
    let id = UUID()
    let value: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

final class AppInfoViewModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var selectedEntry: Entry.ID?
    @Published public var searchText = ""

    var scopes: [Scope] {
        let set = Set(filteredEntries.compactMap { $0.scope })
        return set.map { Scope(value: $0) }.sorted { a, b in
            a.value < b.value
        }
    }

    var filteredEntries: [Entry] {
        guard !searchText.isEmpty else {
            return entries
        }
        let lowercasedSearchText = searchText.lowercased()
        return entries.filter { entry in
            entry.key.lowercased().contains(lowercasedSearchText) ||
            entry.value.lowercased().contains(lowercasedSearchText)
        }.sorted { a, b in
            a.key < b.key
        }
    }

    init() {}
}

struct AppInfoView: View {
    @StateObject var viewModel: AppInfoViewModel

    var body: some View {
        if viewModel.filteredEntries.isEmpty {
            EchoNullStateView(
                iconName: "bolt.horizontal.circle",
                message: "Connect to a device that supports this plugin."
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 400, maximum: 800))],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(viewModel.scopes) { scope in
                            VStack(alignment: .leading, spacing: 0) {
                                let scopedEntries = viewModel.filteredEntries.filter { $0.scope == scope.value }
                                HStack {
                                    Text(scope.value)
                                        .foregroundColor(.secondaryLabel)
                                    Spacer()
                                    Text("\(scopedEntries.count) item\(scopedEntries.count == 1 ? "" : "s")")
                                        .foregroundColor(.secondaryLabel)
                                        .help("items")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.0, opacity: 0.1))
                                HStack(alignment: .top, spacing: 10) {
                                    VStack(alignment: .trailing) {
                                        ForEach(scopedEntries) { entry in
                                            Text(entry.key)
                                                .frame(height: 20)
                                                .foregroundColor(Color.secondary)
                                        }
                                    }
                                    VStack(alignment: .leading) {
                                        ForEach(scopedEntries) { entry in
                                            HStack(alignment: .center) {
                                                Text(entry.value)
                                                CopyButton(
                                                    buttonStyle: .init(
                                                        textColor: .quaternaryLabel,
                                                        hoverTextColor: .link
                                                    )
                                                ) { pasteboard in
                                                    pasteboard.setString(entry.value, forType: .string)
                                                }
                                            }
                                            .frame(height: 20)
                                        }
                                    }
                                }
                                .padding(20)
                                Spacer()
                            }
                            .frame(maxHeight: .infinity)
                            .background(Color(white: 0.0, opacity: 0.05))
                            .cornerRadius(10.0)
                        }
                    }
                    .searchable(text: $viewModel.searchText)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
