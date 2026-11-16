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

    @ObservationIgnored private let client: AniLibertyClient
    @ObservationIgnored private let progressStore: PlaybackProgressStoring

    init(
        route: ReleaseRoute,
        client: AniLibertyClient = AniLibertyClient(),
        progressStore: PlaybackProgressStoring = PlaybackProgressStore()
    ) {
        self.route = route
        self.client = client
        self.progressStore = progressStore
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
            startAt: startAt
        )
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

    /// Asks the store again — used when the player closes, so the screen reflects the position that was
    /// just saved instead of the one it was opened with.
    func refreshResumeProgress() async {
        let alias = route.alias
        let progress = await progressStore.resumableProgress(forReleaseAlias: alias)
        guard !Task.isCancelled else { return }
        resumeProgress = progress
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
            await refreshResumeProgress()
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
