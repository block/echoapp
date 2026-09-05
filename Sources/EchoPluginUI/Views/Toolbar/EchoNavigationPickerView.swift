import SwiftUI

/// A navigation picker styled like a segmented control, supporting icons and labels, hover highlighting, and system-like dividers.
///
/// Example usage:
/// ```swift
/// EchoToolbarNavigationPicker(
///     segments: [
///         (icon: "list.dash", label: "Flows", value: .debuggerView),
///         (icon: "doc.plaintext", label: "Docs", value: .documentationView),
///         (icon: "map", label: "Map", value: .scenarioPlanMapView)
///     ],
///     selection: $selectedTab
/// )
/// ```
public struct EchoToolbarNavigationPicker<T: Hashable>: View {
    public let segments: [(icon: String, label: String, value: T)]
    @Binding public var selection: T
    @State private var isHovered = false

    public init(segments: [(icon: String, label: String, value: T)], selection: Binding<T>) {
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments.indices, id: \.self) { idx in
                let segment = segments[idx]
                let isSelected = selection == segment.value

                segmentButton(segment: segment, isSelected: isSelected)

                if idx < segments.count - 1 {
                    dividerView(isSelected: isSelected, nextIsSelected: selection == segments[idx + 1].value)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium)
                .fill(isHovered ? EchoTheme.Colors.hoverBackground : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
    
    private func segmentButton(segment: (icon: String, label: String, value: T), isSelected: Bool) -> some View {
        Button(action: { selection = segment.value }) {
            HStack(spacing: EchoTheme.Spacing.small) {
                Image(systemName: segment.icon)
                Text(segment.label)
                    .lineLimit(1)
            }
            .padding(.vertical, EchoTheme.Spacing.medium)
            .padding(.horizontal, EchoTheme.Spacing.medium)
            .background(
                isSelected
                ? EchoTheme.Colors.selectedBackground
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium))
            .contentShape(RoundedRectangle(cornerRadius: EchoTheme.CornerRadius.medium))
            .foregroundColor(isSelected ? EchoTheme.Colors.selectedText : EchoTheme.Colors.text)
        }
        .buttonStyle(.plain)
    }
    
    private func dividerView(isSelected: Bool, nextIsSelected: Bool) -> some View {
        Rectangle()
            .fill(EchoTheme.Colors.text)
            .frame(width: 1, height: 16)
            .padding(.vertical, EchoTheme.Spacing.medium)
            .opacity(!isSelected && !nextIsSelected ? 0.2 : 0.0)
    }
} 
