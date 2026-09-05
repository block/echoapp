import AppKit
import Foundation
import SwiftUI

/// A content-following list view that automatically scrolls to new content and provides a follow button when scrolled away.
///
/// ## Type Safety Guidelines
///
/// To ensure type safety with `selectedId`, follow these guidelines:
///
/// 1. Make sure your content items conform to `Identifiable`
/// 2. Use `.id()` modifier on your `ForEach` items
/// 3. Pass the same ID type as `selectedId`
///
/// ## Example Usage
///
/// ```swift
/// struct MyItem: Identifiable {
///     let id: UUID
///     let title: String
/// }
///
/// EchoListView(
///     contentCount: items.count,
///     selectedId: selectedItem?.id, // Type-safe: Item.ID
///     nullState: { Text("No items") }
/// ) {
///     ForEach(items) { item in
///         Text(item.title)
///             .id(item.id) // Required for proper selection
///     }
/// }
/// ```
///
/// ## Features
///
/// - **Auto-following**: Automatically scrolls to new content when added
/// - **Follow button**: Appears when user scrolls away from bottom
/// - **Keyboard navigation**: Supports arrow key navigation
/// - **Null state**: Shows custom view when no content is available
public struct EchoListView<Content: View, NullState: View>: View {
    let content: () -> Content
    let nullState: () -> NullState
    let contentCount: Int
    let selectedId: AnyHashable?
    let onNavigateUp: (() -> Void)?
    let onNavigateDown: (() -> Void)?
    let onScrollViewReady: ((ScrollViewProxy) -> Void)?
    
    @State private var isFollowing: Bool = true
    @State private var isBottomVisible: Bool = true
    @State private var isAutoScrolling: Bool = false
    @State private var scrollViewHeight: CGFloat = 0
    @State private var bottomAnchorY: CGFloat = 0
    
    /// Creates a content-following list view with automatic scrolling and follow button functionality.
    ///
    /// - Parameters:
    ///   - contentCount: The total number of items in the list. Used to determine when to show the null state and follow button.
    ///   - selectedId: The currently selected item's ID. When this changes, the view will stop following new content.
    ///   - onNavigateUp: Optional callback called when the up arrow key is pressed. Use this to move selection to the previous item.
    ///   - onNavigateDown: Optional callback called when the down arrow key is pressed. Use this to move selection to the next item.
    ///   - onScrollViewReady: Optional callback that provides access to the `ScrollViewProxy` when the scroll view is ready. Use this to perform custom scrolling operations.
    ///   - nullState: A view builder that creates the content to display when `contentCount` is zero.
    ///   - content: A view builder that creates the main list content. Make sure to use `.id()` on your items for proper selection tracking.
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// struct MyItem: Identifiable {
    ///     let id: UUID
    ///     let title: String
    /// }
    ///
    /// @State private var items: [MyItem] = []
    /// @State private var selectedItem: MyItem?
    /// @State private var scrollProxy: ScrollViewProxy?
    ///
    /// EchoListView(
    ///     contentCount: items.count,
    ///     selectedId: selectedItem?.id,
    ///     onNavigateUp: {
    ///         // Move to previous item
    ///         if let currentIndex = items.firstIndex(where: { $0.id == selectedItem?.id }),
    ///            currentIndex > 0 {
    ///             selectedItem = items[currentIndex - 1]
    ///         }
    ///     },
    ///     onNavigateDown: {
    ///         // Move to next item
    ///         if let currentIndex = items.firstIndex(where: { $0.id == selectedItem?.id }),
    ///            currentIndex < items.count - 1 {
    ///             selectedItem = items[currentIndex + 1]
    ///         }
    ///     },
    ///     onScrollViewReady: { proxy in
    ///         // Store proxy for custom scrolling
    ///         self.scrollProxy = proxy
    ///     },
    ///     nullState: {
    ///         Text("No items available")
    ///             .foregroundColor(.secondary)
    ///     }
    /// ) {
    ///     ForEach(items) { item in
    ///         Text(item.title)
    ///             .id(item.id) // Required for proper selection tracking
    ///     }
    /// }
    /// ```
    ///
    /// ## Type Safety Guidelines
    ///
    /// To ensure type safety with `selectedId`, follow these guidelines:
    ///
    /// 1. Make sure your content items conform to `Identifiable`
    /// 2. Use `.id()` modifier on your `ForEach` items
    /// 3. Pass the same ID type as `selectedId`
    ///
    /// ## Features
    ///
    /// - **Auto-following**: Automatically scrolls to new content when added
    /// - **Follow button**: Appears when user scrolls away from bottom
    /// - **Keyboard navigation**: Supports arrow key navigation
    /// - **Null state**: Shows custom view when no content is available
    /// - **Custom scrolling**: Access to ScrollViewProxy for custom scroll operations
    public init(
        contentCount: Int,
        selectedId: AnyHashable? = nil,
        onNavigateUp: (() -> Void)? = nil,
        onNavigateDown: (() -> Void)? = nil,
        onScrollViewReady: ((ScrollViewProxy) -> Void)? = nil,
        @ViewBuilder nullState: @escaping () -> NullState,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentCount = contentCount
        self.selectedId = selectedId
        self.onNavigateUp = onNavigateUp
        self.onNavigateDown = onNavigateDown
        self.onScrollViewReady = onScrollViewReady
        self.nullState = nullState
        self.content = content
    }
    
    public var body: some View {
        mainContent
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var mainContent: some View {
        if contentCount == 0 {
            nullStateView
        } else {
            scrollViewContent
        }
    }
    
    private var nullStateView: some View {
        nullState()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var scrollViewContent: some View {
        ScrollViewReader { proxy in
            GeometryReader { scrollGeometry in
                ZStack {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            content()
                            bottomAnchor
                        }
                    }
                    .preference(key: ScrollViewHeightPreferenceKey.self, value: scrollGeometry.size.height)
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollViewHeightPreferenceKey.self) { height in
                        scrollViewHeight = height
                    }
                    .onChange(of: selectedId) { _, _ in
                        isFollowing = false
                    }
                    .onChange(of: contentCount) { _, _ in
                        if isFollowing {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onHotKeyEvent(key: String(NSEvent.SpecialKey.upArrow.unicodeScalar), modifierFlags: []) {
                        onNavigateUp?()
                    }
                    .onHotKeyEvent(key: String(NSEvent.SpecialKey.downArrow.unicodeScalar), modifierFlags: []) {
                        onNavigateDown?()
                    }
                    if !isFollowing && contentCount > 0 && !isBottomVisible {
                        VStack {
                            Spacer()
                            Button {
                                enableFollowing(proxy: proxy)
                            } label: {
                                followButtonLabel
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.bottom, 8)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: isFollowing)
                    }
                }
            }
            .onAppear {
                if isFollowing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let selectedId {
                            proxy.scrollTo(selectedId, anchor: .center)
                        } else {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                // Notify caller that ScrollViewProxy is ready
                onScrollViewReady?(proxy)
            }
        }
    }
    
    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 1)
            .id("bottom")
            .background(
                GeometryReader { anchorGeometry in
                    Color.clear
                        .preference(key: BottomAnchorYPreferenceKey.self, value: anchorGeometry.frame(in: .named("scroll")).minY)
                }
            )
            .onPreferenceChange(BottomAnchorYPreferenceKey.self) { y in
                guard !isAutoScrolling else { return }
                bottomAnchorY = y
                isBottomVisible = bottomAnchorY <= scrollViewHeight + 16
                isFollowing = isBottomVisible
            }
    }

    private var followButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12))
            Text("Follow")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue)
        .cornerRadius(16)
        .shadow(radius: 4)
    }
    
    // MARK: - State Management

    private func enableFollowing(proxy: ScrollViewProxy) {
        isFollowing = true
        isAutoScrolling = true
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("bottom", anchor: UnitPoint.bottom)
        } completion: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isBottomVisible = true
                isAutoScrolling = false
            }
        }
    }
    
    private func resetScrollState() {
        isFollowing = true
    }
}

// MARK: - Preference Keys

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BottomAnchorYPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
