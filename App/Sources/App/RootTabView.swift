import SwiftUI

/// Top-level destination switching: the only navigational chrome the app owns.
struct RootTabView: View {
    private enum AppTab: Hashable {
        case latest
        case catalog
        case profile
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

            ProfilePlaceholderView()
                .tabItem { Label("tab.profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
    }
}
