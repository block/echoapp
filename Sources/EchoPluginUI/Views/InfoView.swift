import SwiftUI

public struct InfoView: View {

    let title: String
    let subtitle: String?

    public init(title: String, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(.callout))
                .bold()
            if let subtitle {
                Text(subtitle)
                    .multilineTextAlignment(.center)
                    .font(.system(.caption2))
            }
        }
        .padding(20)
        .background(
            Color.controlBackground.cornerRadius(8).opacity(0.2)
        )
    }
}
