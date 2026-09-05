import SwiftUI

struct AppAlertView: View {
    let sessionViewModel: SessionViewModel

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .alert(
                "\(sessionViewModel.errorState?.title ?? "Error")",
                isPresented: .init(
                    get: { sessionViewModel.errorState != nil },
                    set: { _ in }
                )
            ) {
                if let button = sessionViewModel.errorState?.secondaryButton {
                    Button(button.title, role: button.role) {
                        handleButtonAction(button.action)
                    }
                }
                if let button = sessionViewModel.errorState?.primaryButton {
                    Button(button.title, role: button.role) {
                        handleButtonAction(button.action)
                    }
                }
            } message: {
                if let error = sessionViewModel.errorState {
                    Text(error.message)
                }
            }
    }

    private func handleButtonAction(_ action: ErrorState.Button.Action) {
        switch action {
        case .dismiss:
            sessionViewModel.dismissError()
        case .quit:
            sessionViewModel.quit()
        case .restart:
            sessionViewModel.restart()
        case let .openURL(url):
            sessionViewModel.openURL(url)
        }
    }
}
