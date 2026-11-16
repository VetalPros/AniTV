import AniLibertyKit
import SwiftUI

/// Width the synopsis occupies, reported from a background reader so the truncation rule is measured
/// against the real layout instead of a guess.
private struct SynopsisWidthPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Detail screen: hero with cover and title, metadata, genres, expandable synopsis, episode list
/// and the play action for the preferred stream.
struct ReleaseDetailView: View {
    @State private var model: ReleaseDetailViewModel
    @State private var playbackTarget: PlaybackRequest?
    @FocusState private var focusedControl: FocusedControl?

    /// Width the synopsis is actually laid out at, reported by the text itself. It feeds the
    /// truncation measurement, so the toggle only exists when there is something to reveal.
    @State private var synopsisWidth: CGFloat = 0

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

    /// The screen is one long scroll view: the hero, genres, synopsis and the episode grid all have
    /// to be reachable with Down/Up from the remote.
    ///
    /// Do not add `.scrollClipDisabled()` here. It makes the scroll view report its content as
    /// visible, so the focus engine believes the whole page is on screen: Down never leaves the
    /// hero and the episode list is unreachable.
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
        .accessibilityIdentifier("detail.screen")
        .onPreferenceChange(SynopsisWidthPreference.self) { width in
            synopsisWidth = width
        }
        .defaultFocus($focusedControl, defaultControl, priority: .userInitiated)
        .onAppear(perform: takeDefaultFocus)
    }

    /// The control that owns focus when the screen opens: the primary action, or the synopsis
    /// toggle when there is nothing playable but something to expand. Focus must land somewhere —
    /// with an empty focus environment Menu backgrounds the app instead of popping the screen
    /// (ADR 0012), so `.play` is the fallback even when it is disabled.
    private var defaultControl: FocusedControl {
        if model.isPlayable {
            return .play
        }
        return isSynopsisClipped ? .synopsisToggle : .play
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
                // `RemoteImage` fills whatever frame it is given, so both dimensions have to come
                // from the 2:3 poster ratio — a width-only frame leaves the height unbounded and
                // slices the artwork.
                .frame(
                    width: DesignTokens.heroPosterWidth,
                    height: DesignTokens.heroPosterWidth / DesignTokens.posterAspectRatio
                )
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
        // Sections make the vertical chain predictable: the engine moves between blocks, so Down
        // from the hero lands on the synopsis control instead of jumping over it into the grid.
        .focusSection()
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
                .lineSpacing(SynopsisFitting.lineSpacing)
                .lineLimit(isSynopsisCollapsed ? SynopsisFitting.collapsedLines : nil)
                .frame(maxWidth: 1300, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: SynopsisWidthPreference.self, value: proxy.size.width)
                    }
                }
                .accessibilityIdentifier("detail.synopsisText")
            if isSynopsisClipped {
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
        .focusSection()
    }

    /// Whether the collapsed synopsis would really be cut off at the width it is rendered with.
    private var isSynopsisClipped: Bool {
        SynopsisFitting.isClipped(model.synopsis, width: synopsisWidth)
    }

    private var isSynopsisCollapsed: Bool {
        isSynopsisClipped && !model.isDescriptionExpanded
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
                episodeGrid(release.episodes)
            }
        }
        .focusSection()
    }

    /// Two-column episode list built with the eager `Grid` on purpose.
    ///
    /// `LazyVGrid` only instantiates the cells that intersect the visible area, and here the first
    /// row sits below the fold: no cell ever exists, so nothing is focusable, so focus never scrolls
    /// down to the list and the list never materialises. The grid holds a handful of rows, so
    /// building it eagerly costs nothing and keeps the whole list reachable with the remote.
    private func episodeGrid(_ episodes: [Episode]) -> some View {
        let rowCount = (episodes.count + 1) / 2
        return Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 20) {
            ForEach(0 ..< rowCount, id: \.self) { row in
                GridRow(alignment: .top) {
                    ForEach(Array((row * 2) ..< min(row * 2 + 2, episodes.count)), id: \.self) { index in
                        let episode = episodes[index]
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
