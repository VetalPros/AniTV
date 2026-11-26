import Foundation

/// Launch-argument overrides for the player, in the same spirit as the app's other UI-test seams.
///
/// The skip hint only appears while the playhead is inside an opening or an ending, and a test cannot
/// spend twenty minutes of playback reaching the ending. A launch argument lets a test start the episode
/// at an arbitrary second; production never passes it.
enum PlayerTestOverrides {
    /// Launch argument with the playback position, in seconds, to start from.
    static let startAtArgument = "-uiTestingStartAt"
    /// Launch argument that starts playback two seconds into the episode's opening.
    static let startAtOpeningArgument = "-uiTestingStartAtOpening"
    /// Launch argument that makes the episode picker start on an episode with an opening.
    static let pickEpisodeWithOpeningArgument = "-uiTestingPickEpisodeWithOpening"
    /// Launch argument that makes the picker start on an episode whose ending runs into the end of the file.
    static let pickEpisodeWithShortEndingArgument = "-uiTestingPickEpisodeWithShortEnding"
    /// Launch argument with the hint's lifetime in seconds, so a test can watch it expire quickly.
    static let hintLifetimeArgument = "-uiTestingHintLifetime"
    /// Launch argument that starts playback two seconds into the episode's ending.
    static let startAtEndingArgument = "-uiTestingStartAtEnding"

    /// Position the app should start playback at, when the argument is present and valid.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: Seconds to seek to, or `nil` for the request's own position.
    static func startAt(arguments: [String] = ProcessInfo.processInfo.arguments) -> TimeInterval? {
        guard let index = arguments.firstIndex(of: startAtArgument),
              arguments.indices.contains(index + 1),
              let value = TimeInterval(arguments[index + 1]),
              value >= 0
        else {
            return nil
        }
        return value
    }

    /// Whether playback should start inside the opening.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: `true` when the opening argument is present.
    static func startsAtOpening(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(startAtOpeningArgument)
    }

    /// Whether the picker should prefer an episode that has an opening.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: `true` when the argument is present.
    static func picksEpisodeWithOpening(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(pickEpisodeWithOpeningArgument)
    }

    /// How long the skip hint should live, when the test asks for a shorter life.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: Lifetime in seconds, or `nil` for the production value.
    static func hintLifetime(arguments: [String] = ProcessInfo.processInfo.arguments) -> Duration? {
        guard let index = arguments.firstIndex(of: hintLifetimeArgument),
              arguments.indices.contains(index + 1),
              let seconds = Double(arguments[index + 1]),
              seconds > 0
        else {
            return nil
        }
        return .seconds(seconds)
    }

    /// Whether the picker should prefer an episode whose ending runs into the end of the file.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: `true` when the argument is present.
    static func picksEpisodeWithShortEnding(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(pickEpisodeWithShortEndingArgument)
    }

    /// Whether playback should start inside the ending.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: `true` when the ending argument is present.
    static func startsAtEnding(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(startAtEndingArgument)
    }
}
