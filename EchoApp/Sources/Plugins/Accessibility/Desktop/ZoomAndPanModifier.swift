import SwiftUI

/// Adds zoom and pan gesture support to a view
struct ZoomAndPanModifier: ViewModifier {

    // MARK: - Properties

    @ObservedObject var viewModel: AccessibilityViewModel
    @GestureState private var panOffset: CGSize = .zero

    // MARK: -

    func body(content: Content) -> some View {
        content
            .scaleEffect(viewModel.scale)
            .offset(
                x: viewModel.position.width + panOffset.width,
                y: viewModel.position.height + panOffset.height
            )
            .gesture(gesture)
    }

    // MARK: -

    private var gesture: some Gesture {
        DragGesture()
            .updating($panOffset) { value, state, transaction in
                state = value.translation
            }
            .onEnded { value in
                viewModel.position.width += value.translation.width
                viewModel.position.height += value.translation.height
            }
            .simultaneously(with: MagnificationGesture()
                .onChanged { value in
                    guard let initialScale = viewModel.initialScale else {
                        viewModel.initialScale = viewModel.scale
                        return
                    }
                    viewModel.scale = constrainScale(initialScale * value)
                }
                .onEnded { value in
                    guard let initialScale = viewModel.initialScale else { return }
                    viewModel.scale = constrainScale(initialScale * value)
                    viewModel.initialScale = nil
                }
            )
    }

    // MARK: - Private Methods

    private func constrainScale(_ scale: CGFloat) -> CGFloat {
        min(
            max(scale, AccessibilityViewModel.Toolbar.sliderRange.lowerBound),
            AccessibilityViewModel.Toolbar.sliderRange.upperBound
        )
    }
}
