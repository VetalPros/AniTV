import AniLibertyKit
import Foundation

/// Localised presentation helpers the Kit deliberately keeps out of the model layer.
extension Episode {
    /// Human-readable episode length, or `nil` when the API did not provide one.
    var localizedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        return Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
    }
}
