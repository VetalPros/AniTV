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
}
