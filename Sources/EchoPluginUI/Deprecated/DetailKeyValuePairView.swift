import Foundation
import Highlight
import SwiftUI

// These are common UI elements that can be moved out into a common area that
// can be used by other plugins

public struct DetailKeyContentPairView<Content: View>: View {
    public let key: String
    public let direction: Axis
    public let content: () -> Content
    private let keyWidth: CGFloat

    public init(
        key: String,
        keyWidth: CGFloat = 65,
        direction: Axis = .horizontal,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.key = key
        self.keyWidth = keyWidth
        self.direction = direction
        self.content = content
    }

    public var body: some View {
        switch direction {
        case .horizontal:
            HStack(alignment: .top, spacing: 8) {
                Text("\(key)")
                    .font(.system(.callout, design: .rounded))
                    .frame(minWidth: keyWidth, maxWidth: keyWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                content()
                Spacer()
            }
            .padding(4.0)
        case .vertical:
            VStack(alignment: .leading, spacing: 8) {
                Text("\(key)")
                    .font(.system(.callout, design: .rounded))
                content()
            }
            .padding(4.0)
        }
    }
}

public struct DetailKeyValuePairView: View {
    public let key: String
    public let value: String
    public let valueColor: SwiftUI.Color?
    public var isSelected: Bool

    public init(key: String, value: String, valueColor: SwiftUI.Color?, isSelected: Bool) {
        self.key = key
        self.value = value
        self.valueColor = valueColor
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(key)")
                .font(.system(.callout, design: .rounded))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(4)
                .frame(minWidth: 40, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .rounded))
                .bold()
                .foregroundColor(.primary)
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let valueColor {
                Circle()
                    .frame(width: 8.0, height: 8.0)
                    .foregroundColor(valueColor)
                    .padding(4)
            }
        }
        .padding(0)
    }
}

public struct DetailCodeBlockKeyValuePairView: View {
    public let key: String
    public let code: String
    public var language: String
    public let showHeader: Bool

    public init(
        key: String,
        code: String,
        language: String = "json",
        showHeader: Bool = true
    ) {
        self.key = key
        self.code = code
        self.language = language
        self.showHeader = showHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(key)")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .padding(4)
            HighlightedSyntaxView(
                code: code,
                language: language,
                showHeader: showHeader
            )
            .multilineTextAlignment(.leading)
            .layoutPriority(1)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0, opacity: 0.05))
            .cornerRadius(4)
        }
    }
}

public struct TimePair: View {
    public let duration: String

    public init(durationNs: String) {
        self.duration = DurationFormatter.string(from: durationNs)
    }

    public init(preFormattedDuration: String) {
        self.duration = preFormattedDuration
    }

    public var body: some View {
        HStack {
            Image(systemName: "clock")
            Text(duration)
        }
        .monospacedDigit()
        .lineLimit(1)
        .font(.system(.callout, design: .monospaced))
        .foregroundColor(.secondary)
    }
}

