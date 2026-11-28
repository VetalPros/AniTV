import Foundation

/// How the player should treat openings and endings without asking.
///
/// Both switches are off by default: a viewer who never opened the settings must still see the skip control
/// and decide for themselves. Turning one on means "do not show me this part", and the player then seeks past
/// it silently.
public struct PlaybackSettings: Sendable, Equatable {
    /// Seek past every opening automatically.
    public var skipsOpenings: Bool
    /// Seek past every ending automatically.
    public var skipsEndings: Bool

    /// Settings a fresh install starts with: nothing is skipped.
    public static let defaults = PlaybackSettings(skipsOpenings: false, skipsEndings: false)

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - skipsOpenings: Whether openings are skipped without asking.
    ///   - skipsEndings: Whether endings are skipped without asking.
    public init(skipsOpenings: Bool, skipsEndings: Bool) {
        self.skipsOpenings = skipsOpenings
        self.skipsEndings = skipsEndings
    }
}

/// Storage seam for ``PlaybackSettings`` so the app can inject a throwaway domain in tests.
public protocol PlaybackSettingsStoring: Sendable {
    /// Reads the stored settings.
    ///
    /// - Returns: The stored value, or ``PlaybackSettings/defaults`` when nothing usable is stored.
    func load() async -> PlaybackSettings
    /// Writes the settings, replacing what was there.
    ///
    /// - Parameter settings: Value to persist.
    func save(_ settings: PlaybackSettings) async
}

/// `UserDefaults`-backed ``PlaybackSettingsStoring``.
///
/// These are preferences, not secrets: the token never comes near this type. A payload that cannot be decoded
/// reads as ``PlaybackSettings/defaults`` so a broken domain can never leave the app in a state nobody chose.
public final class PlaybackSettingsStore: PlaybackSettingsStoring {
    /// Keys the store writes.
    public enum Key {
        /// Whether openings are skipped automatically.
        public static let skipsOpenings = "tv.anitv.playback.skipsOpenings"
        /// Whether endings are skipped automatically.
        public static let skipsEndings = "tv.anitv.playback.skipsEndings"
    }

    private let defaults: DefaultsBox

    /// Creates a store.
    ///
    /// - Parameter defaults: Domain to persist into — `.standard` in the app, a throwaway suite in tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = DefaultsBox(defaults)
    }

    /// Reads the stored settings.
    ///
    /// - Returns: Stored switches, or ``PlaybackSettings/defaults`` when a key was never written.
    public func load() async -> PlaybackSettings {
        PlaybackSettings(
            skipsOpenings: defaults.value.bool(forKey: Key.skipsOpenings),
            skipsEndings: defaults.value.bool(forKey: Key.skipsEndings)
        )
    }

    /// Stores the settings.
    ///
    /// - Parameter settings: Value to persist.
    public func save(_ settings: PlaybackSettings) async {
        defaults.value.set(settings.skipsOpenings, forKey: Key.skipsOpenings)
        defaults.value.set(settings.skipsEndings, forKey: Key.skipsEndings)
    }
}
