import SwiftUI

public extension View {
    /// read the child view frame into a store
    func readSize(_ to: Binding<CGSize>) -> some View {
        ViewSizeReader(size: to, content: { self })
    }
}

// MARK: - Memory layout

public struct ViewSizeReader<Content: View> {
    @Binding var size: CGSize
    let content: () -> Content

    public init(size: Binding<CGSize>,
                @ViewBuilder content: @escaping () -> Content
    ) {
        _size = size
        self.content = content
    }
}

// MARK: - Rendering

extension ViewSizeReader: View {

    public var body: some View {
        ZStack(alignment: .top) {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                self.size = proxy.size
                            }
                            .preference(key: SizePreferenceKey.self, value: proxy.size)
                    }
                )
        }
        .onPreferenceChange(SizePreferenceKey.self) { preferences in
            self.size = preferences
        }
    }
}

// MARK: - Preference keys

public struct SizePreferenceKey: PreferenceKey {
    public typealias Value = CGSize
    public static var defaultValue: Value = .zero

    public static func reduce(value _: inout Value, nextValue: () -> Value) {
        _ = nextValue()
    }
}
