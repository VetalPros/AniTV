import AniLibertyKit
import SwiftUI

/// «Главная»: two rails instead of a grid — fresh releases, and what changed in the viewer's favourites
/// (ADR 0031).
///
/// The rails load independently: a dead favourites request must not take the fresh-release rail with it,
/// and a signed-out viewer simply has no second rail. The section keeps its own `NavigationStack`, whose
/// path is owned by the shell (`ShellNavigationState`).
struct HomeView: View {
    @State private var latestModel = LatestReleasesViewModel()
    @State private var favoritesModel = FavoritesUpdatesViewModel()
    /// How large the viewer wants the posters. Read when the section appears: `TabView` unloads an
    /// unselected section, so coming back from «Настройки» re-runs the task and picks up the new value.
    @State private var posterScale = PosterScale.default
    /// Owned by the shell, so the section survives its own view being recreated (ADR 0028 §7).
    @Binding var path: [ReleaseRoute]
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AniTVBackground()
                content
            }
            .navigationDestination(for: ReleaseRoute.self) { route in
                ReleaseDetailView(route: route)
            }
        }
        .task {
            posterScale = await PosterScaleStore().load()
            await latestModel.loadIfNeeded()
            await favoritesModel.loadIfNeeded()
        }
        .onAppear { Task { await latestModel.setVisible(scenePhase == .active) } }
        .onDisappear { Task { await latestModel.setVisible(false) } }
        .onChange(of: scenePhase) { _, phase in
            Task { await latestModel.setVisible(phase == .active) }
        }
    }

    private var content: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
                latestRail
                favoritesRail
            }
            .padding(.top, DesignTokens.screenTopInset)
            .padding(.bottom, 64)
        }
        .scrollClipDisabled()
    }

    // MARK: Rails

    @ViewBuilder
    private var latestRail: some View {
        switch latestModel.state {
        case .idle, .loading:
            LoadingStateView(message: "latest.loading")
        case let .loaded(releases):
            HomeRail(
                title: "home.latest.title",
                releases: releases,
                scale: posterScale,
                cardIdentifier: "latest.posterCard",
                railIdentifier: "home.rail.latest",
                refreshProbe: RefreshProbe.stamp(RefreshProbe.latestIdentifier, date: latestModel.updatedAt),
                takesDefaultFocus: true,
                onSelect: open
            )
        case .empty:
            EmptyStateView(title: "latest.empty.title", message: "latest.empty.message")
                .padding(.horizontal, DesignTokens.screenInset)
        case let .failed(error):
            ErrorStateView(
                title: "latest.failed.title",
                message: error.userMessageKey,
                retry: { latestModel.reload() }
            )
            .padding(.horizontal, DesignTokens.screenInset)
        }
    }

    @ViewBuilder
    private var favoritesRail: some View {
        switch favoritesModel.state {
        case .idle, .loading, .signedOut, .empty:
            // No account, no rail: an empty strip under «Новинки» would read as a bug.
            EmptyView()
        case let .loaded(releases):
            HomeRail(
                title: "home.favorites.title",
                releases: releases,
                scale: posterScale,
                cardIdentifier: "home.favoriteCard",
                railIdentifier: "home.rail.favorites",
                onSelect: open
            )
        case let .failed(error):
            EmptyStateView(title: "home.favorites.failed", message: error.userMessageKey)
                .padding(.horizontal, DesignTokens.screenInset)
        }
    }

    private func open(_ release: Release) {
        path.append(ReleaseRoute(release: release))
    }
}
