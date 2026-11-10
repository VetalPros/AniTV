import AniLibertyKit
import Foundation

/// Everything the player screen needs, resolved once on the detail screen.
///
/// Resolving the stream URL before presenting the player keeps `AVPlayer` setup synchronous and
/// makes the "release is not playable" case a disabled button instead of a runtime failure.
struct PlaybackRequest: Identifiable {
    let id: UUID
    let releaseTitle: String
    let episodeTitle: String
    let episode: Episode
    let source: PlaybackSource
}
