import SwiftUI

public struct TokenizedText: View {
    public let text: String
    public let color: Color?

    public init(text: String, color: Color?) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4.0)
    }
}
