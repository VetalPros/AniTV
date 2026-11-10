import AniLibertyKit
import SwiftUI

/// "Новинки" tab: poster grid of the most recent releases, pushing into the detail screen.
struct LatestReleasesView: View {
    @State private var model = LatestReleasesViewModel()
    @State private var path: [ReleaseRoute] = []

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
        .task { await model.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            LoadingStateView(message: "latest.loading")
        case let .loaded(releases):
            grid(releases)
        case .empty:
            failureLayout {
                EmptyStateView(title: "latest.empty.title", message: "latest.empty.message")
            }
        case let .failed(error):
            failureLayout {
                ErrorStateView(
                    title: "latest.failed.title",
                    message: error.userMessageKey,
                    retry: { model.reload() }
                )
            }
        }
    }

    private func grid(_ releases: [Release]) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
                ScreenHeader(title: "screen.latest.title", subtitle: "screen.latest.subtitle")
                ReleasePosterGrid(releases: releases) { release in
                    path.append(ReleaseRoute(release: release))
                }
            }
            .padding(.bottom, 64)
        }
        .scrollClipDisabled()
    }

    private func failureLayout(@ViewBuilder body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "screen.latest.title", subtitle: "screen.latest.subtitle")
            VStack {
                body()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
