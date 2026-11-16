import Foundation

/// Default ``PlaybackProgressStoring`` implementation backed by `UserDefaults`.
///
/// Every release owns one key holding one JSON object, so forgetting one title never
/// touches another. Persistence is best effort by design: a value that cannot be encoded
/// or decoded is treated as missing rather than turning into a playback failure.
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
    /// A payload that is not valid JSON, or that no longer matches the current schema,
    /// reads as `nil`; nothing is thrown and nothing is removed.
    ///
    /// - Parameter alias: Alias of the release.
    /// - Returns: The stored progress, or `nil`.
    public func progress(forReleaseAlias alias: String) async -> PlaybackProgress? {
        guard let data = defaults.value.data(forKey: Self.storageKey(forReleaseAlias: alias)) else {
            return nil
        }
        return try? JSONDecoder().decode(PlaybackProgress.self, from: data)
    }

    /// Stores a progress value, replacing the previous one of the same release.
    ///
    /// Encoding failures are swallowed: a position that cannot be serialised (for example
    /// a non-finite number) is simply not persisted.
    ///
    /// - Parameter progress: Value recorded by the player.
    public func save(_ progress: PlaybackProgress) async {
        guard let data = try? JSONEncoder().encode(progress) else {
            return
        }
        defaults.value.set(data, forKey: Self.storageKey(forReleaseAlias: progress.releaseAlias))
    }

    /// Forgets the stored progress of a release.
    ///
    /// - Parameter alias: Alias of the release to forget.
    public func clearProgress(forReleaseAlias alias: String) async {
        defaults.value.removeObject(forKey: Self.storageKey(forReleaseAlias: alias))
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
