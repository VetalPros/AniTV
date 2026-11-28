import Foundation
import XCTest

/// Launch arguments the app understands, mirrored here because a UI-test bundle cannot import the app
/// module. The values are asserted against the app's own constants by the tests that use them.
enum UITestLaunchArguments {
    /// Makes the app behave as if this TV were never paired (`AuthTokenStoreFactory.signedOutArgument`).
    static let signedOut = "-uiTestingSignedOut"
    /// Overrides the auto-refresh interval in seconds (`AutoRefreshPolicy.intervalArgument`).
    static let refreshInterval = "-uiTestingRefreshInterval"
    /// Overrides how long "away" must be before a visible screen reloads (`AutoRefreshPolicy.staleAfterArgument`).
    static let staleAfter = "-uiTestingStaleAfter"
    /// Exposes the freshness instants as hidden accessibility elements (`RefreshProbe.argument`). The
    /// caption a viewer used to see is gone, so this is the only way a test can watch the refresh clock.
    static let refreshProbe = "-uiTestingRefreshProbe"
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

/// Expectation helpers for the UI tests: wait for a condition, not for a fixed number of seconds.
@MainActor
enum UITestWait {
    /// Polls `condition` until it holds or the timeout expires.
    static func until(_ timeout: TimeInterval, poll: TimeInterval = 0.25, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: poll)
        }
        return condition()
    }

    /// Waits for an element to leave the accessibility tree.
    static func forDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        until(timeout) { !element.exists }
    }

    /// Waits until the element's label differs from `previous`, and returns the label it settled on.
    static func forLabelChange(of element: XCUIElement, from previous: String, timeout: TimeInterval) -> String {
        _ = until(timeout) { element.exists && element.label != previous }
        return element.label
    }
}

/// The sidebar sections of the shell (ADR 0028), in the order they are stacked vertically.
///
/// The rows focus as anonymous containers — the row buttons keep their identifiers but are not what the
/// focus engine reports — so a section cannot be found by identifier. It can be reached by geometry:
/// clamp the focus to the first row with Up, then step Down once per row, which is what
/// `ShellNavigator` does.
enum ShellSection: String, CaseIterable {
    case search
    case home
    case catalog
    case settings

    /// What proves the section is on display once Select has been pressed.
    var markers: [String] {
        switch self {
        case .search: ["catalog.searchField"]
        case .home: ["latest.posterCard"]
        case .catalog: ["catalog.genreChip"]
        case .settings: ["settings.screen"]
        }
    }
}

/// Walks the remote into the sidebar, because there is no tab bar to walk up into any more.
/// What proves the profile cover is on screen, signed out or signed in.
let profileMarkers = ["profile.pairingCode", "profile.reconnect", "profile.displayName"]

/// Accessibility identifier of the account entry in the panel header (ADR 0032).
let accountHeaderIdentifier = "shell.account"

@MainActor
enum ShellNavigator {
    /// Moves focus onto `section`'s row and presses Select, without waiting for a particular screen: use
    /// this when the section is expected to come back on a pushed detail rather than on its root.
    @discardableResult
    static func select(_ section: ShellSection, in app: XCUIApplication, settle: TimeInterval = 1.2) -> Bool {
        guard enterPanel(in: app) else { return false }

        // Clamp to the top, then step down once per row: the panel is one focus column. The account header
        // sits above the rows and takes focus too (ADR 0032), so the clamp lands on it and it is skipped.
        for _ in 0 ..< ShellSection.allCases.count + 1 {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.35)
        }
        if accountHeaderIsFocused(in: app) {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.35)
        }
        for _ in 0 ..< rowIndex(of: section) {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: settle)
        return true
    }

    /// Opens `section` from wherever focus is, and proves it by waiting for the section's own marker.
    static func open(
        _ section: ShellSection,
        in app: XCUIApplication,
        settle: TimeInterval = 1.2,
        timeout: TimeInterval = 20
    ) -> Bool {
        guard select(section, in: app, settle: settle) else { return false }
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", section.markers))
            .firstMatch
        // Signed-in screens go to the network before they have anything to show, so the wait is generous.
        return marker.waitForExistence(timeout: timeout)
    }

    /// Opens the profile cover from the panel header, which sits above the section rows.
    static func openProfile(in app: XCUIApplication, timeout: TimeInterval = 25) -> Bool {
        guard enterPanel(in: app) else { return false }
        let header = app.descendants(matching: .any)[accountHeaderIdentifier].firstMatch
        for _ in 0 ..< 6 where !(header.exists && header.hasFocus) {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard header.exists, header.hasFocus else { return false }
        XCUIRemote.shared.press(.select)
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", profileMarkers))
            .firstMatch
        return marker.waitForExistence(timeout: timeout)
    }

    /// Whether the panel's account header currently holds focus.
    static func accountHeaderIsFocused(in app: XCUIApplication) -> Bool {
        let header = app.descendants(matching: .any)[accountHeaderIdentifier].firstMatch
        return header.exists && header.hasFocus
    }

    /// Whether this TV is paired, read from the account header's value; `nil` while it is still loading.
    static func accountSignedIn(in app: XCUIApplication) -> Bool? {
        guard enterPanel(in: app) else { return nil }
        let header = app.descendants(matching: .any)[accountHeaderIdentifier].firstMatch
        for _ in 0 ..< 6 where !(header.exists && header.hasFocus) {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard header.exists, let value = header.value as? String else { return nil }
        switch value {
        case "signedIn": return true
        case "signedOut": return false
        default: return nil
        }
    }

    /// Closes the profile cover with Back and waits for the shell to be reachable again.
    static func closeProfile(in app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        guard app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", profileMarkers)).firstMatch.exists
        else { return true }
        XCUIRemote.shared.press(.menu)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let stillOpen = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier IN %@", profileMarkers)).firstMatch.exists
            if !stillOpen {
                return true
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    /// Presses Left until the focus engine reports a panel row rather than content.
    static func enterPanel(in app: XCUIApplication, attempts: Int = 8) -> Bool {
        for _ in 0 ..< attempts {
            if panelRowIsFocused(in: app) {
                return true
            }
            XCUIRemote.shared.press(.left)
            Thread.sleep(forTimeInterval: 0.45)
        }
        return panelRowIsFocused(in: app)
    }

    /// A panel row focuses as an unnamed element pinned to the leading edge and about one row tall; content
    /// focus always carries an identifier.
    static func panelRowIsFocused(in app: XCUIApplication) -> Bool {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1"))
            .firstMatch
        guard element.exists else { return false }
        let frame = element.frame
        let isAccountHeader = element.identifier == accountHeaderIdentifier
        return (element.identifier.isEmpty || isAccountHeader) && frame.minX <= 1 && frame.width > 300 && frame
            .height < 100
    }

    /// Presses the remote until the element carrying `identifier` holds focus.
    ///
    /// Right leaves the panel for the content and Down walks rows or posters, so alternating covers both a
    /// focus parked in the sidebar and one already inside the grid.
    static func focus(_ identifier: String, in app: XCUIApplication, attempts: Int = 12) -> Bool {
        for step in 0 ..< attempts {
            let element = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", identifier))
                .firstMatch
            if element.exists {
                return true
            }
            XCUIRemote.shared.press(step.isMultiple(of: 2) ? .right : .down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private static func rowIndex(of section: ShellSection) -> Int {
        ShellSection.allCases.firstIndex(of: section) ?? 0
    }

    private static func settleFor(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                return true
            }
            usleep(200_000)
        }
        return false
    }
}
