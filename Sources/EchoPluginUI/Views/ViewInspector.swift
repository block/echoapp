import SwiftUI

/// This is a view that can be used for displaying the detail of selected item
///  Note: - It can be replaced with .inspector when the mini support version is macOS 14.0+
public extension View {
    func customInspector<PresentedContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> PresentedContent
    ) -> some View {
        modifier(CustomInspector(isPresented: isPresented, presentedContent: { content() }))
    }

    func itemInspector<Item, Content: View>(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item?) -> Content
    ) -> some View where Item: Identifiable {
        modifier(
            ItemInspector(item: item, onDismiss: onDismiss, content: { content(item.wrappedValue) })
        )
    }
}

// MARK: - Memory footprint

public struct CustomInspector<PresentedContent: View> {
    @Binding var isPresented: Bool
    let presentedContent: PresentedContent

    @State private var contentSize: CGSize = .zero

    private var inspectorContentWidth: CGFloat {
        return contentSize.width * 0.45
    }

    public init(
        isPresented: Binding<Bool>,
        @ViewBuilder presentedContent: () -> PresentedContent
    ) {
        _isPresented = isPresented
        self.presentedContent = presentedContent()
    }
}

public struct ItemInspector<Item, PresentedContent: View> {
    @Binding var item: Item?
    let presentedContent: PresentedContent
    let onDismiss: () -> Void

    @State private var contentSize: CGSize = .zero

    private var inspectorContentWidth: CGFloat {
        return contentSize.width * 0.45
    }

    public init(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> PresentedContent
    ) {
        _item = item
        self.onDismiss = onDismiss
        self.presentedContent = content()
    }
}

// MARK: - Rendering

extension CustomInspector: ViewModifier {
    public func body(content: Content) -> some View {
        ZStack {
            content
                .readSize($contentSize)

            inspectorContent
        }
    }

    private var inspectorContent: some View {
        HStack {
            Spacer()
            ZStack {
                HStack(spacing: 0) {
                    Divider()
                    Color.Echo.Inspector.background
                }
                presentedContent
                    .transition(.move(edge: .trailing))
            }
            .frame(width: inspectorContentWidth)
            .offset(x: isPresented ? 0 : inspectorContentWidth)
            .animation(.easeInOut(duration: 0.3), value: isPresented)
        }
    }
}

extension ItemInspector: ViewModifier {
    public func body(content: Content) -> some View {
        ZStack {
            content
                .readSize($contentSize)

            inspectorContent
        }
    }

    private var inspectorContent: some View {
        HStack {
            Spacer()
                .frame(maxWidth: 2.0, maxHeight: .infinity)
                .background(Color.black)

            ZStack {
                Color.Echo.Inspector.background

                VStack {
                    presentedContent
                        .transition(.move(edge: .trailing))
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                }
            }
            .frame(width: inspectorContentWidth)
            .offset(x: item != nil ? 0 : inspectorContentWidth)
            .animation(.easeInOut(duration: 0.3), value: item != nil)
        }
    }
}
