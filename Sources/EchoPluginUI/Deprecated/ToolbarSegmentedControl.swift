import SwiftUI

public protocol ToolbarSegmentedControlItemProtocol: Identifiable, Hashable {
    var id: String { get }
    var systemImage: String? { get }
    var title: String { get }
}

@available(*, deprecated, message: "This component is deprecated, use EchoNavigationPickerView instead.")
public struct ToolbarSegmentedControl<T: ToolbarSegmentedControlItemProtocol>: View {
    public let items: [T]
    @Binding var selection: T
    public let badgeProvider: ((T) -> Int)?
    
    private let dividerHeight: CGFloat = 16.0
    private let dividerWidth: CGFloat = 1.0

    public init(
        items: [T],
        selection: Binding<T>,
        badgeProvider: ((T) -> Int)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.badgeProvider = badgeProvider
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(items) { item in
                ToolbarSegmentedControlItem(
                    icon: item.systemImage,
                    title: item.title,
                    badgeCount: badgeProvider?(item) ?? 0,
                    isSelected: Binding(
                        get: { selection.id == item.id },
                        set: { isSelected in
                            if isSelected { selection = item }
                        }
                    )
                ) {
                    selection = item
                }

                if items.last != item {
                    dividerView(isVisible: !isAdjacentOrEqual(selection: selection, item: item))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cornerRadius(EchoTheme.CornerRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium)
                .stroke(EchoTheme.Colors.hoverBackground, lineWidth: 1)
        )
    }

    private func dividerView(isVisible: Bool) -> some View {
        Rectangle()
            .frame(width: dividerWidth, height: dividerHeight)
            .foregroundStyle(EchoTheme.Colors.hoverBackground)
            .opacity(isVisible ? 1.0 : 0.0)
    }

    private func isAdjacentOrEqual(selection: T, item: T) -> Bool {
        guard let selectionIndex = items.firstIndex(of: selection),
              let itemIndex = items.firstIndex(of: item) else {
            return false
        }
        return [selectionIndex, selectionIndex-1].contains(itemIndex)
    }
}

public struct ToolbarSegmentedControlItem: View {
    let icon: String?
    let title: String
    var badgeCount: Int = 0
    @Binding var isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .center) {
                if badgeCount > 0 {
                    badgeView
                } else if let icon {
                    Image(systemName: icon)
                }
                text
            }
            .frame(height: EchoTheme.Spacing.large)
            .lineLimit(1)
            .padding(.horizontal, EchoTheme.Spacing.medium)
            .padding(.vertical, EchoTheme.Spacing.medium)
            .onHover { isHovering = $0 }
            .background(backgroundView)
            .cornerRadius(EchoTheme.CornerRadius.small)
        }
        .buttonStyle(.plain)
    }
    
    private var badgeView: some View {
        HStack(spacing: EchoTheme.Spacing.small) {
            if let icon {
                Image(systemName: icon)
            }
            Text("\(badgeCount)")
        }
        .padding(.vertical, EchoTheme.Spacing.small)
        .padding(.horizontal, EchoTheme.Spacing.small)
        .background(Color.red)
        .cornerRadius(EchoTheme.CornerRadius.small)
    }
    
    private var text: some View {
        Text(title)
            .font(.system(size: EchoTheme.FontSize.large, weight: .medium, design: .rounded))
            .foregroundColor(isSelected ? EchoTheme.Colors.selectedText : EchoTheme.Colors.text)
    }
    
    private var backgroundView: some View {
        Group {
            if isSelected {
                EchoTheme.Colors.selectedBackground
            } else if isHovering {
                EchoTheme.Colors.hoverBackground
            }
        }
    }
}
