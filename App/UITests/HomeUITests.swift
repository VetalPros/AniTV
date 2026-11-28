import XCTest

/// Proves the shape of «Главная»: a rail of fresh releases, and a favourites rail that exists only for a
/// signed-in viewer (ADR 0031).
final class HomeUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 60

    @MainActor
    func testLatestRailShowsReleaseCards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let rail = app.descendants(matching: .any)["home.rail.latest"].firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: loadTimeout), "The «Новинки» rail never appeared")

        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: loadTimeout), "The «Новинки» rail shows no cards")
        XCTAssertGreaterThan(cards.count, 1, "A rail should offer more than one release to walk through")
    }

    /// The freshness caption is gone from the UI, and the hidden probe that replaced it exists only under the
    /// UI-test launch argument — a production launch must not carry the element at all.
    @MainActor
    func testFreshnessProbeIsAbsentWithoutTheLaunchArgument() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.rail.latest"].firstMatch.waitForExistence(timeout: loadTimeout),
            "The «Новинки» rail never appeared"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["latest.updatedAt"].firstMatch.exists,
            "A production launch exposed the hidden freshness probe"
        )
    }

    /// The favourites rail is whatever the account is: present with cards when signed in, absent when not.
    ///
    /// The account state comes from the panel header, which is the only place that knows it (ADR 0032);
    /// travelling through the profile cover to learn it would make this test depend on the cover too.
    @MainActor
    func testFavouritesRailFollowsTheAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.rail.latest"].firstMatch.waitForExistence(timeout: loadTimeout),
            "The «Новинки» rail never appeared"
        )
        guard let signedIn = ShellNavigator.accountSignedIn(in: app) else {
            XCTFail("The account header never reported whether this TV is paired")
            return
        }
        XCTAssertTrue(ShellNavigator.open(.home, in: app), "«Главная» was not reachable after reading the header")

        let favouritesRail = app.descendants(matching: .any)["home.rail.favorites"].firstMatch
        if signedIn {
            XCTAssertTrue(
                favouritesRail.waitForExistence(timeout: loadTimeout),
                "A signed-in viewer got no «Обновления в избранном» rail"
            )
            let cards = app.descendants(matching: .any).matching(identifier: "home.favoriteCard")
            XCTAssertTrue(cards.firstMatch.exists, "The favourites rail is on screen but empty")
            attach(app, named: "home-signed-in")
        } else {
            XCTAssertFalse(favouritesRail.exists, "A signed-out viewer got a favourites rail")
        }
    }

    @MainActor
    func testFavouritesRailIsAbsentWhenSignedOut() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [UITestLaunchArguments.signedOut]
        app.launch()

        // The fresh rail has to be there, otherwise the assertion below would pass for the wrong reason.
        XCTAssertTrue(
            app.descendants(matching: .any)["home.rail.latest"].firstMatch.waitForExistence(timeout: loadTimeout),
            "The «Новинки» rail never appeared, so the missing favourites rail proves nothing"
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
