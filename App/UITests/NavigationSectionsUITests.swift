import XCTest

/// Captures every sidebar section in the state the redesign has to look right in, so the content
/// adaptation of P2 can be judged from images instead of guesses.
///
/// It asserts the cheap things — each screen is on display — and attaches a screenshot per section; the
/// screenshots are the deliverable, not a pixel comparison.
final class NavigationSectionsUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 30

    @MainActor
    func testEverySectionRendersItsOwnScreen() {
        let sections: [(name: String, markers: [String])] = [
            ("home", ["latest.posterCard"]),
            ("search", ["catalog.searchField"]),
            ("catalog", ["catalog.genreChip"]),
            // Signed out the profile shows the pairing code; signed in it offers «Сменить аккаунт».
            ("profile", ["profile.pairingCode", "profile.reconnect"]),
            ("settings", ["settings.screen"]),
        ]

        for section in sections {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchArguments = UITestLaunchArguments.opening(section: section.name)
            app.launch()

            let marker = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier IN %@", section.markers))
                .firstMatch
            XCTAssertTrue(
                marker.waitForExistence(timeout: loadTimeout),
                "«\(section.name)» never showed any of \(section.markers): \(app.debugDescription)"
            )
            keepScreenshot(of: app, named: "section-\(section.name)-expanded")

            // One directional press takes focus out of the panel, which collapses it: this is the state
            // the viewer actually reads the screen in, so both are captured.
            XCUIRemote.shared.press(.right)
            usleep(1_500_000)
            keepScreenshot(of: app, named: "section-\(section.name)-collapsed")
            app.terminate()
        }
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
