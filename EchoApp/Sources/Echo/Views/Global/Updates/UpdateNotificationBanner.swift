import SwiftUI
import AppKit
import EchoPluginUI

struct UpdateNotificationBanner: View {
    let update: Release
    let onInstall: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "gift")
                    Text("New Update Available")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Install Now") {
                        onInstall()
                    }
                    .buttonStyle(
                        FooterButtonStyle(
                            textColor: .primary,
                            backgroundColor: .accentColor,
                            hoverBackgroundColor: .link
                        )
                    )
                }
            }
        }
        .padding(12)
        .background(
            Color(NSColor.controlBackgroundColor)
                .overlay(Color.blue.opacity(0.08))
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1.0)
        )
        .frame(minWidth: 300, maxWidth: .infinity)
    }
}

struct UpdateNotificationBannerContainer: View {
    let availableUpdate: Release?
    let onInstall: () -> Void
    
    var body: some View {
        if let update = availableUpdate {
            UpdateNotificationBanner(
                update: update,
                onInstall: onInstall
            )
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: availableUpdate)
        }
    }
}
