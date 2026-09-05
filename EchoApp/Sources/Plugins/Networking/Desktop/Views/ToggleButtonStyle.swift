import SwiftUI

struct ToggleButtonStyle: ButtonStyle {
    @State var isHovered = false
    let isSelected: Bool

    func makeBody(configuration: Self.Configuration) -> some View {
        let highlighted = isSelected || configuration.isPressed
        let foregroundColor = highlighted ? Color.accentColor : Color.primary

        return configuration.label
            .animation(.default, value: isHovered)
            .imageScale(.large)
            .onHover { isHovered in
                withAnimation {
                    self.isHovered = isHovered
                }
            }
            .padding(6)
            .background(.quinary.opacity(isHovered || highlighted ? 1.0 : 0))
            .foregroundStyle(foregroundColor)
            .buttonBorderShape(.roundedRectangle)
            .clipShape(.buttonBorder)
    }

}
