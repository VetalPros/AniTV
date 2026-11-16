import Foundation

/// Where playback of one episode stopped, as persisted between launches.
///
/// The player writes a value every few seconds; the release detail screen then asks
/// ``isResumable`` whether offering «Продолжить» makes sense. The type is `Codable` so
/// ``PlaybackProgressStore`` can keep it as one JSON object per release.
public struct PlaybackProgress: Sendable, Codable, Equatable {
    /// Position, in seconds, below which a resume prompt is pointless.
    ///
    /// Anything in the first seconds of an episode is almost certainly an accidental
    /// tap, not a deliberate stop, so resuming there only annoys the viewer.
    public static let minimumResumableOffset: Double = 15

    /// Distance from the end, in seconds, below which the episode counts as finished.
    ///
    /// Offering to resume into the credits is worse than restarting from the beginning,
    /// so a position this close to the end is not resumable.
    public static let minimumRemainingSeconds: Double = 30

    /// Alias of the release the episode belongs to, e.g. `mezametara-saikyou-soubi`.
    public let releaseAlias: String
    /// Identifier of the episode, matching ``Episode/id``.
    public let episodeID: UUID
    /// Playback position in seconds from the start of the episode.
    public let position: Double
    /// Episode duration in seconds, or `nil` when the API did not publish one.
    public let duration: Double?
    /// Moment the position was recorded, used to break ties between devices.
    public let updatedAt: Date

    /// Creates a progress value.
    ///
    /// - Parameters:
    ///   - releaseAlias: Alias of the release the episode belongs to.
    ///   - episodeID: Identifier of the episode.
    ///   - position: Playback position in seconds.
    ///   - duration: Episode duration in seconds; `nil` when unknown.
    ///   - updatedAt: Moment the position was recorded; defaults to now.
    public init(
        releaseAlias: String,
        episodeID: UUID,
        position: Double,
        duration: Double?,
        updatedAt: Date = .now
    ) {
        self.releaseAlias = releaseAlias
        self.episodeID = episodeID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    /// Seconds of playback left, or `nil` when the duration is unknown.
    ///
    /// The value is clamped at zero, so a position past the end reports no time left
    /// instead of a negative number.
    public var remainingSeconds: Double? {
        guard let duration else {
            return nil
        }
        return max(0, duration - position)
    }

    /// Whether the episode should be offered as «Продолжить».
    ///
    /// The rules are deliberately conservative:
    /// * the position must reach ``minimumResumableOffset``, so the first seconds are
    ///   never resumed;
    /// * when the duration is known, at least ``minimumRemainingSeconds`` of the episode
    ///   must remain, so the credits are never resumed;
    /// * when the duration is unknown, only the lower bound applies.
    ///
    /// A progress that fails these rules is still stored: the viewer may have stopped it
    /// deliberately, and the app can offer «Смотреть» from the beginning instead.
    public var isResumable: Bool {
        guard position >= Self.minimumResumableOffset else {
            return false
        }
        guard let duration else {
            return true
        }
        return duration - position >= Self.minimumRemainingSeconds
    }
}
