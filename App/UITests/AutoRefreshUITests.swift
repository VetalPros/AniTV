import XCTest

/// Proof that the two content screens keep themselves current without the viewer doing anything.
///
/// The production cadence is minutes long, so the app reads a short interval from a launch argument
/// (`-uiTestingRefreshInterval`) and the test watches a real request happen: the «Обновлено» caption is
/// re-stamped while the screen is untouched, and focus is not thrown away by the refresh.
final class AutoRefreshUITests: XCTestCase {
    private let screenTimeout: TimeInterval = 60
    private let settleTimeout: TimeInterval = 1.0
    private let focusAttempts = 8
    /// Seconds between the two caption reads: several refresh ticks even for a slow request.
    private let observationWindow: TimeInterval = 10

    /// Short interval so the test sees a genuine refresh; the stale rule is shortened too, so entering a
    /// tab refreshes immediately instead of waiting a minute.
    private var launchArguments: [String] {
        [UITestLaunchArguments.refreshInterval, "4", UITestLaunchArguments.staleAfter, "1"]
    }

    @MainActor
    func testLatestFeedRefreshesItselfWithoutTouchingTheScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()

        let caption = element(identifier: "latest.updatedAt", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: screenTimeout), "The feed shows no freshness caption")
        let firstStamp = caption.value as? String
        XCTAssertNotNil(firstStamp, "The freshness caption exposes no timestamp")

        // Focus starts on the grid; the refresh must leave it there.
        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: screenTimeout), "The feed shows no poster cards")
        for _ in 0 ..< focusAttempts where !isFocused(identifier: "latest.posterCard", in: app) {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(isFocused(identifier: "latest.posterCard", in: app), "Focus never reached the poster grid")

        Thread.sleep(forTimeInterval: observationWindow)
        let secondStamp = caption.value as? String
        XCTAssertNotEqual(
            secondStamp,
            firstStamp,
            "The feed did not refresh by itself: the caption stayed at \(secondStamp ?? "nil")"
        )
        XCTAssertTrue(cards.firstMatch.exists, "The grid disappeared during the refresh")
        XCTAssertTrue(
            isFocused(identifier: "latest.posterCard", in: app),
            "The background refresh threw focus out of the grid"
        )
    }

    @MainActor
    func testFavoritesRefreshThemselvesOnTheProfileTab() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()

        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: screenTimeout), "The feed never loaded")
        openProfileTab(in: app)

        // The simulator's Keychain holds a real session today; if it does not, the signed-out surface is
        // what this run can observe and the refresh test is reported as skipped.
        let pairingCode = element(identifier: "profile.pairingCode", in: app)
        if pairingCode.waitForExistence(timeout: 15) {
            XCTAssertFalse(pairingCode.label.isEmpty, "The pairing screen shows no code")
            throw XCTSkip("The stored session is gone; the signed-out profile screen is asserted instead")
        }

        let caption = element(identifier: "profile.updatedAt", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: screenTimeout), "The profile shows no freshness caption")
        let firstStamp = caption.value as? String
        XCTAssertNotNil(firstStamp, "The profile freshness caption exposes no timestamp")

        Thread.sleep(forTimeInterval: observationWindow)
        let secondStamp = caption.value as? String
        XCTAssertNotEqual(
            secondStamp,
            firstStamp,
            "The favourites did not refresh by themselves: the caption stayed at \(secondStamp ?? "nil")"
        )
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).exists == false,
            "The refresh navigated somewhere unexpected"
        )
    }

    /// The regression the owner reported: a title favourited elsewhere never showed up, because leaving
    /// the tab after the first load cancelled the refresh loop for good and coming back within the minute
    /// did not count as "away". Coming back to the tab must re-read the favourites.
    @MainActor
    func testReturningToTheProfileTabRefreshesTheFavourites() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A staleness window long enough that it can never fire inside the test: what is measured here is
        // the timer surviving the initial load, not the "away" rule.
        app.launchArguments = [
            UITestLaunchArguments.refreshInterval, "4",
            UITestLaunchArguments.staleAfter, "3600",
        ]
        app.launch()

        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: screenTimeout), "The feed never loaded")
        openProfileTab(in: app)

        let pairingCode = element(identifier: "profile.pairingCode", in: app)
        if pairingCode.waitForExistence(timeout: 15) {
            throw XCTSkip("The stored session is gone; the signed-out profile screen is asserted instead")
        }

        let caption = element(identifier: "profile.updatedAt", in: app)
        XCTAssertTrue(caption.waitForExistence(timeout: screenTimeout), "The profile shows no freshness caption")
        let beforeLeaving = caption.value as? String
        XCTAssertNotNil(beforeLeaving, "The profile freshness caption exposes no timestamp")

        // Leave for another tab and come straight back — a couple of seconds, far less than the interval.
        openLatestTab(in: app)
        Thread.sleep(forTimeInterval: 1)
        openProfileTab(in: app)

        var afterReturn: String? = beforeLeaving
        for _ in 0 ..< 10 where afterReturn == beforeLeaving {
            Thread.sleep(forTimeInterval: 1)
            afterReturn = caption.value as? String
        }
        XCTAssertNotEqual(
            afterReturn,
            beforeLeaving,
            "Coming back to the tab did not re-read the favourites: the caption stayed at \(afterReturn ?? "nil")"
        )
    }

    // MARK: Steps

    /// Walks focus up into the tab bar and selects the «Новинки» tab.
    @MainActor
    private func openLatestTab(in app: XCUIApplication) {
        selectTab(identifier: "sparkles.tv", arrow: .left, in: app)
    }

    /// Focuses a tab bar item by pressing the given arrow while focus is in the bar.
    @MainActor
    private func selectTab(identifier: String, arrow: XCUIRemote.Button, in app: XCUIApplication) {
        let tabIdentifiers = ["sparkles.tv", "square.grid.2x2", "person.crop.circle"]
        for _ in 0 ..< focusAttempts * 2 {
            if isFocused(identifier: identifier, in: app) {
                break
            }
            let onTabBar = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == 1 AND identifier IN %@", tabIdentifiers))
                .firstMatch.exists
            XCUIRemote.shared.press(onTabBar ? arrow : .up)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(isFocused(identifier: identifier, in: app), "Focus never reached the \(identifier) tab")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: settleTimeout)
    }

    /// Walks focus up into the tab bar and selects the «Профиль» tab.
    @MainActor
    private func openProfileTab(in app: XCUIApplication) {
        let tabIdentifiers = ["sparkles.tv", "square.grid.2x2", "person.crop.circle"]
        for _ in 0 ..< focusAttempts * 2 {
            if isFocused(identifier: "person.crop.circle", in: app) {
                break
            }
            let onTabBar = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == 1 AND identifier IN %@", tabIdentifiers))
                .firstMatch.exists
            XCUIRemote.shared.press(onTabBar ? .right : .up)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(isFocused(identifier: "person.crop.circle", in: app), "Focus never reached the «Профиль» tab")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: settleTimeout)
    }

    // MARK: Queries

    @MainActor
    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func isFocused(identifier: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", identifier))
            .firstMatch.exists
    }
}
