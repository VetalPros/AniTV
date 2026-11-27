import XCTest

/// End-to-end proof of the «Профиль» tab's signed-out half: it asks the live service for a pairing code,
/// shows it, counts it down and replaces it on demand.
///
/// The signed-in half (profile, favourites, sign-out) cannot be reached without an account confirming
/// the code, so it stays out of this file — see the task report for that gap.
final class ProfileUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 40
    private let focusAttempts = 6
    private let settleTimeout: TimeInterval = 1.0
    // Accessibility identifiers of the three tab-bar buttons.

    @MainActor
    func testProfileTabShowsLivePairingCodeAndRefreshesIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The simulator's Keychain may hold a real session; the pairing screen is asserted on a
        // deliberately signed-out process (see AuthTokenStoreFactory).
        app.launchArguments = [UITestLaunchArguments.signedOut]
        app.launch()

        // The app is up once the feed has cards; tabs are reached from the content with Up.
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card"
        )
        openProfileTab(in: app)

        // The code comes from the service, so it is a six-digit number.
        let code = element(identifier: "profile.pairingCode", in: app)
        XCTAssertTrue(
            code.waitForExistence(timeout: screenTimeout),
            "The profile tab never showed a pairing code"
        )
        // The service hands out numeric codes shorter than six digits: leading zeros are dropped, and
        // three-digit codes have been observed in the app's own log ("Pairing code requested: 766"),
        // so "exactly six" would be a false assumption.
        let firstCode = code.label
        XCTAssertTrue(
            (1 ... 6).contains(firstCode.count),
            "The pairing code is not one to six digits long: «\(firstCode)»"
        )
        XCTAssertTrue(
            firstCode.allSatisfy(\.isNumber),
            "The pairing code is not numeric: «\(firstCode)»"
        )
        attach(app, named: "profile-pairing")

        // The countdown runs: the same element reports a different value a few seconds later.
        let countdown = element(identifier: "profile.pairingCountdown", in: app)
        XCTAssertTrue(countdown.waitForExistence(timeout: screenTimeout), "The pairing screen shows no countdown")
        let before = countdown.label
        Thread.sleep(forTimeInterval: 4)
        let after = countdown.label
        XCTAssertNotEqual(before, after, "The pairing countdown is frozen at «\(before)»")

        // «Обновить код» replaces the code with a fresh one from the service.
        XCTAssertTrue(
            focusRefreshButton(in: app),
            "«Обновить код» cannot be focused with the remote"
        )
        XCUIRemote.shared.press(.select)
        var refreshed = ""
        for _ in 0 ..< 20 {
            Thread.sleep(forTimeInterval: 1.5)
            refreshed = code.label
            if refreshed != firstCode, refreshed.allSatisfy(\.isNumber), !refreshed.isEmpty {
                break
            }
        }
        XCTAssertNotEqual(refreshed, firstCode, "«Обновить код» did not replace the pairing code")
    }

    // MARK: Steps

    /// Walks focus into the sidebar and opens «Профиль» (ADR 0028: the panel replaced the tab bar).
    @MainActor
    private func openProfileTab(in app: XCUIApplication) {
        XCTAssertTrue(ShellNavigator.openProfile(in: app), "The account header never opened «Профиль»")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "profile.pairingCode").firstMatch
                .waitForExistence(timeout: settleTimeout),
            "Opening «Профиль» never showed the pairing screen"
        )
    }

    /// Moves focus onto the refresh button on the pairing screen.
    @MainActor
    private func focusRefreshButton(in app: XCUIApplication) -> Bool {
        for _ in 0 ..< focusAttempts {
            if isFocused(identifier: "profile.refreshCode", in: app) {
                return true
            }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        return isFocused(identifier: "profile.refreshCode", in: app)
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

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
