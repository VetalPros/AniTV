import SwiftUI

/// Entry point of the tvOS application.
///
/// The app is deliberately thin: navigation lives in `RootTabView`, every screen is a function of
/// its own `@Observable` view model, and all networking, decoding and playback resolution happen
/// inside `AniLibertyKit`.
@main
struct AniTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
