import XCTest

/// «Настройки» tab: the two playback switches must exist, flip, and survive a relaunch; the poster size must
/// reach «Главная» and survive a relaunch too.
///
/// The switches are read by the player from the same `UserDefaults` domain, so persistence here is what makes
/// the auto-skip tests meaningful — they set the switch the way a viewer would and then play.
final class SettingsUITests: XCTestCase {
    private let screenTimeout: TimeInterval = 30
    private let feedTimeout: TimeInterval = 60
    private let focusAttempts = 8
    private let settleTimeout: TimeInterval = 0.6

    /// Every poster size the settings offer, in the order they are laid out.
    private let posterPercents = [100, 110, 120, 130, 140, 150]

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

    /// Choosing a poster size must reach «Главная» with the geometry the scale promises (130 % is a 317 pt
    /// tile, interpolated between the pinned 244 and 366 pt edges) and survive a relaunch.
    @MainActor
    func testPosterScaleAppliesToHomeAndSurvivesRelaunch() {
        continueAfterFailure = false
        let app = launch(reset: true)
        openSettings(in: app)

        for percent in posterPercents {
            XCTAssertTrue(
                chip(percent, in: app).waitForExistence(timeout: screenTimeout),
                "The settings offer no \(percent) % poster size"
            )
        }
        XCTAssertTrue(chip(150, in: app).isSelected, "A fresh install should show 150 % as the current size")
        attach(app, named: "settings-poster-scale")

        XCTAssertTrue(selectPosterScale(130, in: app), "The remote never reached the 130 % option")
        XCTAssertTrue(chip(130, in: app).isSelected, "The 130 % option did not become the current size")
        attach(app, named: "settings-poster-scale-130")

        // The setting must reach «Главная»: 130 % is a 317 pt tile.
        XCTAssertTrue(
            ShellNavigator.open(.home, in: app),
            "«Главная» was not reachable after changing the poster size"
        )
        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: feedTimeout), "The «Новинки» rail never appeared")
        // Park focus in the panel first: a focused card draws at ×1.04, which is a different frame.
        XCTAssertTrue(ShellNavigator.enterPanel(in: app), "Focus never left the rail")
        Thread.sleep(forTimeInterval: settleTimeout)
        assertCardPitch(cards, isCloseTo: 317)
        attach(app, named: "home-poster-scale-130")

        app.terminate()
        let relaunched = launch(reset: false)
        openSettings(in: relaunched)
        let stored = chip(130, in: relaunched)
        XCTAssertTrue(stored.waitForExistence(timeout: screenTimeout), "The settings lost the poster size options")
        XCTAssertTrue(stored.isSelected, "130 % did not survive a relaunch")

        // Leave the app as it was found: the other home tests assume the shipped 150 %.
        XCTAssertTrue(selectPosterScale(150, in: relaunched), "The remote never reached the 150 % option")
        XCTAssertTrue(chip(150, in: relaunched).isSelected, "150 % did not come back")
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

    // MARK: Poster size steps

    @MainActor
    private func chip(_ percent: Int, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "settings.posterScale.\(percent)").firstMatch
    }

    /// Focuses the chip for `percent` and selects it.
    ///
    /// The chips are the last row on the screen: Down walks from the two switches into the row, then Left or
    /// Right reaches the wanted step, chosen by comparing the focused chip's frame with the target's. The
    /// focus engine lands on whichever chip is under the switch above, not necessarily the first one.
    @MainActor
    private func selectPosterScale(_ percent: Int, in app: XCUIApplication) -> Bool {
        let target = chip(percent, in: app)
        guard target.waitForExistence(timeout: screenTimeout) else { return false }

        // Leave the panel if focus is still on the sidebar row; on the switches this does nothing.
        XCUIRemote.shared.press(.right)
        Thread.sleep(forTimeInterval: settleTimeout)

        for _ in 0 ..< 8 where !anyChipIsFocused(in: app) {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        for _ in 0 ..< 12 {
            if target.hasFocus {
                break
            }
            let focused = focusedElement(in: app)
            guard focused.exists, anyChipIsFocused(in: app) else { return false }
            XCUIRemote.shared.press(focused.frame.midX <= target.frame.midX ? .right : .left)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        guard target.hasFocus else { return false }
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: settleTimeout)
        return true
    }

    @MainActor
    private func anyChipIsFocused(in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier BEGINSWITH 'settings.posterScale.'"))
            .firstMatch.exists
    }

    @MainActor
    private func focusedElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == 1")).firstMatch
    }

    /// Asserts the rail's card pitch: the tile width plus the 28 pt rail gap, which is what the scale
    /// actually controls.
    ///
    /// A card's accessibility frame is not the tile's layout width: this runtime inflates it by the focus
    /// chrome's 1.05 (measured 100 % 244 → 256, 130 % 317 → 333, 150 % 366 → 384.5) and a focused card adds
    /// its own ×1.04 on top. The distance between two cards is unaffected by either, so 130 % is asserted as
    /// a 345 pt pitch. Both numbers are reported when it fails.
    @MainActor
    private func assertCardPitch(
        _ cards: XCUIElementQuery,
        isCloseTo width: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard cards.count > 1 else {
            XCTFail("The rail has fewer than two cards, so its pitch cannot be measured", file: file, line: line)
            return
        }
        let first = cards.element(boundBy: 0).frame
        let second = cards.element(boundBy: 1).frame
        let pitch = second.minX - first.minX
        XCTAssertEqual(
            pitch,
            width + 28,
            accuracy: 1,
            "The rail pitch measured \(pitch) pt (card reported \(first.width) pt wide);"
                + " \(width) pt tiles plus the 28 pt gap were expected",
            file: file,
            line: line
        )
    }
}
