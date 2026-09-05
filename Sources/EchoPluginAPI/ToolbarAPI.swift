#if os(macOS)
import SwiftUI

/// Describes an element that can appear in Echo's toolbar.
/// The toolbar is attached to the active iOS Simulator / Android Emulator window.
public protocol ToolbarElementType: Codable {
    var id: String { get }
}

/**
 Conform to this protocol to provide toolbar elements to display next to the simulator/emulator.

 Toolbar elements are usually defined as an `enum` that conforms to `ToolbarElementType`.

 1. Provide your items to the registry in the `registerToolbarElements` method.
 Note: you can save a reference to the registry instance and dynamically register/unregister items at any time.

 2. Implement `makeView(for:)` and return a `ToolbarElementView` for each element.
 `ToolbarElementView` is a lightweight SwiftUI view that applies some standard styling.
 You can provide any content in the view builder parameter, or use the convenience method `ToolbarElementView.button(name:action:content:)` to create a button
 with a standard appearance.

 Example:
 ```
 final class MyDesktopPlugin: DesktopPlugin { ... }

 extension MyDesktopPlugin: ToolbarElementProvider {

    enum ToolbarElement: ToolbarElementType {
        case toggleSlowAnimations
        case toggleFeatureFlag(FeatureFlag)
    }

    func registerToolbarElements(registry: any ToolbarElementRegistry<ToolbarElement>) {
        registry.register(.toggleSlowAnimations)
        registry.register(.toggleDarkMode)

        registry.register(.toggleFeatureFlag(.enableLogging))
        registry.register(.toggleFeatureFlag(.useModernDesignLanguage))

        // Note: you can also save a reference to the registry to register/unregister
        // items dynamically later on.
        // self.toolbarElementRegistry = registry
    }

    func makeView(for toolbarElement: ToolbarElement) -> ToolbarElementView {
        switch toolbarElement {
        case .toggleSlowAnimations:
            .button(name: "Slow Animations") {
                // toggle slow animations
            } content: {
                Image(systemName: "hare")
            }

        case let .toggleFeatureFlag(featureFlag):
            .button(name: "Toggle Feature Flag (\(featureFlag.name))") {
                // toggle the feature flag
            } content: {
                Image(systemName: "flag")
            }
        }
     }
 }
 ```
 */
public protocol ToolbarElementProvider<ToolbarElement>: DesktopPlugin {
    /**
     Describes an element that can be displayed in the toolbar.
     This is usally an enum that conforms to `ToolbarElementType`.

     Note: `ToolbarElementType` requires your custom type to conform to `Codable`.

     For example:
     ```
     enum ToolbarElement: ToolbarElementType {
        case toggleSlowAnimations
        case toggleFeatureFlag(FeatureFlag)
     }
     ```

    Provide instances of this type to the registry passed in the `registerToolbarElements` method.
    Echo will ask your app to construct the view for these elements in the `makeView(for:)` method.
     */
    associatedtype ToolbarElement: ToolbarElementType

    /**
     Call `registry.register` and `registry.unregister` to add and remove toolbar elements.
     Note: you can save a reference to the registry instance to dynamically register/unregister elements at any time.
     */
    func registerToolbarElements(registry: any ToolbarElementRegistry<ToolbarElement>)

    /// Construct a view for the provided toolbar element.
    func makeView(for toolbarElement: ToolbarElement) -> ToolbarElementView
}

// MARK: -

public protocol ToolbarElementRegistry<Element> {
    associatedtype Element: ToolbarElementType

    /**
     Provide an element to Echo's toolbar.

     Elements can be programmatically removed by calling `unregister`.
     Users can also manually hide and remove elements in Echo Settings.
     */
    func register(_ element: Element)

    /**
     Remove a previously-registered toolbar element from Echo.
     Users can also manually hide and remove elements in Echo Settings.
     */
    func unregister(_ element: Element)
}

/**
 A SwiftUI.View wrapper that applies a standard appearance to toolbar items.

 See also: `ToolbarElementView.button` for a standard button view.
 */
public struct ToolbarElementView {
    @State private var isHovering = false

    var name: String
    @ViewBuilder var content:  () -> AnyView

    public init<Content: View>(
        name: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.name = name
        self.content = { AnyView(content()) }
    }
}

// MARK: -

extension ToolbarElementView: View {
    public var body: some View {
        content()
            .onHover { isHovering in
                self.isHovering = isHovering
            }
            .background(.thickMaterial)
            .clipShape(
                RoundedRectangle(cornerRadius: 10)
            )
            .popover(isPresented: $isHovering, arrowEdge: .trailing) {
                Text(name)
                    .padding(16)
                    .interactiveDismissDisabled()
            }
    }
}

extension ToolbarElementView {

    public static func button<Content: View>(
        name: String,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> Self {
        Self(name: name) {
            Button(action: action) {
                content()
                    .imageScale(.large)
                    .padding(.all, 8)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }
}

#endif
