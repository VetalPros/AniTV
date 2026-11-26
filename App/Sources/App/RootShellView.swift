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
        case profile
        case settings
    }

    @State private var selection: Section = .home

    var body: some View {
        TabView(selection: $selection) {
            // `role: .search` is what pins the magnifier row above the sections, as in the reference.
            Tab("nav.search", systemImage: "magnifyingglass", value: Section.search, role: .search) {
                // Search and browse are the same screen today (ADR 0020: the catalogue opens on its
                // search field), so a separate «Каталог» row would only duplicate its state.
                CatalogView()
            }

            Tab("nav.home", systemImage: "house", value: Section.home) {
                LatestReleasesView()
            }

            Tab("nav.profile", systemImage: "person.crop.circle", value: Section.profile) {
                ProfileView()
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
