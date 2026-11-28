import XCTest

/// Proof that the two content screens keep themselves current without the viewer doing anything.
///
/// The production cadence is minutes long, so the app reads a short interval from a launch argument
/// (`-uiTestingRefreshInterval`) and the test watches a real request happen: the hidden freshness probe is
/// re-stamped while the screen is untouched, and focus is not thrown away by the refresh. The probe exists
/// only under `-uiTestingRefreshProbe` — the caption that used to carry it is no longer in the UI.
final class AutoRefreshUITests: XCTestCase {
    private let screenTimeout: TimeInterval = 60
    private let settleTimeout: TimeInterval = 1.0
    private let focusAttempts = 8
    /// Seconds between the two probe reads: several refresh ticks even for a slow request.
    private let observationWindow: TimeInterval = 10

    /// Short interval so the test sees a genuine refresh; the stale rule is shortened too, so entering a
    /// tab refreshes immediately instead of waiting a minute.
    private var launchArguments: [String] {
        [
            UITestLaunchArguments.refreshInterval, "4",
            UITestLaunchArguments.staleAfter, "1",
            UITestLaunchArguments.refreshProbe,
        ]
    }

    @MainActor
    func testLatestFeedRefreshesItselfWithoutTouchingTheScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = launchArguments
        app.launch()

        let probe = element(identifier: "latest.updatedAt", in: app)
        XCTAssertTrue(probe.waitForExistence(timeout: screenTimeout), "The feed exposes no freshness probe")
        let firstStamp = probe.value as? String
        XCTAssertNotNil(firstStamp, "The freshness probe carries no timestamp")

        // Focus starts on the grid; the refresh must leave it there.
        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: screenTimeout), "The feed shows no poster cards")
        // Right leaves the sidebar, Down walks the rows: alternating covers both starting points.
        for step in 0 ..< focusAttempts * 2 where !isFocused(identifier: "latest.posterCard", in: app) {
            XCUIRemote.shared.press(step.isMultiple(of: 2) ? .right : .down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(isFocused(identifier: "latest.posterCard", in: app), "Focus never reached the poster grid")

        Thread.sleep(forTimeInterval: observationWindow)
        let secondStamp = probe.value as? String
        XCTAssertNotEqual(
            secondStamp,
            firstStamp,
            "The feed did not refresh by itself: the probe stayed at \(secondStamp ?? "nil")"
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

        let probe = element(identifier: "profile.updatedAt", in: app)
        XCTAssertTrue(probe.waitForExistence(timeout: screenTimeout), "The profile exposes no freshness probe")
        let firstStamp = probe.value as? String
        XCTAssertNotNil(firstStamp, "The profile freshness probe carries no timestamp")

        Thread.sleep(forTimeInterval: observationWindow)
        let secondStamp = probe.value as? String
        XCTAssertNotEqual(
            secondStamp,
            firstStamp,
            "The favourites did not refresh by themselves: the probe stayed at \(secondStamp ?? "nil")"
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
            UITestLaunchArguments.refreshProbe,
        ]
        app.launch()

        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: screenTimeout), "The feed never loaded")
        openProfileTab(in: app)

        let pairingCode = element(identifier: "profile.pairingCode", in: app)
        if pairingCode.waitForExistence(timeout: 15) {
            throw XCTSkip("The stored session is gone; the signed-out profile screen is asserted instead")
        }

        let probe = element(identifier: "profile.updatedAt", in: app)
        XCTAssertTrue(probe.waitForExistence(timeout: screenTimeout), "The profile exposes no freshness probe")
        let beforeLeaving = probe.value as? String
        XCTAssertNotNil(beforeLeaving, "The profile freshness probe carries no timestamp")

        // Leave for another section and come straight back — a couple of seconds, far less than the
        // interval. The profile is a cover since ADR 0032, so leaving it means closing it first.
        XCTAssertTrue(ShellNavigator.closeProfile(in: app), "The profile cover did not close")
        openLatestTab(in: app)
        Thread.sleep(forTimeInterval: 1)
        openProfileTab(in: app)

        var afterReturn: String? = beforeLeaving
        for _ in 0 ..< 10 where afterReturn == beforeLeaving {
            Thread.sleep(forTimeInterval: 1)
            afterReturn = probe.value as? String
        }
        XCTAssertNotEqual(
            afterReturn,
            beforeLeaving,
            "Coming back to the tab did not re-read the favourites: the probe stayed at \(afterReturn ?? "nil")"
        )
    }

    // MARK: Steps

    /// Walks focus into the sidebar and opens «Главная» (ADR 0028: there is no tab bar any more).
    @MainActor
    private func openLatestTab(in app: XCUIApplication) {
        XCTAssertTrue(ShellNavigator.open(.home, in: app), "The sidebar never reached «Главная»")
    }

    /// Walks focus into the sidebar and opens «Профиль».
    @MainActor
    private func openProfileTab(in app: XCUIApplication) {
        XCTAssertTrue(ShellNavigator.openProfile(in: app), "The account header never opened «Профиль»")
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
