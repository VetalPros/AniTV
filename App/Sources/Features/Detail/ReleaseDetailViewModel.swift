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

    @ObservationIgnored private let client: AniLibertyClient

    init(route: ReleaseRoute, client: AniLibertyClient = AniLibertyClient()) {
        self.route = route
        self.client = client
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
    func playbackRequest(for episode: Episode) -> PlaybackRequest? {
        guard let release, let source = StreamResolver.preferredSource(for: episode) else {
            return nil
        }
        return PlaybackRequest(
            id: episode.id,
            releaseTitle: release.title,
            episodeTitle: episode.displayTitle,
            episode: episode,
            source: source
        )
    }

    /// Plain text for the synopsis: the API ships `\r\n` pairs that SwiftUI would otherwise honour.
    var synopsis: String {
        (release?.description ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var genres: [Genre] {
        release?.genres ?? []
    }

    /// Synopsis longer than this is collapsed behind a "read more" control.
    static let synopsisThreshold = 420

    private(set) var isDescriptionExpanded = false

    var isSynopsisExpandable: Bool {
        synopsis.count > Self.synopsisThreshold
    }

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
