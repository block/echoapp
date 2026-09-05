import ComposableArchitecture
import SwiftUI

struct FixturesView: View {
    let store: Store<AppState, AppAction>

    var body: some View {
        WithViewStore(store, observe: \.self) { viewStore in
            VStack(alignment: .leading) {
                if !viewStore.fixturesRepoPath.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Text(viewStore.fixturesRepoURL.path)
                            .font(.body)
                            .monospaced()

                        let fixtureCount = viewStore.responseFixtures.reduce(0, { $0 + $1.value.count })
                        Text("(\(fixtureCount) \(fixtureCount == 1 ? "file" : "files"))")
                            .font(.footnote)
                            .italic()
                    }
                }
                HStack {
                    chooseDirectoryButton()
                    openDirectoryButton()
                }
            }
        }
    }

    func chooseDirectoryButton() -> some View {
        WithViewStore(store, observe: \.fixturesRepoURL) { viewStore in
            Button("Choose Directory…") {
                let panel = NSOpenPanel()
                panel.directoryURL = viewStore.state
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false

                if panel.runModal() == .OK {
                    viewStore.send(.ui(.setFixturesRepoPath(panel.url?.path ?? "")))
                }
            }
        }
    }

    func openDirectoryButton() -> some View {
        WithViewStore(store, observe: \.fixturesRepoPath) { viewStore in
            Button("Open Directory") {
                let expanded = (viewStore.state as NSString).expandingTildeInPath
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
            }
            .disabled(viewStore.state.isEmpty)
        }
    }
}
