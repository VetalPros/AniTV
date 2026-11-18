import AniLibertyKit
import Foundation
import Observation
import os

/// Owns the release-detail request and the derived facts the screen needs (playable episode,
/// readable synopsis, playback gating).
@MainActor
@Observable
final class ReleaseDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(Release)
        case failed(AniLibertyError)
    }

    private static let logger = Logger(subsystem: "tv.anitv.client", category: "Detail")

    let route: ReleaseRoute
    private(set) var state: State = .idle

    /// Position the viewer stopped at, when it is worth resuming. `nil` means the screen offers only
    /// «Смотреть» from the beginning.
    private(set) var resumeProgress: PlaybackProgress?

    /// Whether this TV has a session. The screen only needs the answer, never the token itself.
    private(set) var isPaired = false
    /// Whether the release is in the signed-in viewer's favourites.
    private(set) var isFavorite = false
    /// One-line feedback under the action row: a hint when signed out, or a failure.
    private(set) var favoriteMessage: FavoriteMessage?
    /// Progress of the episodes that were watched, keyed by episode id.
    private(set) var episodeProgress: [UUID: PlaybackProgress] = [:]

    /// Feedback the screen shows under the hero actions.
    enum FavoriteMessage: Equatable {
        case signedOut
        case failed(AniLibertyError)
    }

    @ObservationIgnored private let client: AniLibertyClient
    @ObservationIgnored private let progressStore: PlaybackProgressStoring
    /// Session store; the token it returns is used locally and never kept on this type.
    @ObservationIgnored private let tokenStore: AuthTokenStoring
    @ObservationIgnored private var favoriteIDs: Set<Int> = []

    init(
        route: ReleaseRoute,
        client: AniLibertyClient = AniLibertyClient(),
        progressStore: PlaybackProgressStoring = PlaybackProgressStore(),
        tokenStore: AuthTokenStoring = AuthTokenStoreFactory.make()
    ) {
        self.route = route
        self.client = client
        self.progressStore = progressStore
        self.tokenStore = tokenStore
    }

    // MARK: Derived presentation

    var release: Release? {
        if case let .loaded(release) = state {
            return release
        }
        return nil
    }

    /// Title to show while the request is still in flight: the route snapshot keeps the hero
    /// populated instead of flashing an empty screen.
    var title: String {
        release?.title ?? route.title
    }

    var originalTitle: String? {
        release?.originalTitle
    }

    var subtitle: String {
        release?.subtitle ?? route.subtitle
    }

    var posterURL: URL? {
        release?.posterURL ?? route.posterURL
    }

    /// The first episode that has a resolvable stream; the play button drives playback for it.
    var playableEpisode: Episode? {
        release?.episodes.first { StreamResolver.preferredSource(for: $0) != nil }
    }

    /// Playback is offered only when the release is playable *and* a stream can be built.
    var isPlayable: Bool {
        (release?.isPlayable ?? false) && playableEpisode != nil
    }

    var primaryPlaybackRequest: PlaybackRequest? {
        guard let episode = playableEpisode else { return nil }
        return playbackRequest(for: episode)
    }

    /// `nil` when the episode has no usable stream, which the UI renders as a disabled row.
    ///
    /// - Parameters:
    ///   - episode: Episode to play.
    ///   - startAt: Position to start at, or `nil` for the beginning.
    func playbackRequest(for episode: Episode, startAt: TimeInterval? = nil) -> PlaybackRequest? {
        guard let release, let source = StreamResolver.preferredSource(for: episode) else {
            return nil
        }
        return PlaybackRequest(
            id: episode.id,
            releaseAlias: release.alias,
            releaseTitle: release.title,
            episodeTitle: episode.displayTitle,
            episode: episode,
            source: source,
            startAt: startAt,
            nextEpisode: nextPlayableEpisode(after: episode)
        )
    }

    /// Episode that follows `episode` in the release and can be played, if any.
    private func nextPlayableEpisode(after episode: Episode) -> Episode? {
        guard let episodes = release?.episodes,
              let index = episodes.firstIndex(where: { $0.id == episode.id })
        else {
            return nil
        }
        return episodes[(index + 1)...].first { StreamResolver.preferredSource(for: $0) != nil }
    }

    /// Episode the picker should start on: the one «Продолжить» would resume, otherwise the first playable.
    ///
    /// A UI test can ask for an episode that actually has an opening (see `PlayerTestOverrides`), because
    /// whether episode 1 has one is a property of the release, not of the player.
    var pickerInitialEpisodeID: UUID? {
        let shortEnding = PlayerTestOverrides.picksEpisodeWithShortEnding()
            ? episodes.first(where: { isShortEnding($0) })
            : nil
        if let shortEnding {
            return shortEnding.id
        }
        let openingEpisode = PlayerTestOverrides.picksEpisodeWithOpening()
            ? episodes.first(where: {
                StreamResolver.preferredSource(for: $0) != nil
                    && TimecodeResolver.timecodes(for: $0).contains { $0.kind == .opening }
            })
            : nil
        if let openingEpisode {
            return openingEpisode.id
        }
        return resumeProgress?.episodeID ?? playableEpisode?.id
    }

    /// Whether this episode's ending runs into the end of the file and another episode follows.
    private func isShortEnding(_ episode: Episode) -> Bool {
        guard StreamResolver.preferredSource(for: episode) != nil,
              let duration = episode.duration,
              let ending = TimecodeResolver.timecodes(for: episode).first(where: { $0.kind == .ending })
        else {
            return false
        }
        return duration - ending.end <= PlayerModel.endingTailThreshold
            && nextPlayableEpisode(after: episode) != nil
    }

    /// The remembered episode played from the remembered position, or `nil` when there is nothing
    /// worth resuming.
    var resumeRequest: PlaybackRequest? {
        guard let resumeProgress,
              let episode = release?.episodes.first(where: { $0.id == resumeProgress.episodeID })
        else {
            return nil
        }
        return playbackRequest(for: episode, startAt: resumeProgress.position)
    }

    /// Asks the store again — used when the player closes, so the screen reflects the positions that
    /// were just saved instead of the ones it was opened with.
    func refreshResumeProgress() async {
        await loadProgress()
    }

    /// Progress of one episode, used by the cards and the picker.
    ///
    /// - Parameter episodeID: Episode to look up.
    /// - Returns: The stored record, or `nil` when that episode was never played.
    func progress(for episodeID: UUID) -> PlaybackProgress? {
        episodeProgress[episodeID]
    }

    /// Fraction of the episode that was watched, `nil` when nothing is stored or the duration is unknown.
    ///
    /// - Parameter episodeID: Episode to look up.
    /// - Returns: A value in `0...1`.
    func watchedFraction(for episodeID: UUID) -> Double? {
        guard let progress = episodeProgress[episodeID],
              let duration = progress.duration,
              duration > 0
        else {
            return nil
        }
        return min(max(progress.position / duration, 0), 1)
    }

    // MARK: Favourites

    /// Reads the signed-in state and the favourites of this release.
    ///
    /// The answer is cached for the lifetime of the screen (one release, one push) so focus moves and
    /// scrolling never ask the service again; it is refreshed after a toggle and when the player closes.
    func loadFavoritesState() async {
        guard let token = try? await tokenStore.load(), !token.isEmpty else {
            isPaired = false
            isFavorite = false
            favoriteIDs = []
            return
        }
        isPaired = true
        do {
            let ids = try await client.favoriteReleaseIDs(token: token)
            guard !Task.isCancelled else { return }
            favoriteIDs = Set(ids)
            isFavorite = favoriteIDs.contains(route.id)
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            if Self.isUnauthorized(mapped) {
                // A dead token means "not paired" for this screen; forgetting it belongs to the profile tab.
                isPaired = false
                isFavorite = false
                return
            }
            Self.logger.error("Favourites state failed: \(String(describing: mapped), privacy: .public)")
            favoriteMessage = .failed(mapped)
        }
    }

    /// Flips the favourite state optimistically and rolls back when the call fails.
    ///
    /// Signed out, nothing is sent: the screen explains how to pair this TV instead.
    func toggleFavorite() async {
        favoriteMessage = nil
        guard let token = try? await tokenStore.load(), !token.isEmpty else {
            isPaired = false
            favoriteMessage = .signedOut
            return
        }
        isPaired = true
        let wasFavorite = isFavorite
        isFavorite.toggle()
        do {
            let ids = isFavorite
                ? try await client.addFavorites([route.id], token: token)
                : try await client.removeFavorites([route.id], token: token)
            guard !Task.isCancelled else { return }
            favoriteIDs = Set(ids)
            isFavorite = favoriteIDs.contains(route.id)
            Self.logger.info(
                "Favourite toggled for release \(self.route.id, privacy: .public); service reports \(ids.count, privacy: .public) favourites"
            )
            NotificationCenter.default.post(name: .anitvFavoritesChanged, object: nil)
        } catch {
            guard !Task.isCancelled else { return }
            isFavorite = wasFavorite
            let mapped = AniLibertyError.mapped(error)
            if Self.isUnauthorized(mapped) {
                isPaired = false
                favoriteMessage = .signedOut
                return
            }
            favoriteMessage = .failed(mapped)
            Self.logger.error("Favourite toggle failed: \(String(describing: mapped), privacy: .public)")
        }
    }

    /// Clears the feedback line, so it disappears as soon as the viewer acts again.
    func clearFavoriteMessage() {
        favoriteMessage = nil
    }

    private func loadProgress() async {
        let alias = route.alias
        let resumable = await progressStore.resumableProgress(forReleaseAlias: alias)
        guard !Task.isCancelled else { return }
        resumeProgress = resumable

        var perEpisode: [UUID: PlaybackProgress] = [:]
        for episode in episodes {
            if let progress = await progressStore.progress(forReleaseAlias: alias, episodeID: episode.id) {
                perEpisode[episode.id] = progress
            }
        }
        guard !Task.isCancelled else { return }
        episodeProgress = perEpisode
    }

    private static func isUnauthorized(_ error: AniLibertyError) -> Bool {
        if case let .httpStatus(status) = error {
            return status == 401 || status == 403
        }
        return false
    }

    /// Plain text for the synopsis: the API ships `\r\n` pairs that SwiftUI would otherwise honour.
    var synopsis: String {
        (release?.description ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Episodes of the loaded release, empty until it arrives.
    var episodes: [Episode] {
        release?.episodes ?? []
    }

    var genres: [Genre] {
        release?.genres ?? []
    }

    /// Whether the viewer asked for the full synopsis. Whether the text *can* be collapsed is a
    /// rendering question and is measured by the view, not guessed from a character count here.
    private(set) var isDescriptionExpanded = false

    func toggleDescriptionExpanded() {
        isDescriptionExpanded.toggle()
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await load()
    }

    func reload() async {
        await load()
    }

    private func load() async {
        state = .loading
        do {
            let release = try await client.release(idOrAlias: route.alias)
            guard !Task.isCancelled else { return }
            state = .loaded(release)
            await loadProgress()
            await loadFavoritesState()
            Self.logger
                .info(
                    "Loaded release \(release.alias, privacy: .public) with \(release.episodes.count, privacy: .public) episodes"
                )
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            Self.logger.error("Release detail failed: \(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }
}
