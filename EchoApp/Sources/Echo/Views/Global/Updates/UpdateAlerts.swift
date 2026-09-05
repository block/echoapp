import AppKit
import SwiftUI

// MARK: - Update Alert Container

struct UpdateAlertsContainer: ViewModifier {
    let appViewModel: AppViewModel

    func body(content: Content) -> some View {
        let updateState = appViewModel.updateState

        content
            .alert(
                "EchoApp \(updateState.availableUpdate?.version ?? "Update")",
                isPresented: .init(
                    get: { appViewModel.updateState.showingUpdateAlert != nil },
                    set: { _ in appViewModel.dismissUpdateAlert() }
                )
            ) {
                updateAlertButtons(for: appViewModel.updateState.showingUpdateAlert)
            } message: {
                updateAlertMessage(for: appViewModel.updateState.showingUpdateAlert)
            }
    }

    @ViewBuilder
    private func updateAlertButtons(
        for alertType: AppState.UpdateState.UpdateAlert?
    ) -> some View {
        switch alertType {
        case .noUpdatesAvailable, .updateError:
            Button("OK") {
                appViewModel.dismissUpdateAlert()
            }
        case let .updateRedirect(_, buttonTitle, url):
            Button(buttonTitle) {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
                NSApplication.shared.terminate(nil)
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func updateAlertMessage(for alertType: AppState.UpdateState.UpdateAlert?) -> some View {
        switch alertType {
        case .noUpdatesAvailable:
            Text("You are running the latest version of EchoApp.")
        case let .updateError(message):
            Text(message)
        case let .updateRedirect(message, _, _):
            Text(message)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - View Extension

extension View {
    func updateAlerts(appViewModel: AppViewModel) -> some View {
        modifier(UpdateAlertsContainer(appViewModel: appViewModel))
    }
}
