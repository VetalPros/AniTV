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
}
