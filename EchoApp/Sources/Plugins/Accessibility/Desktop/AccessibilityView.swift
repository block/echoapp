import Combine
import EchoPluginAPI
import EchoPluginUI
import Foundation
import SwiftUI

public struct AccessibilityView: View {
    @StateObject private var viewModel: AccessibilityViewModel

    public init(viewModel: AccessibilityViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        SplitView(
            leftContent: {
                VStack(spacing: 16) {
                    AccessibilitySnapshotView(viewModel: viewModel)
                        .padding(.top, AccessibilityViewModel.Toolbar.height)
                        .modifier(ZoomAndPanModifier(viewModel: viewModel))
                    AccessibilityToolbarView(viewModel: viewModel)
                        .padding(.bottom, 16)
                }
            },
            rightContent: {
                if viewModel.currentSnapshot != nil {
                    AccessibilityDetailView(selectedElement: viewModel.selectedAccessibilityElement)
                }
            },
            leftWidthPercentage: 0.66
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Toggle("Live Updates", isOn: viewModel.sendLiveUpdatesBinding)
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 12)
                Spacer()
            }
            ToolbarItemGroup(placement: .automatic) {
                Button(action: viewModel.takeSnapshot) {
                    Image(systemName: "camera.fill")
                }
                .help("Capture the current screen")
                Spacer()
            }
            ToolbarItem(placement: .automatic) {
                Button(action: viewModel.launchAccessibilityInspector) {
                    Image(systemName: "magnifyingglass.circle.fill")
                }
                .help("Launch the Accessibility Inspector")
            }
        }
    }
}

// MARK: -

private struct AccessibilityToolbarView: View {
    @ObservedObject var viewModel: AccessibilityViewModel
    @State private var isHovered = false

    var body: some View {
        HStack {
            scaleSlider
            resetButton
        }
    }

    private var scaleSlider: some View {
        ZStack(alignment: .top) {
            sliderView
            if isHovered {
                scaleTooltip
            }
        }
        .onHover { hovering in
            withAnimation {
                isHovered = hovering
            }
        }
    }

    private var scaleTooltip: some View {
        Text(viewModel.scalePercentage)
            .foregroundStyle(.background)
            .frame(width: 50)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(capsuleShape)
            .offset(y: -24)
    }

    private var sliderView: some View {
        Slider(
            value: $viewModel.scale,
            in: AccessibilityViewModel.Toolbar.sliderRange
        )
        .padding(.horizontal, 16)
        .frame(
            width: AccessibilityViewModel.Toolbar.sliderWidth,
            height: AccessibilityViewModel.Toolbar.height
        )
        .background(capsuleShape)
    }

    private var resetButton: some View {
        Button(action: viewModel.resetView) {
            capsuleShape
                .overlay(
                    Image(systemName: "arrow.down.left.and.arrow.up.right")
                        .foregroundStyle(.background)
                )
        }
        .frame(
            width: AccessibilityViewModel.Toolbar.height,
            height: AccessibilityViewModel.Toolbar.height
        )
        .help("Reset View")
        .buttonStyle(.plain)
    }

    private var capsuleShape: some View {
        Capsule().fill(.primary.opacity(0.8))
    }
}
