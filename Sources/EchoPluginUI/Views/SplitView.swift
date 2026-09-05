import SwiftUI

public struct SplitView<LeftContent: View, RightContent: View>: View {

    let leftContent: () -> LeftContent
    let rightContent: () -> RightContent
    var leftWidthPercentage: CGFloat

    public init(
        @ViewBuilder leftContent: @escaping () -> LeftContent,
        @ViewBuilder rightContent: @escaping () -> RightContent,
        leftWidthPercentage: CGFloat = 0.5
    ) {
        self.leftContent = leftContent
        self.rightContent = rightContent
        self.leftWidthPercentage = leftWidthPercentage
    }

    public var body: some View {
        GeometryReader { geometry in
            let min = geometry.size.width * min(leftWidthPercentage, (1 - leftWidthPercentage))
            let max = geometry.size.width * max(leftWidthPercentage, (1 - leftWidthPercentage))

            HSplitView {
                leftContent()
                .frame(
                    minWidth: min,
                    idealWidth: geometry.size.width * leftWidthPercentage,
                    maxWidth: max,
                    maxHeight: .infinity
                )
                .layoutPriority(leftWidthPercentage > 0.5 ? 1 : 0)
                rightContent()
                .frame(
                    minWidth: min,
                    idealWidth: geometry.size.width * (1 - leftWidthPercentage),
                    maxWidth: max,
                    maxHeight: .infinity
                )
                .layoutPriority(leftWidthPercentage <= 0.5 ? 1 : 0)
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
