import AniLibertyKit
import SwiftUI

/// Top-level destination switching: the only navigational chrome the app owns.
struct RootTabView: View {
    private enum AppTab: Hashable {
        case latest
        case catalog
        case profile
        case settings
    }

    @State private var selection: AppTab = .latest

    var body: some View {
        TabView(selection: $selection) {
            LatestReleasesView()
                .tabItem { Label("tab.latest", systemImage: "sparkles.tv") }
                .tag(AppTab.latest)

            CatalogView()
                .tabItem { Label("tab.catalog", systemImage: "square.grid.2x2") }
                .tag(AppTab.catalog)

            ProfileView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)

            SettingsView()
                .tabItem { Label("tab.settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // UI tests start from the shipped defaults; without this a failed test could leave a switch on and
        // the next run would read someone else's settings.
        .task { await resetSettingsIfAsked() }
    }

    /// Restores the playback switches to their shipped defaults when a UI test asks for it.
    private func resetSettingsIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestingResetSettings") else { return }
        await PlaybackSettingsStore().save(.defaults)
    }
}
