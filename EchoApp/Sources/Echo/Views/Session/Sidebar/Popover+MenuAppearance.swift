import SwiftUI

/// A view that emulates a section header that would normally appear in a Menu.
/// Useful in popovers to emulate Menus with dynamic content.
struct MenuSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }
}

// MARK: -

/// A view that emulates a row that would normally appear in a Menu.
/// Useful in popovers to emulate Menus with dynamic content.
struct MenuRow: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(MenuRowStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
    }

    private struct MenuRowStyle: ButtonStyle {
        let isHovering: Bool

        func makeBody(configuration: Configuration) -> some View {
            let bg: AnyShapeStyle = configuration.isPressed
            ? AnyShapeStyle(.tint.opacity(0.8))
            : (isHovering ? AnyShapeStyle(.primary.opacity(0.08)) : AnyShapeStyle(.clear))

            let fg = configuration.isPressed
                ? Color(nsColor: .selectedMenuItemTextColor)
                : Color.primary

            return configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(bg)
                )
                .foregroundStyle(fg)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: -

/// Emulates disabled text that would normally appear in a Menu.
/// Useful in popovers to emulate Menus with dynamic content.
struct MenuDisabledText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .opacity(0.6)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}
