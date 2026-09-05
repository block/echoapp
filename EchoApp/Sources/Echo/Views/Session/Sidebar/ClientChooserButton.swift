import EchoConnection
import SwiftUI

struct ClientChooserButton: View {
    let sessionViewModel: SessionViewModel

    var body: some View {
        Button(action: {
            sessionViewModel.navigateToScreen(.clientPicker)
        }) {
            HStack {
                HStack(spacing: 8) {
                    buttonIcon()
                    buttonText()
                    Spacer()
                }
                Circle()
                    .fill(sessionViewModel.connectedClient == nil ? Color.disconnected : Color.connected)
                    .frame(width: 10, height: 10)
            }
            .frame(height: 36)
            .padding(.horizontal, 10)
            .background(.bar)
            .cornerRadius(8)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 0)
    }

    // MARK: -

    private func buttonIcon() -> some View {
        Image(systemName: "apps.iphone")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 16, height: 16)
            .foregroundColor(.primary)
    }

    private func buttonText() -> some View {
        Group {
            if let connectedClient = sessionViewModel.connectedClient {
                VStack(alignment: .leading) {
                    Text(connectedClient.deviceName ?? connectedClient.deviceIdentifier.value)
                        .font(.system(size: 13))
                    Text(connectedClient.appIdentifier)
                        .font(.system(size: 9))
                }
            } else {
                Text("Select Device")
                    .font(.system(size: 13))
            }
        }
    }
}

// MARK: -

extension Color {
    public static let disconnected = Color(nsColor: .systemRed)
    public static let connected = Color(nsColor: .systemGreen)
}
