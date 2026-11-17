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

    /// Whether playback should start inside the ending.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: `true` when the ending argument is present.
    static func startsAtEnding(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(startAtEndingArgument)
    }
}
