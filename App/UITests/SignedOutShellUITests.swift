import XCTest

/// The header without an account: it must offer the way in, the profile must open on the pairing screen, and
/// Back must return to the shell (ADR 0032).
final class SignedOutShellUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 45

    @MainActor
    func testHeaderOffersSignInAndProfileOpensOnPairing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [UITestLaunchArguments.signedOut]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.rail.latest"].firstMatch.waitForExistence(timeout: loadTimeout),
            "The shell never came up"
        )

        // The header reports the account; a forced signed-out launch must say so, whatever the language is.
        XCTAssertEqual(
            ShellNavigator.accountSignedIn(in: app),
            false,
            "The header did not report a signed-out TV"
        )
        let header = app.descendants(matching: .any)[accountHeaderIdentifier].firstMatch
        XCTAssertFalse(header.label.isEmpty, "The account header exposes no label to read")
        attach(app, named: "shell-signed-out")

        // The header is the way into the profile, and with no account that screen is the pairing handshake.
        XCTAssertTrue(ShellNavigator.openProfile(in: app), "The account header did not open the profile")
        XCTAssertTrue(
            app.descendants(matching: .any)["profile.pairingCode"].firstMatch.waitForExistence(timeout: 30),
            "A signed-out TV opened a profile without a pairing code"
        )
        attach(app, named: "profile-signed-out")

        // Back closes the cover and leaves the shell usable.
        XCTAssertTrue(ShellNavigator.closeProfile(in: app), "Back did not close the profile cover")
        XCTAssertTrue(ShellNavigator.open(.home, in: app), "The shell was not usable after closing the profile")
        XCTAssertTrue(
            app.descendants(matching: .any)["home.rail.latest"].firstMatch.waitForExistence(timeout: loadTimeout),
            "«Главная» did not come back after the profile cover closed"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["home.rail.favorites"].firstMatch.exists,
            "A signed-out viewer got a favourites rail"
        )
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
