import Foundation

/// Carries `UserDefaults` across concurrency boundaries.
///
/// `UserDefaults` is documented as thread-safe but is not marked `Sendable`, so the promise is stated once
/// here and shared by ``PlaybackProgressStore``, ``PlaybackSettingsStore`` and ``PosterScaleStore``.
final class DefaultsBox: @unchecked Sendable {
    let value: UserDefaults

    init(_ value: UserDefaults) {
        self.value = value
    }
}
