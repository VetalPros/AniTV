import XCTest

/// «Настройки» tab: the two playback switches must exist, flip, and survive a relaunch.
///
/// The switches are read by the player from the same `UserDefaults` domain, so persistence here is what makes
/// the auto-skip tests meaningful — they set the switch the way a viewer would and then play.
final class SettingsUITests: XCTestCase {
    private let screenTimeout: TimeInterval = 30
    private let focusAttempts = 8
    private let settleTimeout: TimeInterval = 0.6
    /// Accessibility identifiers of the tab-bar buttons, in bar order.
    private let tabIdentifiers = ["sparkles.tv", "square.grid.2x2", "person.crop.circle", "gearshape"]

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

    /// Walks focus up into the tab bar and selects «Настройки», the fourth and last tab.
    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let tab = app.descendants(matching: .any).matching(identifier: "gearshape").firstMatch
        for _ in 0 ..< focusAttempts * 3 {
            if isFocused(identifier: "gearshape", in: app) {
                break
            }
            guard let focusedIndex = tabIdentifiers.firstIndex(where: { isFocused(identifier: $0, in: app) }) else {
                XCUIRemote.shared.press(.up)
                Thread.sleep(forTimeInterval: settleTimeout)
                continue
            }
            let target = tabIdentifiers.count - 1
            XCUIRemote.shared.press(target >= focusedIndex ? .right : .left)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        XCTAssertTrue(tab.exists, "The app exposes no «Настройки» tab")
        XCTAssertTrue(isFocused(identifier: "gearshape", in: app), "Focus never reached the «Настройки» tab")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "settings.screen").firstMatch
                .waitForExistence(timeout: screenTimeout),
            "Selecting the settings tab did not open the settings screen"
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

    /// Focuses a toggle (Down walks from the tab bar through the header into the switches) and selects it.
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
