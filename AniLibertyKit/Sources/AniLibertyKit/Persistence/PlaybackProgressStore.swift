import Foundation

/// Default ``PlaybackProgressStoring`` implementation backed by `UserDefaults`.
///
/// Every release owns one key, and that key holds a JSON array of episode records. Keeping
/// the whole release in one slot means forgetting a title is a single `removeObject`, and
/// the array stays small: a release has as many entries as episodes the viewer has
/// actually started.
///
/// Keys written by earlier versions of the kit hold a single JSON object instead of an
/// array. Those payloads are still read (the object becomes the only record of the
/// release), and the next ``save(_:)`` rewrites the key in the array shape, so nothing is
/// lost during the upgrade.
///
/// Persistence is best effort by design: a value that cannot be encoded or decoded is
/// treated as missing rather than turning into a playback failure.
///
/// Payloads written by this version are arrays. A build of the kit from before per-episode
/// progress would read such a key as missing (and lose the resume prompt until the next
/// save), which is the price of keeping the format a plain `Codable` array.
///
/// The store is a `Sendable` value-like service rather than an actor: it keeps no mutable
/// state of its own and delegates thread safety to `UserDefaults`, which Apple documents as
/// thread-safe.
public final class PlaybackProgressStore: PlaybackProgressStoring {
    /// Prefix shared by every key the store writes.
    public static let keyPrefix = "tv.anitv.playbackProgress."

    private let defaults: DefaultsBox

    /// Creates a store.
    ///
    /// - Parameter defaults: Domain to persist into — `.standard` in the app, a throwaway
    ///   suite in tests. The domain is injected so tests never touch the real one.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = DefaultsBox(defaults)
    }

    /// Key under which the progress of a release is stored.
    ///
    /// Exposed so tests and diagnostics can address the same slot the store uses.
    ///
    /// - Parameter alias: Alias of the release, e.g. `mezametara-saikyou-soubi`.
    /// - Returns: Key composed of ``keyPrefix`` and the alias.
    public static func storageKey(forReleaseAlias alias: String) -> String {
        keyPrefix + alias
    }

    /// Most recent progress stored for a release, resumable or not.
    ///
    /// "Most recent" is decided by ``PlaybackProgress/updatedAt``; when two records share a
    /// timestamp the one further into its episode wins, because it is the more informative
    /// resume point.
    ///
    /// A payload that is not valid JSON, or that matches neither the current array shape
    /// nor the legacy single-object shape, reads as `nil`; nothing is thrown and nothing is
    /// removed.
    ///
    /// - Parameter alias: Alias of the release.
    /// - Returns: The stored progress, or `nil`.
    public func progress(forReleaseAlias alias: String) async -> PlaybackProgress? {
        records(forReleaseAlias: alias).max(by: Self.isOlder)
    }

    /// Progress stored for one specific episode of a release.
    ///
    /// - Parameters:
    ///   - alias: Alias of the release.
    ///   - episodeID: Identifier of the episode.
    /// - Returns: The record of that episode, or `nil` when it was never played.
    public func progress(forReleaseAlias alias: String, episodeID: UUID) async -> PlaybackProgress? {
        records(forReleaseAlias: alias)
            .filter { $0.episodeID == episodeID }
            .max(by: Self.isOlder)
    }

    /// Stores a progress value, upserting the record of its episode.
    ///
    /// Records of other episodes of the same release survive, and the key is rewritten in
    /// the current array shape even when it held the legacy single-object payload.
    ///
    /// Encoding failures are swallowed: a position that cannot be serialised (for example
    /// a non-finite number) is simply not persisted.
    ///
    /// - Parameter progress: Value recorded by the player.
    public func save(_ progress: PlaybackProgress) async {
        var stored = records(forReleaseAlias: progress.releaseAlias)
        stored.removeAll { $0.episodeID == progress.episodeID }
        stored.append(progress)

        guard let data = try? JSONEncoder().encode(stored) else {
            return
        }
        defaults.value.set(data, forKey: Self.storageKey(forReleaseAlias: progress.releaseAlias))
    }

    /// Forgets every stored record of a release.
    ///
    /// - Parameter alias: Alias of the release to forget.
    public func clearProgress(forReleaseAlias alias: String) async {
        defaults.value.removeObject(forKey: Self.storageKey(forReleaseAlias: alias))
    }

    /// Reads every record of a release, accepting both the current and the legacy shape.
    private func records(forReleaseAlias alias: String) -> [PlaybackProgress] {
        guard let data = defaults.value.data(forKey: Self.storageKey(forReleaseAlias: alias)) else {
            return []
        }
        if let records = try? JSONDecoder().decode([PlaybackProgress].self, from: data) {
            return records
        }
        // Before per-episode progress the key held one object; treat it as the only record.
        if let single = try? JSONDecoder().decode(PlaybackProgress.self, from: data) {
            return [single]
        }
        return []
    }

    /// Orders records from the least to the most recent.
    private static func isOlder(_ lhs: PlaybackProgress, _ rhs: PlaybackProgress) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.position < rhs.position
    }
}

/// Carries `UserDefaults` across concurrency boundaries.
///
/// `UserDefaults` is documented as thread-safe but is not marked `Sendable`, so the promise
/// is stated once, here, instead of at every call site.
private final class DefaultsBox: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
