import AppKit
import SwiftUI

struct PluginQuickLaunchView: View {
    @Environment(\.openWindow) var openWindow
    @State private var searchText: String = ""
    @State private var selectedIndex: Int? = nil
    let sessionViewModel: SessionViewModel
    @State var hotKeyEvent: Any? = nil

    var body: some View {
        ZStack {
            VisualEffectView(
                material: .popover,
                blendingMode: .behindWindow,
                state: .active,
                emphasized: true
            )
            VStack(spacing: 0) {
                searchField
                Divider().foregroundStyle(.tertiary)
                pluginList
                Divider().foregroundStyle(.tertiary)
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            hotKeyEvent = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if handleKeyDown(event: event, plugins: filteredPlugins) {
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let hotKeyEvent {
                NSEvent.removeMonitor(hotKeyEvent)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 0) {
            Text("􀊫")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
            TextField("Search", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(5)
                .font(.system(size: 24))
                .onChange(of: searchText) { _, _ in selectedIndex = 0 }
        }
        .background(.clear)
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    private var pluginList: some View {
        List(selection: $selectedIndex) {
            ForEach(filteredPlugins.indices, id: \.self) { index in
                let plugin = filteredPlugins[index]
                HStack {
                    plugin.icon.font(.title2).frame(width: 32)
                    Text(plugin.displayName).font(.title2)
                    if selectedIndex == index {
                        Spacer()
                        Text("􀅇")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.vertical, 8)
                .onTapGesture {
                    selectedIndex = index
                    sessionViewModel.selectPlugin(plugin.id)
                    clearSearchAndClosePanel()
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("􀆔+􀅇 to open in a new window.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(8)
        }
    }

    private var filteredPlugins: [LoadedPlugin] {
        sessionViewModel.enabledPlugins.filter { $0.displayName.lowercased().contains(searchText.lowercased()) }
    }

    private func handleKeyDown(event: NSEvent, plugins: [LoadedPlugin]) -> Bool {
        guard !plugins.isEmpty else { return false }

        switch event.keyCode {
        case 125: // Down arrow
            selectedIndex = (selectedIndex ?? -1) + 1 < plugins.count ? (selectedIndex ?? 0) + 1 : selectedIndex
            return true
        case 126: // Up arrow
            selectedIndex = (selectedIndex ?? 0) - 1 >= 0 ? (selectedIndex ?? 0) - 1 : 0
            return true
        case 36: // Return/Enter key
            if let currentIndex = selectedIndex, currentIndex < plugins.count {
                let selectedPlugin = plugins[currentIndex]
                if event.modifierFlags.contains(.command) {
                    openWindow(id: WindowID.plugin, value: selectedPlugin.id)
                } else {
                    sessionViewModel.selectPlugin(selectedPlugin.id)
                }
                clearSearchAndClosePanel()
            }
            return true
        default:
            return false
        }
    }

    private func clearSearchAndClosePanel() {
        searchText = ""
        sessionViewModel.showQuickLaunchPanel(false)
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State
    var emphasized: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        context.coordinator.visualEffectView
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        context.coordinator.update(
            material: material,
            blendingMode: blendingMode,
            state: state,
            emphasized: emphasized
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        let visualEffectView = NSVisualEffectView()

        init() {
            visualEffectView.blendingMode = .behindWindow
        }

        func update(
            material: NSVisualEffectView.Material,
            blendingMode: NSVisualEffectView.BlendingMode,
            state: NSVisualEffectView.State,
            emphasized: Bool
        ) {
            visualEffectView.material = material
        }
    }
}
