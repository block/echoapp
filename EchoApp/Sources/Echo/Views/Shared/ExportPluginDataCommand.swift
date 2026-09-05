import Combine
import EchoPluginAPI
import SwiftUI
import UniformTypeIdentifiers
import os

struct ExportPluginDataCommand: Commands {
    @Environment(\.openWindow) var openWindow

    let appViewModel: AppViewModel
    private let logger = Logger(subsystem: "xyz.block.echoapp", category: "ExportPluginDataCommand")

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button {
                showImportPanel()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.square")
            }
            .keyboardShortcut("o", modifiers: [.command])

            if let activeSession = appViewModel.activeSession {
                Button {
                    activeSession.showExportPanel(selectedOnly: false)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }
    }

    private func showImportPanel() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType(filenameExtension: "echoarchive") ?? UTType.data]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.title = "Open Plugin Data Archive"
        openPanel.prompt = "Open"

        openPanel.begin { [openWindow, appViewModel, logger] response in
            if response == .OK, let url = openPanel.url {
                let sessionID = UUID()

                Task {
                    do {
                        try await PluginMessageCache.shared.importArchiveIntoCache(from: url)

                        await MainActor.run {
                            _ = appViewModel.createSession(
                                initialClient: nil,
                                sessionID: sessionID,
                                isImportedArchive: true,
                                archiveURL: url
                            )
                            openWindow(value: SessionWindow(id: sessionID))
                        }
                    } catch {
                        logger.error("Failed to import archive: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
