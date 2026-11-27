import XCTest

/// «Настройки» tab: the two playback switches must exist, flip, and survive a relaunch.
///
/// The switches are read by the player from the same `UserDefaults` domain, so persistence here is what makes
/// the auto-skip tests meaningful — they set the switch the way a viewer would and then play.
final class SettingsUITests: XCTestCase {
    private let screenTimeout: TimeInterval = 30
    private let focusAttempts = 8
    private let settleTimeout: TimeInterval = 0.6

    @MainActor
    func testSwitchesExistFlipAndSurviveRelaunch() {
        continueAfterFailure = false
        let app = launch(reset: true)
        openSettings(in: app)

        let openings = app.descendants(matching: .any).matching(identifier: "settings.openings").firstMatch
        let endings = app.descendants(matching: .any).matching(identifier: "settings.endings").firstMatch
        XCTAssertTrue(openings.waitForExistence(timeout: screenTimeout), "No opening switch in the settings tab")
        XCTAssertTrue(endings.exists, "No ending switch in the settings tab")
        attach(app, named: "settings-screen")

        // Both start off; flipping one must stick after the app is gone.
        XCTAssertFalse(isOn(openings), "The opening switch should start off")
        XCTAssertFalse(isOn(endings), "The ending switch should start off")
        XCTAssertTrue(flip(openings, in: app), "The opening switch never took focus")
        XCTAssertTrue(isOn(openings), "The opening switch did not turn on")
        attach(app, named: "settings-openings-on")

        app.terminate()
        let relaunched = launch(reset: false)
        openSettings(in: relaunched)
        let persisted = relaunched.descendants(matching: .any)
            .matching(identifier: "settings.openings").firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: screenTimeout), "The settings tab lost its switches")
        XCTAssertTrue(isOn(persisted), "The opening switch did not survive a relaunch")

        // Leave the app as it was found: the player tests assume both switches are off.
        XCTAssertTrue(flip(persisted, in: relaunched), "The opening switch never took focus after relaunch")
        XCTAssertFalse(isOn(persisted), "The opening switch did not turn back off")
    }

    // MARK: Steps

    /// Launches the app; `reset` restores the shipped defaults, which is exactly what a persistence check must
    /// not do on the second launch.
    @MainActor
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = reset ? [UITestLaunchArguments.resetSettings] : []
        app.launch()
        return app
    }

    /// Walks focus into the sidebar and opens «Настройки» (ADR 0028: the panel replaced the tab bar).
    @MainActor
    private func openSettings(in app: XCUIApplication) {
        XCTAssertTrue(ShellNavigator.open(.settings, in: app), "The sidebar never reached «Настройки»")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "settings.screen").firstMatch
                .waitForExistence(timeout: screenTimeout),
            "Selecting the settings row did not open the settings screen"
        )
    }

    @MainActor
    private func isFocused(identifier: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", identifier))
            .firstMatch.exists
    }

    /// Whether a tvOS toggle reads as on, from its accessibility value.
    @MainActor
    private func isOn(_ toggle: XCUIElement) -> Bool {
        let value = (toggle.value as? String) ?? ""
        return value == "1" || value.localizedCaseInsensitiveContains("on")
            || value.localizedCaseInsensitiveContains("вкл")
    }

    /// Focuses a toggle (Down walks from the sidebar through the header into the switches) and selects it.
    @MainActor
    private func flip(_ element: XCUIElement, in _: XCUIApplication) -> Bool {
        for _ in 0 ..< focusAttempts * 2 {
            if element.hasFocus {
                XCUIRemote.shared.press(.select)
                Thread.sleep(forTimeInterval: settleTimeout)
                return true
            }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        return false
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
