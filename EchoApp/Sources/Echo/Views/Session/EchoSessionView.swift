import EchoPluginAPI
import EchoPluginUI
import Foundation
import SwiftUI

struct EchoSessionView: View {
    @Environment(\.openWindow) var openWindow

    let sessionId: UUID
    let appViewModel: AppViewModel
    let startupError: String?

    @State private var showingResetPluginAlert = false
    @State private var hasCreatedSession = false

    var body: some View {
        if let sessionViewModel = appViewModel.session(for: sessionId) {
            sessionView(sessionViewModel: sessionViewModel)
                .onAppear {
                    appViewModel.setActiveSession(sessionId)
                }
        } else {
            Color.clear
                .onAppear {
                    if !hasCreatedSession {
                        hasCreatedSession = true
                        _ = appViewModel.createSession(sessionID: sessionId)
                    }
                }
                .overlay {
                    Text("Loading Session...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private func sessionView(sessionViewModel: SessionViewModel) -> some View {
        NavigationSplitView(
            sidebar: {
                SidebarView(
                    pluginManager: sessionViewModel.pluginManager,
                    sessionViewModel: sessionViewModel,
                    availableUpdate: appViewModel.updateState.availableUpdate,
                    onInstallUpdate: {
                        appViewModel.performUpdate()
                    }
                )
            },
            detail: {
                detailView(sessionViewModel: sessionViewModel)
            }
        )
        .navigationSplitViewStyle(.automatic)
        .navigationTitle("EchoApp")
        .floatingPanel(
            isPresented: Binding(
                get: { sessionViewModel.isShowingPluginQuickLaunchView },
                set: { sessionViewModel.showQuickLaunchPanel($0) }
            )
        ) {
            PluginQuickLaunchView(sessionViewModel: sessionViewModel)
        }
        .floatingPanel(
            isPresented: Binding(
                get: { sessionViewModel.exportState.isShowingSavePanel },
                set: { _ in sessionViewModel.dismissExport() }
            )
        ) {
            ExportPanelView(sessionViewModel: sessionViewModel)
        }
        .overlay(AppAlertView(sessionViewModel: sessionViewModel))
        .alert("Disconnect & Reload Plugins?", isPresented: $showingResetPluginAlert) {
            Button("Reset", role: .destructive) {
                sessionViewModel.resetPlugins()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All of the plugin content will be wiped and you'll be prompted to reconnect your client afterwards.")
        }
        .onDisappear {
            appViewModel.destroySession(sessionId)
        }
    }

    @ViewBuilder
    private func detailView(sessionViewModel: SessionViewModel) -> some View {
        switch sessionViewModel.currentScreen {
        case .clientPicker:
            if !sessionViewModel.isImportedArchive {
                ClientPickerView(sessionViewModel: sessionViewModel, appViewModel: appViewModel, port: sessionViewModel.port)
            } else {
                ArchivePlaceholderView()
            }
        case .main:
            if let plugin = sessionViewModel.selectedPlugin?.plugin {
                plugin.makeView()
                    .navigationTitle(plugin.metadata.displayName)
            } else {
                if sessionViewModel.isImportedArchive {
                    ArchivePlaceholderView()
                } else {
                    ClientPickerView(sessionViewModel: sessionViewModel, appViewModel: appViewModel, port: sessionViewModel.port)
                }
            }
        }
    }
}

// MARK: - Archive Placeholder View

struct ArchivePlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Viewing Archived Data")
                .font(.title2)
                .fontWeight(.medium)

            Text("Select a plugin from the sidebar to view cached data")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Extension

extension View {
    func touch(_ block: () -> Void) -> Self {
        block()
        return self
    }
}
