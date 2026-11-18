import Foundation

/// What the player should offer while the playhead is inside an episode's ending.
public enum EndingOffer: Sendable, Equatable {
    /// Rewind past the credits and keep watching: there is something after them.
    case skip
    /// The credits run into the end of the file, so the useful action is the next episode.
    case nextEpisode
}

/// Decides between ``EndingOffer/skip`` and ``EndingOffer/nextEpisode``.
///
/// The service publishes an `ending` range per episode, but the range does not always end at the end of the
/// file: measured on 2026-11-17, some episodes carry 26, 43 or even 120 seconds of content after the credits —
/// a next-episode preview or an insert that a viewer would not want thrown away. Skipping straight to the
/// next episode there would silently lose it, so the offer depends on the tail.
public enum EndingOfferResolver {
    /// Longest tail still treated as "the credits run into the end".
    ///
    /// Calibrated on six releases from the fresh feed: tails cluster at 0–12 s (credits to the end) and at
    /// 25 s and above (insert or preview), with 15 s separating the clusters and leaving room on both sides.
    public static let tailThreshold: TimeInterval = 15

    /// Decides what to offer for an ending.
    ///
    /// - Parameters:
    ///   - ending: The ending range the playhead is inside.
    ///   - duration: Length of the episode in seconds, when the service published it.
    ///   - hasNextEpisode: Whether the release has another playable episode after this one.
    /// - Returns: The action to offer. Without a known duration or a next episode there is nothing better to
    ///   do than the plain skip, which never throws content away.
    public static func offer(
        ending: SkipTimecode,
        duration: Double?,
        hasNextEpisode: Bool
    ) -> EndingOffer {
        guard hasNextEpisode, let duration, duration > 0 else {
            return .skip
        }
        let tail = duration - ending.end
        return tail <= tailThreshold ? .nextEpisode : .skip
    }
}
