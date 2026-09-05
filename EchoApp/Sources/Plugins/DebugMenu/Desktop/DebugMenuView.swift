import DebugMenuPluginAPI
import EchoPluginUI
import SwiftUI

struct DebugMenuView: View {
    @StateObject private var viewModel: DebugMenuViewModel
    @State private var navigationPath: [String] = []

    init(viewModel: DebugMenuViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        if viewModel.sections.isEmpty {
            // Surface `errorMessage` here too — without this branch, snapshot
            // failures before any sections arrive collapse into generic
            // loading/empty copy and the actual reason is invisible.
            EchoNullStateView(
                iconName: "wrench.and.screwdriver",
                message: viewModel.errorMessage
                    ?? (viewModel.isLoading
                        ? "Loading debug menu..."
                        : "Connect a mobile app with a debug menu to view and control its settings.")
            )
        } else {
            NavigationStack(path: $navigationPath) {
                scrollContent
                    .searchable(text: $viewModel.searchText, prompt: "Search debug menu items")
                    .navigationDestination(for: String.self) { sectionId in
                        DebugMenuSectionDetailView(
                            viewModel: viewModel,
                            sectionId: sectionId,
                            onDrillIn: { navigationPath.append($0.id) }
                        )
                    }
            }
        }
    }

    // MARK: - Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let error = viewModel.errorMessage {
                    BannerView(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: .orange,
                        message: error,
                        backgroundColor: Color.orange.opacity(0.1)
                    ) {
                        viewModel.errorMessage = nil
                    }
                }

                if let result = viewModel.lastActionResult {
                    BannerView(
                        icon: result.success ? "checkmark.circle.fill" : "xmark.circle.fill",
                        iconColor: result.success ? .green : .red,
                        message: result.message ?? (result.success ? "Action completed" : "Action failed"),
                        backgroundColor: (result.success ? Color.green : Color.red).opacity(0.1)
                    ) {
                        viewModel.lastActionResult = nil
                    }
                }

                ForEach(viewModel.filteredSections) { section in
                    DebugMenuSectionCard(
                        viewModel: viewModel,
                        section: section,
                        onDrillIn: { navigationPath.append($0.id) }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Section Detail (pushed view)

struct DebugMenuSectionDetailView: View {
    @ObservedObject var viewModel: DebugMenuViewModel
    let sectionId: String
    let onDrillIn: (EchoDebugMenuSection) -> Void

    var body: some View {
        if let section = viewModel.findSection(id: sectionId) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    DebugMenuSectionCard(
                        viewModel: viewModel,
                        section: section,
                        onDrillIn: onDrillIn
                    )
                }
                .padding()
            }
            .navigationTitle(section.title)
        } else {
            Text("Section unavailable")
                .foregroundColor(.secondary)
                .padding()
        }
    }
}

// MARK: - Section Card

struct DebugMenuSectionCard: View {
    @ObservedObject var viewModel: DebugMenuViewModel
    let section: EchoDebugMenuSection
    let onDrillIn: (EchoDebugMenuSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = section.icon {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }
                Text(section.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(section.items.count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    DebugMenuItemRow(
                        viewModel: viewModel,
                        item: item,
                        onDrillIn: onDrillIn
                    )
                    if index < section.items.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

// MARK: - Item Row

struct DebugMenuItemRow: View {
    @ObservedObject var viewModel: DebugMenuViewModel
    let item: EchoDebugMenuItem
    let onDrillIn: (EchoDebugMenuSection) -> Void

    var body: some View {
        if case .subsection(let child) = item.type {
            Button {
                onDrillIn(child)
            } label: {
                HStack(spacing: 12) {
                    itemTitleStack
                    Spacer()
                    Text("\(child.items.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                itemTitleStack
                Spacer()
                leafControl
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var itemTitleStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.body)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let description = item.itemDescription, !description.isEmpty {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var leafControl: some View {
        switch item.type {
        case let .toggle(isOn):
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { viewModel.setToggle(itemId: item.id, isOn: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(!viewModel.isConnected)

        case let .picker(options, selectedIndex):
            Picker("", selection: Binding(
                get: { selectedIndex },
                set: { viewModel.selectOption(itemId: item.id, selectedIndex: $0) }
            )) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    Text(option).tag(index)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            .disabled(!viewModel.isConnected)

        case .action:
            Button {
                viewModel.executeAction(itemId: item.id)
            } label: {
                Text("Run")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isConnected)

        case let .textInput(value, placeholder):
            TextField(placeholder ?? "", text: Binding(
                get: { value },
                set: { viewModel.setTextValue(itemId: item.id, value: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)
            .disabled(!viewModel.isConnected)

        case .subsection:
            EmptyView()

        case let .info(value):
            if let value, !value.isEmpty {
                Text(value)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("on device")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - Banner

private struct BannerView: View {
    let icon: String
    let iconColor: Color
    let message: String
    let backgroundColor: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
            Text(message)
                .font(.callout)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(8)
    }
}
