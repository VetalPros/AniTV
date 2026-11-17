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
    @State private var isPickerPresented = false
    /// Episode chosen in the picker; playback starts when the cover finishes dismissing.
    @State private var pendingEpisode: Episode?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedControl: DetailHeroAction?

    /// Width the synopsis is actually laid out at, reported by the text itself. It feeds the
    /// truncation measurement, so the toggle only exists when there is something to reveal.
    @State private var synopsisWidth: CGFloat = 0

    /// The screen refetches on its own, so at push time it usually has nothing focusable yet. When
    /// the hero finally appears the focus engine has already dropped focus, and on tvOS a Menu
    /// press with nothing focused is handled by the system, which backgrounds the app instead of
    /// popping back to the feed. The screen therefore claims focus itself as soon as it can.
    init(route: ReleaseRoute) {
        _model = State(initialValue: ReleaseDetailViewModel(route: route))
    }

    var body: some View {
        ZStack {
            AniTVBackground()
            content
        }
        .task { await model.loadIfNeeded() }
        // Back from the player or from another tab: the heart has to match the site again. Focus moves
        // deliberately do not trigger this.
        .onAppear {
            Task { await model.loadFavoritesState() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.loadFavoritesState() }
        }
        .fullScreenCover(
            isPresented: $isPickerPresented,
            onDismiss: {
                if let episode = pendingEpisode {
                    pendingEpisode = nil
                    playbackTarget = model.playbackRequest(for: episode)
                }
            },
            content: {
                EpisodePickerScreen(
                    episodes: model.episodes,
                    initialFocusEpisodeID: model.resumeProgress?.episodeID ?? model.playableEpisode?.id,
                    playableQuality: playbackQuality(for:),
                    onSelect: { episode in
                        pendingEpisode = episode
                        isPickerPresented = false
                    }
                )
            }
        )
        .fullScreenCover(
            item: $playbackTarget,
            onDismiss: {
                Task {
                    await model.refreshResumeProgress()
                    await model.loadFavoritesState()
                }
            },
            content: { request in
                PlayerScreen(request: request)
            }
        )
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
                ReleaseHeroView(
                    release: release,
                    model: model,
                    focus: $focusedControl,
                    onResume: { playbackTarget = model.resumeRequest },
                    onPlay: { isPickerPresented = true },
                    onFavorite: { Task { await model.toggleFavorite() } }
                )
                if !model.genres.isEmpty {
                    genresRow
                }
                synopsisSection
                EpisodeSection(
                    episodes: release.episodes,
                    playableQuality: playbackQuality(for:),
                    progressFraction: model.watchedFraction(for:),
                    currentEpisodeID: model.resumeProgress?.episodeID,
                    onSelect: play
                )
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

    /// The control that owns focus when the screen opens: continuing is the likelier intent when the
    /// viewer has been here before, otherwise the primary action, otherwise the synopsis toggle when
    /// there is nothing playable but something to expand. Focus must land somewhere — with an empty
    /// focus environment Menu backgrounds the app instead of popping the screen (ADR 0012), so
    /// `.play` is the fallback even when it is disabled.
    private var defaultControl: DetailHeroAction {
        if model.resumeRequest != nil {
            return .resume
        }
        if model.isPlayable {
            return .play
        }
        return isSynopsisClipped ? .synopsisToggle : .play
    }

    /// Whether the screen offers to continue where the viewer stopped.
    private var canResume: Bool {
        model.resumeRequest != nil
    }

    /// Asks for focus once the content is in the hierarchy. The assignment is made on the next turn
    /// of the run loop because the push transition is often still running when the hero appears and
    /// the focus engine drops requests made during it.
    private func takeDefaultFocus() {
        Task {
            // The resume decision arrives with the release, a beat after the screen appears. Waiting
            // for it means focus lands on «Продолжить» when there is progress to continue, instead of
            // landing on «Смотреть» and making the viewer's first press a correction.
            loading: for _ in 0 ..< 40 {
                switch model.state {
                case .idle, .loading:
                    try? await Task.sleep(for: .milliseconds(50))
                case .loaded, .failed:
                    break loading
                }
            }
            let control = defaultControl
            focusedControl = control
            try? await Task.sleep(for: .milliseconds(400))
            focusedControl = control
        }
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

    private func playbackQuality(for episode: Episode) -> StreamQuality? {
        StreamResolver.preferredSource(for: episode)?.quality
    }

    private func play(_ episode: Episode) {
        playbackTarget = model.playbackRequest(for: episode)
    }
}
