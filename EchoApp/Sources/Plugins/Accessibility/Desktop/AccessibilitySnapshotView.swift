import SwiftUI

struct AccessibilitySnapshotView: View {
    @ObservedObject var viewModel: AccessibilityViewModel

    var body: some View {
        if let snapshot = viewModel.currentSnapshot,
           let image = NSImage(data: snapshot.imageData) {
            GeometryReader { geo in
                SnapshotView(
                    viewModel: viewModel,
                    image: image,
                    size: geo.size,
                    snapshot: snapshot
                )
            }
        } else {
            InitialView(viewModel: viewModel)
        }
    }
}

// MARK: - Private Views

private extension AccessibilitySnapshotView {
    private struct InitialView: View {
        @ObservedObject var viewModel: AccessibilityViewModel

        var body: some View {
            Button(
                action: viewModel.takeSnapshot,
                label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take a Snapshot")
                    }
                    .foregroundColor(.secondary)
                }
            )
            .help("Capture the current screen")
        }
    }

    private struct SnapshotView: View {
        @ObservedObject var viewModel: AccessibilityViewModel
        let image: NSImage
        let size: CGSize
        let snapshot: Snapshot

        var body: some View {
            let scaleData = viewModel.calculateScaleData(for: image, in: size)
            Group {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        ForEach(snapshot.elements.indices, id: \.self) { index in
                            let element = snapshot.elements[index]
                            Overlay(
                                color: Overlay.colors[index % Overlay.colors.count],
                                isSelected: viewModel.isSelected(element)
                            )
                            .frame(
                                width: element.frame.width * scaleData.scale,
                                height: element.frame.height * scaleData.scale
                            )
                            .position(
                                x: scaleData.xOffset + (element.frame.x * scaleData.scale),
                                y: scaleData.yOffset + (element.frame.y * scaleData.scale)
                            )
                            .onTapGesture {
                                viewModel.selectedAccessibilityElement = element
                            }
                        }
                    )
                    .frame(width: scaleData.imageWidth, height: scaleData.imageHeight)
                    .clipped()
                    .contentShape(Rectangle()) // Restricts tap area to the image bounds; ignores taps outside image
                    .position(
                        x: scaleData.xOffset + scaleData.imageWidth / 2,
                        y: scaleData.yOffset + scaleData.imageHeight / 2
                    )
            }
        }
    }

    private struct Overlay: View {
        static let colors: [Color] = [ .cyan, .magenta, .green, .blue, .yellow, .purple, .orange ]

        @State private var isHovering: Bool = false
        let color: Color
        let isSelected: Bool

        var body: some View {
            Rectangle()
                .fill(color.opacity(0.5))
                .overlay(
                    Rectangle()
                        .fill(.black.opacity(isSelected ? 0.4 : 0.2))
                        .opacity(isHovering || isSelected ? 1 : 0)
                )
                .overlay(
                    Rectangle()
                        .strokeBorder(.blue, lineWidth: 4)
                        .opacity(isHovering || isSelected ? 1 : 0)
                        .drawingGroup()
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .drawingGroup()
        }
    }
}
