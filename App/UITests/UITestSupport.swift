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
    case profile
    case settings

    /// What proves the section is on display once Select has been pressed.
    var markers: [String] {
        switch self {
        case .search: ["catalog.searchField"]
        case .home: ["latest.posterCard"]
        case .catalog: ["catalog.genreChip"]
        case .profile: ["profile.pairingCode", "profile.reconnect"]
        case .settings: ["settings.screen"]
        }
    }
}

/// Walks the remote into the sidebar, because there is no tab bar to walk up into any more.
@MainActor
enum ShellNavigator {
    /// Moves focus onto `section`'s row and presses Select, without waiting for a particular screen: use
    /// this when the section is expected to come back on a pushed detail rather than on its root.
    @discardableResult
    static func select(_ section: ShellSection, in app: XCUIApplication, settle: TimeInterval = 1.2) -> Bool {
        guard enterPanel(in: app) else { return false }

        // Clamp to the first row, then step down once per row: the panel is one focus column.
        for _ in 0 ..< ShellSection.allCases.count {
            XCUIRemote.shared.press(.up)
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
    static func open(_ section: ShellSection, in app: XCUIApplication, settle: TimeInterval = 1.2) -> Bool {
        guard select(section, in: app, settle: settle) else { return false }
        let marker = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", section.markers))
            .firstMatch
        return marker.waitForExistence(timeout: 12)
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
        return element.identifier.isEmpty && frame.minX <= 1 && frame.width > 300 && frame.height < 100
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
