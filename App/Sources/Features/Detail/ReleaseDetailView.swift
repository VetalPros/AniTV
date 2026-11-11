import AniLibertyKit
import SwiftUI

/// Detail screen: hero with cover and title, metadata, genres, expandable synopsis, episode list
/// and the play action for the preferred stream.
struct ReleaseDetailView: View {
    @State private var model: ReleaseDetailViewModel
    @State private var playbackTarget: PlaybackRequest?
    @FocusState private var focusedControl: FocusedControl?

    /// The screen refetches on its own, so at push time it usually has nothing focusable yet. When
    /// the hero finally appears the focus engine has already dropped focus, and on tvOS a Menu
    /// press with nothing focused is handled by the system, which backgrounds the app instead of
    /// popping back to the feed. The screen therefore claims focus itself as soon as it can.
    private enum FocusedControl: Hashable {
        case play
        case synopsisToggle
    }

    init(route: ReleaseRoute) {
        _model = State(initialValue: ReleaseDetailViewModel(route: route))
    }

    var body: some View {
        ZStack {
            AniTVBackground()
            content
        }
        .task { await model.loadIfNeeded() }
        .fullScreenCover(item: $playbackTarget) { request in
            PlayerScreen(request: request)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            LoadingStateView(message: "detail.loading")
        case let .failed(error):
            ErrorStateView(
                title: "detail.failed.title",
                message: error.userMessageKey,
                retry: { Task { await model.reload() } }
            )
            .frame(maxHeight: .infinity)
        case let .loaded(release):
            loaded(release)
        }
    }

    private func loaded(_ release: Release) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 48) {
                hero(release)
                if !model.genres.isEmpty {
                    genresRow
                }
                synopsisSection
                episodesSection(release)
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, 36)
            .padding(.bottom, 88)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("detail.screen")
        .defaultFocus($focusedControl, defaultControl, priority: .userInitiated)
        .onAppear(perform: takeDefaultFocus)
    }

    /// The control that owns focus when the screen opens: the primary action, or the synopsis
    /// toggle when there is nothing playable.
    private var defaultControl: FocusedControl {
        model.isPlayable ? .play : .synopsisToggle
    }

    /// Asks for focus once the content is in the hierarchy. The assignment is made on the next turn
    /// of the run loop because the push transition is often still running when the hero appears and
    /// the focus engine drops requests made during it.
    private func takeDefaultFocus() {
        let control = defaultControl
        Task {
            focusedControl = control
            try? await Task.sleep(for: .milliseconds(400))
            focusedControl = control
        }
    }

    // MARK: Hero

    private func hero(_ release: Release) -> some View {
        HStack(alignment: .top, spacing: 52) {
            RemoteImage(url: model.posterURL)
                .frame(width: DesignTokens.heroPosterWidth)
                .aspectRatio(DesignTokens.posterAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 16)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: release.title)
                        .font(DesignTokens.Typography.detailTitle)
                        .foregroundStyle(.white)
                    if let originalTitle = release.originalTitle {
                        Text(verbatim: originalTitle)
                            .font(DesignTokens.Typography.detailOriginalTitle)
                            .foregroundStyle(.secondary)
                    }
                }

                metadataRow(release)
                blockingNotice(release)
                playButton(release)
            }
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private func metadataRow(_ release: Release) -> some View {
        HStack(spacing: 10) {
            if let year = release.year {
                GlassBadge(title: LocalizedStringKey(String(year)), systemImage: "calendar")
            }
            if let type = release.type?.description {
                GlassBadge(title: LocalizedStringKey(type))
            }
            if let ageRating = release.ageRating {
                GlassBadge(title: LocalizedStringKey(ageRating))
            }
            if let rating = release.averageRating {
                RatingPill(rating: rating)
            }
            if let total = release.episodesTotal {
                GlassBadge(title: "detail.episodesTotal \(total)", systemImage: "rectangle.stack")
            }
            if release.isOngoing == true {
                GlassBadge(title: "badge.ongoing", tint: Palette.accent.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private func blockingNotice(_ release: Release) -> some View {
        if release.isBlockedByGeo {
            noticeRow(
                systemImage: "globe",
                text: "detail.blocked.geo",
                tint: Palette.accent
            )
        } else if release.isBlockedByCopyrights {
            noticeRow(
                systemImage: "lock",
                text: "detail.blocked.copyrights",
                tint: Palette.accent
            )
        }
    }

    private func noticeRow(systemImage: String, text: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func playButton(_: Release) -> some View {
        Button {
            playbackTarget = model.primaryPlaybackRequest
        } label: {
            Label("detail.watch", systemImage: "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .disabled(!model.isPlayable)
        .opacity(model.isPlayable ? 1 : 0.5)
        .accessibilityHint(Text(model.playableEpisode?.displayTitle ?? ""))
        .focused($focusedControl, equals: .play)
        .accessibilityIdentifier("detail.playButton")
    }

    // MARK: Genres

    private var genresRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("detail.genres.title")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
            WrapLayout(horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(model.genres, id: \.id) { genre in
                    if let name = genre.name {
                        Text(verbatim: name)
                            .font(DesignTokens.Typography.callout)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: Synopsis

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("detail.synopsis.title")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
            Text(verbatim: model.synopsis)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .lineLimit(model.isSynopsisExpandable && !model.isDescriptionExpanded ? 6 : nil)
                .frame(maxWidth: 1300, alignment: .leading)
            if model.isSynopsisExpandable {
                Button(model.isDescriptionExpanded ? "detail.synopsis.collapse" : "detail.synopsis.expand") {
                    withAnimation(DesignTokens.Motion.reveal) {
                        model.toggleDescriptionExpanded()
                    }
                }
                .buttonStyle(.glass)
                .focused($focusedControl, equals: .synopsisToggle)
                .accessibilityIdentifier("detail.synopsisToggle")
            }
        }
    }

    // MARK: Episodes

    private func episodesSection(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("detail.episodes.title")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
            if release.episodes.isEmpty {
                Text("detail.episodes.empty")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 20, alignment: .top),
                        GridItem(.flexible(), spacing: 20, alignment: .top),
                    ],
                    alignment: .leading,
                    spacing: 20
                ) {
                    ForEach(release.episodes) { episode in
                        EpisodeCard(
                            episode: episode,
                            playableQuality: playbackQuality(for: episode)
                        ) {
                            play(episode)
                        }
                    }
                }
            }
        }
    }

    private func playbackQuality(for episode: Episode) -> StreamQuality? {
        StreamResolver.preferredSource(for: episode)?.quality
    }

    private func play(_ episode: Episode) {
        playbackTarget = model.playbackRequest(for: episode)
    }
}
