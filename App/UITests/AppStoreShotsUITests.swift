import XCTest

/// Captures the App Store screenshots of tvOS (1920×1080) in one pass, so the set can be refreshed by
/// running one command instead of cropping images by hand. The images are the deliverable; the assertions
/// only make sure each screen is really on display before it is captured.
///
/// `scripts/capture-appstore-screenshots.sh` runs this test and copies the attachments into
/// `docs/appstore/screenshots/`.
final class AppStoreShotsUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 60

    @MainActor
    func testCaptureStoreScreenshots() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.rail.latest"].firstMatch.waitForExistence(timeout: loadTimeout),
            "The «Новинки» rail never appeared"
        )
        // Give the second rail (favourites) time to arrive so the shot shows both.
        _ = app.descendants(matching: .any)["home.rail.favorites"].firstMatch.waitForExistence(timeout: 15)
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, named: "01-home")

        XCTAssertTrue(ShellNavigator.open(.search, in: app), "«Поиск» never opened")
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "02-search")

        XCTAssertTrue(ShellNavigator.open(.catalog, in: app), "«Каталог» never opened")
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "03-catalog")

        XCTAssertTrue(ShellNavigator.open(.home, in: app), "«Главная» never came back")
        XCTAssertTrue(ShellNavigator.focus("latest.posterCard", in: app), "Focus never reached a poster")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.descendants(matching: .any)["detail.screen"].firstMatch.waitForExistence(timeout: 30),
            "The release screen never opened"
        )
        Thread.sleep(forTimeInterval: 3)
        attach(app, named: "04-detail")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(ShellNavigator.open(.settings, in: app), "«Настройки» never opened")
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "05-settings")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
