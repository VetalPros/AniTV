import Foundation

/// A skippable range of one episode, resolved into concrete seconds.
///
/// `AVPlayerViewController` receives these through `transportBarCustomMenuItems`, and the
/// "skip intro" affordance appears while `playhead` is inside `[start, end)`.
public struct SkipTimecode: Sendable, Equatable {
    /// Which part of the episode the range belongs to.
    public enum Kind: Sendable {
        /// Opening title sequence.
        case opening
        /// Ending credits.
        case ending
    }

    /// Kind of the range.
    public let kind: Kind
    /// First second of the range.
    public let start: Double
    /// Second at which the range is already over.
    public let end: Double
    /// Identifier of the episode the range belongs to.
    public let releaseEpisodeID: UUID
}

/// Extracts skippable ranges from an episode and tells which one is active.
public enum TimecodeResolver {
    /// All usable skip ranges of `episode`, opening first, then ending.
    ///
    /// The API occasionally publishes partial ranges (only `start` or only `stop`) or
    /// zero-length ones; those are ignored instead of confusing the player.
    ///
    /// - Parameter episode: Episode decoded from the release detail endpoint.
    /// - Returns: Ranges in payload order; empty when the episode has no usable range.
    public static func timecodes(for episode: Episode) -> [SkipTimecode] {
        var timecodes: [SkipTimecode] = []
        if let range = validRange(episode.opening) {
            timecodes.append(
                SkipTimecode(
                    kind: .opening,
                    start: range.start,
                    end: range.end,
                    releaseEpisodeID: episode.id
                )
            )
        }
        if let range = validRange(episode.ending) {
            timecodes.append(
                SkipTimecode(
                    kind: .ending,
                    start: range.start,
                    end: range.end,
                    releaseEpisodeID: episode.id
                )
            )
        }
        return timecodes
    }

    /// The timecode covering `playhead`, if any.
    ///
    /// - Parameters:
    ///   - timecodes: Ranges previously produced by `timecodes(for:)`.
    ///   - playhead: Current playback position in seconds.
    /// - Returns: The matching range, or `nil` when the playhead is outside all of them.
    public static func activeSkip(for timecodes: [SkipTimecode], playhead: Double) -> SkipTimecode? {
        timecodes.first { playhead >= $0.start && playhead < $0.end }
    }

    private static func validRange(_ range: Episode.SkipRange?) -> (start: Double, end: Double)? {
        guard let range, let start = range.start, let stop = range.stop, stop > start else {
            return nil
        }
        return (start, stop)
    }
}
