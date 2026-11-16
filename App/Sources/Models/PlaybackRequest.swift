import AniLibertyKit
import Foundation

/// Everything the player screen needs, resolved once on the detail screen.
///
/// Resolving the stream URL before presenting the player keeps `AVPlayer` setup synchronous and
/// makes the "release is not playable" case a disabled button instead of a runtime failure.
struct PlaybackRequest: Identifiable {
    let id: UUID
    /// Alias of the release, used as the key of the persisted playback progress.
    let releaseAlias: String
    let releaseTitle: String
    let episodeTitle: String
    let episode: Episode
    let source: PlaybackSource
    /// Position to start at, or `nil` to play the episode from the beginning.
    let startAt: TimeInterval?
}
