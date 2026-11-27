import AniLibertyKit
import SwiftUI

/// Top-level shell: the system sidebar and the sections it switches between (ADR 0028).
///
/// The panel, its collapse-on-leave behaviour, its focus handling and its glass are the platform's;
/// this type only owns which section is selected and what each section shows. «Медиатека» joins when
/// the favourites and continue-watching screens exist — a dead row is worse than a missing one.
struct RootShellView: View {
    private enum Section: Hashable {
        case search
        case home
        case catalog
        case profile
        case settings
    }

    @State private var selection: Section = RootShellView.initialSection
    /// Section paths live here, above the tabs, so a section keeps its stack when the tab is unloaded
    /// and reloaded (`ShellNavigationState`, ADR 0028 §7).
    @State private var navigation = ShellNavigationState()

    /// Section to open on launch. Production always starts on «Главная»; a UI test may ask for another
    /// one with `-uiTestingSection <search|home|profile|settings>` so it can capture every screen without
    /// walking the focus engine into the panel.
    private static var initialSection: Section {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uiTestingSection"),
              arguments.index(after: flag) < arguments.endIndex
        else {
            return .home
        }
        switch arguments[arguments.index(after: flag)] {
        case "search": return .search
        case "catalog": return .catalog
        case "profile": return .profile
        case "settings": return .settings
        default: return .home
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            // `role: .search` is what pins the magnifier row above the sections, as in the reference.
            Tab("nav.search", systemImage: "magnifyingglass", value: Section.search, role: .search) {
                CatalogView(mode: .search, path: $navigation.search)
            }

            Tab("nav.home", systemImage: "house", value: Section.home) {
                LatestReleasesView(path: $navigation.home)
            }

            Tab("nav.catalog", systemImage: "square.grid.2x2", value: Section.catalog) {
                CatalogView(mode: .browse, path: $navigation.catalog)
            }

            Tab("nav.profile", systemImage: "person.crop.circle", value: Section.profile) {
                ProfileView(path: $navigation.profile)
            }

            Tab("nav.settings", systemImage: "gearshape", value: Section.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarHeaderView() }
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

/// The block above the sections: who is watching and what time it is, as in the system TV app.
///
/// The account has no display name yet (signing in is an OTP pairing, ADR 0021), so the name slot shows
/// the app itself until the Kit exposes one.
private struct SidebarHeaderView: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("nav.header.title")
                    .font(.system(size: 21, weight: .semibold))
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }
}
