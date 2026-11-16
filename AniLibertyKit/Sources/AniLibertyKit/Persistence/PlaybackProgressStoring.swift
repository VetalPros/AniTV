import Foundation

/// Persistence seam for playback positions.
///
/// The app depends on this protocol, not on ``PlaybackProgressStore``, so previews and UI
/// tests can inject an in-memory fake. Methods are asynchronous because the production
/// implementation is an actor.
public protocol PlaybackProgressStoring: Sendable {
    /// Most recent progress stored for a release, resumable or not.
    ///
    /// - Parameter alias: Alias of the release, e.g. `mezametara-saikyou-soubi`.
    /// - Returns: The stored progress, or `nil` when there is none or the payload cannot
    ///   be read.
    func progress(forReleaseAlias alias: String) async -> PlaybackProgress?

    /// Stores a progress value, replacing the previous one of the same release.
    ///
    /// - Parameter progress: Value recorded by the player.
    func save(_ progress: PlaybackProgress) async

    /// Forgets the stored progress of a release.
    ///
    /// - Parameter alias: Alias of the release to forget.
    func clearProgress(forReleaseAlias alias: String) async
}

public extension PlaybackProgressStoring {
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
}
