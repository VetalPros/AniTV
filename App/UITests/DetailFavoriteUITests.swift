import XCTest

/// Proof of the favourite heart on the release detail screen, on a TV that is **not** paired.
///
/// The signed-in path (real favourites, optimistic toggle, rollback) needs an account confirming a
/// pairing code, so it stays unverified — see the task report. What is checked here needs no account:
/// the heart exists, the remote reaches it from the hero actions and back, it never takes the default
/// focus, and pressing it without a session explains how to pair instead of calling the API or opening
/// the player.
final class DetailFavoriteUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    private let focusAttempts = 6
    private let settleTimeout: TimeInterval = 1.0

    @MainActor
    func testFavoriteHeartIsReachableAndExplainsSignOut() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A deterministic signed-out session: the signed-in path is reported as unverified.
        app.launchArguments = [UITestLaunchArguments.signedOut]
        app.launch()
        openFirstRelease(in: app)

        // The heart exists and is not the control the screen opens on (ADR 0012 keeps resume/play).
        let heart = element(identifier: "detail.favoriteButton", in: app)
        XCTAssertTrue(heart.waitForExistence(timeout: screenTimeout), "The detail screen shows no favourite heart")
        XCTAssertFalse(
            isFocused(identifier: "detail.favoriteButton", in: app),
            "The heart took the default focus, which belongs to «Продолжить»/«Смотреть»"
        )

        // Right walks from the hero action to the heart, Left walks back.
        XCTAssertTrue(focus(heart, in: app, pressing: .right), "The heart cannot be reached from the hero actions")
        attach(app, named: "detail-favorite-focused")
        XCUIRemote.shared.press(.left)
        Thread.sleep(forTimeInterval: settleTimeout)
        let heroActions = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "hasFocus == 1 AND identifier IN %@",
                ["detail.playButton", "detail.resumeButton"]
            )
        )
        XCTAssertTrue(heroActions.firstMatch.exists, "Left from the heart did not return to the hero actions")

        // Without a session the press explains how to pair; it must not call the API or start playback.
        XCTAssertTrue(focus(heart, in: app, pressing: .right), "The heart lost focus on the way back")
        XCUIRemote.shared.press(.select)
        let message = element(identifier: "detail.favoriteMessage", in: app)
        XCTAssertTrue(
            message.waitForExistence(timeout: screenTimeout),
            "Pressing the heart without a session showed no hint"
        )
        XCTAssertFalse(
            element(identifier: "player.screen", in: app).exists,
            "Pressing the heart started playback"
        )
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).exists,
            "Pressing the heart left the detail screen"
        )
        attach(app, named: "detail-favorite-signed-out")
    }

    // MARK: Steps

    /// Opens the first poster of the feed and waits for its detail screen to take focus.
    @MainActor
    private func openFirstRelease(in app: XCUIApplication) {
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card"
        )
        XCTAssertTrue(
            ShellNavigator.focus("latest.posterCard", in: app),
            "Focus never reached a poster card"
        )

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).waitForExistence(timeout: screenTimeout),
            "The poster card did not open the detail screen"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "hasFocus == 1 AND identifier IN %@",
                    ["detail.playButton", "detail.resumeButton", "detail.synopsisToggle"]
                )
            ).firstMatch.waitForExistence(timeout: screenTimeout),
            "The detail screen never took focus"
        )
    }

    /// Presses `button` until `target` holds focus.
    @MainActor
    private func focus(_ target: XCUIElement, in app: XCUIApplication, pressing button: XCUIRemote.Button) -> Bool {
        for _ in 0 ..< focusAttempts {
            if isFocused(identifier: target.identifier, in: app) {
                return true
            }
            XCUIRemote.shared.press(button)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        return isFocused(identifier: target.identifier, in: app)
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
