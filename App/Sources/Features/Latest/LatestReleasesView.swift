import AniLibertyKit
import SwiftUI

/// "Новинки" tab: poster grid of the most recent releases, pushing into the detail screen.
struct LatestReleasesView: View {
    @State private var model = LatestReleasesViewModel()
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
        .task { await model.loadIfNeeded() }
        .onAppear { Task { await model.setVisible(scenePhase == .active) } }
        .onDisappear { Task { await model.setVisible(false) } }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.setVisible(phase == .active) }
        }
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
                VStack(alignment: .leading, spacing: 6) {
                    ScreenHeader(title: "screen.latest.title", subtitle: "screen.latest.subtitle")
                    freshness
                }
                ReleasePosterGrid(releases: releases) { release in
                    path.append(ReleaseRoute(release: release))
                }
            }
            .padding(.bottom, 64)
        }
        .scrollClipDisabled()
    }

    /// Quiet "the list is live" line: the time the grid was last brought up to date.
    @ViewBuilder
    private var freshness: some View {
        if let updatedAt = model.updatedAt {
            Text("common.updatedAt \(updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(DesignTokens.Typography.cardMeta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.screenInset)
                .accessibilityIdentifier("latest.updatedAt")
                .accessibilityValue(Text(verbatim: updatedAt.formatted(date: .omitted, time: .standard)))
        }
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
