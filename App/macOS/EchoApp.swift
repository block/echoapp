import Echo
import SwiftUI

// The entry point for the macOS app build product in Xcode
// this wraps the `Echo` product from `echo` because SPM
// does not support defining app products.

@main
struct macOSApp: App {
    var body: some Scene {
        EchoApp().body
    }
}
