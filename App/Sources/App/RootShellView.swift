import AniLibertyKit
import SwiftUI

/// Top-level shell: the system sidebar and the sections it switches between (ADR 0028), with the account
/// as the panel's own header (ADR 0032).
///
/// The panel, its collapse-on-leave behaviour, its focus handling and its glass are the platform's; this
/// type owns which section is selected, the header's account read, and the profile cover. «Медиатека»
/// joins when the favourites and continue-watching screens exist — a dead row is worse than a missing one.
struct RootShellView: View {
    private enum Section: Hashable {
        case search
        case home
        case catalog
        case settings
    }

    @State private var selection: Section = RootShellView.initialSection
    /// Section paths live here, above the tabs, so a section keeps its stack when the tab is unloaded
    /// and reloaded (`ShellNavigationState`, ADR 0028 §7).
    @State private var navigation = ShellNavigationState()
    @State private var account = SidebarProfileModel()
    /// The profile is a cover, not a section: the reference keeps it in the panel header, and a section
    /// that is also reachable from the header would put the same screen in two places.
    @State private var showsProfile = RootShellView.startsOnProfile

    /// Section to open on launch. Production always starts on «Главная»; a UI test may ask for another
    /// one with `-uiTestingSection <search|home|catalog|profile|settings>` so it can capture every screen
    /// without walking the focus engine into the panel. `profile` opens the cover instead of a tab.
    private static var initialSection: Section {
        switch requestedSection {
        case "search": .search
        case "catalog": .catalog
        case "settings": .settings
        default: .home
        }
    }

    private static var startsOnProfile: Bool {
        requestedSection == "profile"
    }

    private static var requestedSection: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-uiTestingSection"),
              arguments.index(after: flag) < arguments.endIndex
        else {
            return "home"
        }
        return arguments[arguments.index(after: flag)]
    }

    var body: some View {
        TabView(selection: $selection) {
            // `role: .search` is what pins the magnifier row above the sections, as in the reference.
            Tab("nav.search", systemImage: "magnifyingglass", value: Section.search, role: .search) {
                CatalogView(mode: .search, path: $navigation.search)
            }

            Tab("nav.home", systemImage: "house", value: Section.home) {
                HomeView(path: $navigation.home)
            }

            Tab("nav.catalog", systemImage: "square.grid.2x2", value: Section.catalog) {
                CatalogView(mode: .browse, path: $navigation.catalog)
            }

            Tab("nav.settings", systemImage: "gearshape", value: Section.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            SidebarHeaderView(account: account) { showsProfile = true }
        }
        .fullScreenCover(isPresented: $showsProfile) {
            ProfileView(path: $navigation.profile)
                // Signing in or out happens inside the cover, and the header is the only place that shows
                // the result, so the account is re-read when the cover goes away.
                .onDisappear { Task { await account.reload() } }
        }
        .task {
            await account.reload()
            await resetSettingsIfAsked()
        }
    }

    /// Restores the playback switches and the poster size to their shipped defaults when a UI test asks for
    /// it. A test that changes a setting must not leave it for the next one.
    private func resetSettingsIfAsked() async {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestingResetSettings") else { return }
        await PlaybackSettingsStore().save(.defaults)
        await PosterScaleStore().save(.default)
    }
}

/// The panel's header: who is watching, and what time it is — the account entry point, as in the system TV
/// app. Selecting it opens the profile cover.
private struct SidebarHeaderView: View {
    let account: SidebarProfileModel
    let openProfile: () -> Void

    var body: some View {
        Button(action: openProfile) {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 21, weight: .semibold))
                        .lineLimit(1)
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shell.account")
        // A stable, language-independent signal for the UI tests: the header is the only place that knows
        // whether this TV is paired, and reading it here beats re-deriving it from screens.
        .accessibilityValue(Text(verbatim: accountStateValue))
    }

    @ViewBuilder
    private var avatar: some View {
        switch account.state {
        case let .signedIn(_, url?):
            RemoteImage(url: url)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        default:
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
        }
    }

    private var accountStateValue: String {
        switch account.state {
        case .signedIn: "signedIn"
        case .signedOut: "signedOut"
        case .loading, .failed: "unknown"
        }
    }

    private var title: LocalizedStringKey {
        switch account.state {
        case let .signedIn(name, _): .init(verbatim: name)
        case .signedOut: "shell.account.signIn"
        case .loading, .failed: "shell.account.profile"
        }
    }
}

/// `LocalizedStringKey` needs an explicit initialiser for a runtime string; this keeps the header's switch
/// readable instead of spreading `LocalizedStringKey(name)` over every branch.
private extension LocalizedStringKey {
    init(verbatim string: String) {
        self = LocalizedStringKey(string)
    }
}
