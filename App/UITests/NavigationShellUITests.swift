import XCTest

/// Proves the two behaviours ADR 0028 leans on and that no screenshot could show — they need input:
/// focus leaves the sidebar for the content (the panel collapses), and Left from the first poster
/// column brings it back to the sidebar instead of getting lost.
///
/// The app's first launch parks focus in the sidebar; this test walks out of that state and back.
final class NavigationShellUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 45
    private let focusTimeout: TimeInterval = 8

    @MainActor
    func testFocusLeavesTheSidebarAndComesBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The feed exposed no poster card within \(feedTimeout)s, so focus cannot be checked"
        )

        // Focus may start in the sidebar (the reference starts in content). Whatever the engine picked,
        // a directional press must land it in the posters — a panel that refuses to give focus up is the
        // failure this test exists for.
        var leftTheSidebar = false
        for direction in [XCUIRemote.Button.right, .right, .down, .right] {
            XCUIRemote.shared.press(direction)
            if waitForFocus(in: app, on: "latest.posterCard") {
                leftTheSidebar = true
                break
            }
        }
        XCTAssertTrue(leftTheSidebar, "Directional presses never moved focus out of the sidebar")
        keepScreenshot(of: app, named: "shell-content-focused")

        // Left from the leftmost poster column must return to the sidebar, not stay in the grid.
        XCUIRemote.shared.press(.left)
        XCTAssertFalse(
            waitForFocus(in: app, on: "latest.posterCard", timeout: 3),
            "Left from the first poster column kept focus in the content"
        )
        keepScreenshot(of: app, named: "shell-sidebar-focused")
    }

    @MainActor
    private func focusIsOn(in app: XCUIApplication, identifier: String) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", identifier))
            .firstMatch.exists
    }

    @MainActor
    private func waitForFocus(in app: XCUIApplication, on identifier: String, timeout: TimeInterval? = nil) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? focusTimeout)
        while Date() < deadline {
            if focusIsOn(in: app, identifier: identifier) {
                return true
            }
            usleep(200_000)
        }
        return false
    }

    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
