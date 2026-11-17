import Foundation

/// Persistence seam for playback positions.
///
/// The app depends on this protocol, not on ``PlaybackProgressStore``, so previews and UI
/// tests can inject an in-memory fake. Methods are asynchronous because the production
/// implementation may be an actor or a thread-safe service.
///
/// A release may have progress for several episodes at once; ``progress(forReleaseAlias:)``
/// answers with the most recent one, which is what the «Продолжить» button on the release
/// detail screen needs.
public protocol PlaybackProgressStoring: Sendable {
    /// Most recent progress stored for a release, resumable or not.
    ///
    /// - Parameter alias: Alias of the release, e.g. `mezametara-saikyou-soubi`.
    /// - Returns: The most recently updated record of the release, or `nil` when there is
    ///   none or the payload cannot be read.
    func progress(forReleaseAlias alias: String) async -> PlaybackProgress?

    /// Progress stored for one specific episode of a release.
    ///
    /// - Parameters:
    ///   - alias: Alias of the release.
    ///   - episodeID: Identifier of the episode, matching ``Episode/id``.
    /// - Returns: The record of that episode, or `nil` when it was never played.
    func progress(forReleaseAlias alias: String, episodeID: UUID) async -> PlaybackProgress?

    /// Stores a progress value, replacing the previous record of the same episode.
    ///
    /// Records of other episodes of the same release are kept.
    ///
    /// - Parameter progress: Value recorded by the player.
    func save(_ progress: PlaybackProgress) async

    /// Forgets every stored record of a release.
    ///
    /// - Parameter alias: Alias of the release to forget.
    func clearProgress(forReleaseAlias alias: String) async
}

public extension PlaybackProgressStoring {
    /// Default implementation for stores that keep a single record per release: the
    /// record counts only when it belongs to the requested episode.
    ///
    /// - Parameters:
    ///   - alias: Alias of the release.
    ///   - episodeID: Identifier of the episode.
    /// - Returns: The record of that episode, or `nil`.
    func progress(forReleaseAlias alias: String, episodeID: UUID) async -> PlaybackProgress? {
        guard let progress = await progress(forReleaseAlias: alias), progress.episodeID == episodeID else {
            return nil
        }
        return progress
    }

    /// Progress of a release, but only when it is worth resuming.
    ///
    /// The release detail screen uses this to decide between «Смотреть» and
    /// «Продолжить»: a nil result means the episode should start from the beginning.
    ///
    /// - Parameter alias: Alias of the release, e.g. `mezametara-saikyou-soubi`.
    /// - Returns: The stored progress when ``PlaybackProgress/isResumable`` holds,
    ///   otherwise `nil`.
    func resumableProgress(forReleaseAlias alias: String) async -> PlaybackProgress? {
        guard let progress = await progress(forReleaseAlias: alias), progress.isResumable else {
            return nil
        }
        return progress
    }

    /// Progress of one episode, but only when it is worth resuming.
    ///
    /// The player uses this when it opens an episode.
    ///
    /// - Parameters:
    ///   - alias: Alias of the release.
    ///   - episodeID: Identifier of the episode.
    /// - Returns: The stored progress when ``PlaybackProgress/isResumable`` holds,
    ///   otherwise `nil`.
    func resumableProgress(forReleaseAlias alias: String, episodeID: UUID) async -> PlaybackProgress? {
        guard let progress = await progress(forReleaseAlias: alias, episodeID: episodeID),
              progress.isResumable
        else {
            return nil
        }
        return progress
    }
}
