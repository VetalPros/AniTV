import XCTest

/// The routing promises of ADR 0028 that no screenshot can show: a section keeps its navigation path and
/// its focus position across switches, and Back stays inside the section it was pressed in.
final class NavigationStateUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 45
    private let settle: TimeInterval = 1.2

    /// Opening a release and then leaving the section must not close the release behind your back.
    @MainActor
    func testPushedDetailSurvivesASectionSwitch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(ShellNavigator.open(.home, in: app), "«Главная» never opened")
        XCTAssertTrue(ShellNavigator.focus("latest.posterCard", in: app), "Focus never reached a poster")
        XCUIRemote.shared.press(.select)

        let detail = app.descendants(matching: .any)["detail.screen"].firstMatch
        XCTAssertTrue(
            detail.waitForExistence(timeout: loadTimeout),
            "Selecting a poster did not open the detail screen"
        )

        XCTAssertTrue(ShellNavigator.open(.settings, in: app), "«Настройки» never opened")
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.screen"].firstMatch.exists,
            "The settings section is not on display"
        )

        // Coming back must land on the pushed detail, not on the grid, so this only selects the row.
        XCTAssertTrue(ShellNavigator.select(.home, in: app), "«Главная» never came back")
        XCTAssertTrue(
            detail.waitForExistence(timeout: 10),
            "Returning to «Главная» lost the pushed release: the section rebuilt its navigation path"
        )
    }

    /// **Known limitation, encoded as an expected failure.** `TabView` unloads the content of a section
    /// that is not selected, so the grid comes back at the top and refetches — measured 2026-11-27: the
    /// freshness caption moved from 13:38:35 to 13:38:56 across one switch. The navigation *path* survives
    /// (it lives in `ShellNavigationState`), focus and scroll do not. Restoring them needs the external
    /// `FocusState` plumbing the episode grid already uses; see `docs/NAVIGATION.md` §7.
    @MainActor
    func testGridFocusIsNotPreservedBecauseTheSectionIsUnloaded() {
        XCTExpectFailure(
            "tvOS unloads an unselected section: focus and scroll restart at the top (docs/NAVIGATION.md §7)"
        )
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // A grid screen, not «Главная»: the home screen is rails since ADR 0031, and a rail does not have
        // the "two rows down" the measurement needs.
        XCTAssertTrue(ShellNavigator.open(.catalog, in: app), "«Каталог» never opened")
        XCTAssertTrue(ShellNavigator.focus("latest.posterCard", in: app), "Focus never reached a poster")

        // Move away from the default first card so "reset to the top" is distinguishable from "kept".
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settle)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settle)
        let before = focusedPosterLabel(in: app)
        XCTAssertNotNil(before, "Two Down presses left no poster focused")
        let stampBefore = app.descendants(matching: .any)["latest.updatedAt"].firstMatch.value as? String

        XCTAssertTrue(ShellNavigator.open(.settings, in: app), "«Настройки» never opened")
        XCTAssertTrue(ShellNavigator.open(.catalog, in: app), "«Каталог» never came back")

        let after = focusedPosterLabel(in: app)
        let stampAfter = app.descendants(matching: .any)["latest.updatedAt"].firstMatch.value as? String
        XCTAssertEqual(
            after,
            before,
            "The grid came back on a different card («\(before ?? "nil")» → «\(after ?? "nil")»), freshness caption \(stampBefore ?? "nil") → \(stampAfter ?? "nil")"
        )
    }

    /// Back pops the section's own stack and must not change the selected section underneath it.
    @MainActor
    func testBackPopsTheSectionStackWithoutChangingSection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(ShellNavigator.open(.home, in: app), "«Главная» never opened")
        XCTAssertTrue(ShellNavigator.focus("latest.posterCard", in: app), "Focus never reached a poster")
        XCUIRemote.shared.press(.select)

        let detail = app.descendants(matching: .any)["detail.screen"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: loadTimeout), "The detail screen never opened")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            app.descendants(matching: .any)["latest.posterCard"].firstMatch.waitForExistence(timeout: 15),
            "Back did not pop the detail screen back to the feed"
        )

        // A second Back at the section root: tvOS may hand the screen to the system, which is a valid
        // outcome, so only assert what must not happen — silently ending up in another section.
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: settle)
        if app.state == .runningForeground {
            XCTAssertFalse(
                app.descendants(matching: .any)["settings.screen"].firstMatch.exists,
                "Back at the «Главная» root switched to another section"
            )
        } else {
            // The system took the screen back to the Home screen; bring the app forward again.
            app.activate()
            XCTAssertTrue(
                app.descendants(matching: .any)["latest.posterCard"].firstMatch.waitForExistence(timeout: 20),
                "The app did not come back to the shell"
            )
        }
    }

    @MainActor
    private func focusedPosterLabel(in app: XCUIApplication) -> String? {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1"))
            .firstMatch
        guard element.exists, element.identifier == "latest.posterCard" else { return nil }
        return element.label
    }
}
