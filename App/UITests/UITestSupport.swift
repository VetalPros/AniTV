import Foundation

/// Launch arguments the app understands, mirrored here because a UI-test bundle cannot import the app
/// module. The values are asserted against the app's own constants by the tests that use them.
enum UITestLaunchArguments {
    /// Makes the app behave as if this TV were never paired (`AuthTokenStoreFactory.signedOutArgument`).
    static let signedOut = "-uiTestingSignedOut"
    /// Overrides the auto-refresh interval in seconds (`AutoRefreshPolicy.intervalArgument`).
    static let refreshInterval = "-uiTestingRefreshInterval"
    /// Overrides how long "away" must be before a visible screen reloads (`AutoRefreshPolicy.staleAfterArgument`).
    static let staleAfter = "-uiTestingStaleAfter"
    /// Starts the player inside the episode's opening (`PlayerTestOverrides.startAtOpeningArgument`).
    static let startAtOpening = "-uiTestingStartAtOpening"
    /// Starts the player inside the episode's ending (`PlayerTestOverrides.startAtEndingArgument`).
    static let startAtEnding = "-uiTestingStartAtEnding"
    /// Makes the picker start on an episode with an opening (`PlayerTestOverrides.pickEpisodeWithOpeningArgument`).
    static let pickEpisodeWithOpening = "-uiTestingPickEpisodeWithOpening"
    /// Makes the picker start on an episode whose ending runs into the end of the file.
    static let pickEpisodeWithShortEnding = "-uiTestingPickEpisodeWithShortEnding"

    /// Restores both playback switches to their shipped defaults at launch.
    static let resetSettings = "-uiTestingResetSettings"

    /// Opens a specific sidebar section at launch (`RootShellView.initialSection`), so a test can reach
    /// every screen without steering focus through the panel.
    static let section = "-uiTestingSection"

    /// Launch arguments that open `section` on «Главная» / «Поиск» / «Профиль» / «Настройки».
    static func opening(section name: String) -> [String] {
        [section, name]
    }

    /// Launch argument that sets the skip hint's lifetime (`PlayerTestOverrides.hintLifetime`).
    static let hintLifetimeKey = "-uiTestingHintLifetime"

    /// Shortens the skip hint's lifetime, so a test can watch it expire instead of waiting thirty seconds.
    ///
    /// - Parameter seconds: Lifetime the player should use.
    /// - Returns: The launch argument and its value, ready to append to a launch-argument list.
    static func hintLifetime(_ seconds: Int) -> [String] {
        [hintLifetimeKey, String(seconds)]
    }
}
