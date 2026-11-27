import XCTest

/// The player's single skip hint: it holds focus, it acts on Select, it expires by itself, and the two
/// settings switch it off for good.
///
/// The hint lives inside `AVPlayerViewController.contentOverlayView` as one UIKit button, because that is the
/// only shape that takes focus with the remote.
final class PlayerSkipUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    private let hintTimeout: TimeInterval = 25
    private let focusAttempts = 10
    private let settleTimeout: TimeInterval = 0.8

    // MARK: Hint with focus

    @MainActor
    func testHintHoldsFocusAndSelectSkipsTheOpening() throws {
        continueAfterFailure = false
        let app = launch([
            UITestLaunchArguments.resetSettings,
            UITestLaunchArguments.startAtOpening,
            UITestLaunchArguments.pickEpisodeWithOpening,
        ])
        openFeedAndPlay(in: app)
        try requireHint(in: app, kind: .opening)

        XCTAssertTrue(waitForHintFocus(in: app), "The hint never held focus, so Select could not act on it")
        attach(app, named: "player-hint-focused")

        // The press happens straight from the focused hint: reading the playhead first would open the
        // transport bar and take focus away, which is the exact bug this test exists to catch.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: hintTimeout),
            "Select on the focused hint did not skip the opening"
        )
        let after = playhead(in: app)
        XCTAssertNotNil(after, "The player does not expose its playhead after the skip")
        if let after {
            // Playback started two seconds into the opening, so a playhead beyond twenty seconds means the
            // segment was jumped rather than played through.
            XCTAssertGreaterThanOrEqual(after, 20, "The skip did not move the playhead (\(after)s)")
        }
        attach(app, named: "player-hint-after-skip")
    }

    // MARK: Lifetime

    @MainActor
    func testHintExpiresWithoutAPressAndDoesNotComeBack() throws {
        continueAfterFailure = false
        let app = launch(
            [
                UITestLaunchArguments.resetSettings,
                UITestLaunchArguments.startAtOpening,
                UITestLaunchArguments.pickEpisodeWithOpening,
            ]
                + UITestLaunchArguments.hintLifetime(4)
        )
        openFeedAndPlay(in: app)
        try requireHint(in: app, kind: .opening)
        XCTAssertTrue(waitForHintFocus(in: app), "The expiring hint never held focus")
        attach(app, named: "player-hint-before-expiry")

        let hint = element(identifier: "player.skipButton", in: app)
        XCTAssertTrue(
            waitForDisappearance(of: hint, timeout: 15),
            "The hint did not disappear on its own after the four-second lifetime"
        )
        // Still inside the same segment, and still no button: the offer must not return.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(
            hint.exists,
            "The hint came back after expiring, although the playhead is still inside the same segment"
        )
        attach(app, named: "player-hint-expired")
    }

    // MARK: Auto-skip

    @MainActor
    func testAutoSkipOpeningShowsNoHintAndMovesThePlayhead() {
        continueAfterFailure = false
        let app = launch([
            UITestLaunchArguments.resetSettings,
            UITestLaunchArguments.startAtOpening,
            UITestLaunchArguments.pickEpisodeWithOpening,
        ])
        XCTAssertTrue(
            setSwitch(identifier: "settings.openings", on: true, in: app),
            "Could not turn on opening auto-skip"
        )
        openFeedAndPlay(in: app)

        XCTAssertFalse(
            element(identifier: "player.skipButton", in: app).waitForExistence(timeout: 12),
            "The hint appeared even though openings are skipped automatically"
        )
        let seconds = playhead(in: app)
        XCTAssertNotNil(seconds, "The player does not expose its playhead")
        if let seconds {
            XCTAssertGreaterThan(seconds, 40, "Auto-skip did not move the playhead past the opening (\(seconds)s)")
        }
        attach(app, named: "player-auto-skip-opening")

        // Leave the switch as the owner ships it: off. Best effort — every launch in this suite starts with
        // `-uiTestingResetSettings`, so the next run sees the shipped defaults either way.
        leaveToFeed(in: app)
        _ = setSwitch(identifier: "settings.openings", on: false, in: app)
    }

    @MainActor
    func testAutoSkipEndingOffersTheNextEpisode() throws {
        continueAfterFailure = false
        let app = launch([
            UITestLaunchArguments.resetSettings,
            UITestLaunchArguments.startAtEnding,
            UITestLaunchArguments.pickEpisodeWithShortEnding,
        ])
        XCTAssertTrue(
            setSwitch(identifier: "settings.endings", on: true, in: app),
            "Could not turn on ending auto-skip"
        )
        openFeedAndPlay(in: app)

        let hint = element(identifier: "player.skipButton", in: app)
        guard hint.waitForExistence(timeout: hintTimeout) else {
            throw XCTSkip(
                "The episode played here has no next playable episode, so nothing is offered after the credits"
            )
        }
        XCTAssertTrue(
            hint.label.localizedCaseInsensitiveContains("Следующая"),
            "After auto-skipping the credits the player offers «\(hint.label)», expected «Следующая серия»"
        )
        attach(app, named: "player-auto-skip-ending-next")

        XCTAssertTrue(waitForHintFocus(in: app), "«Следующая серия» never held focus")
        XCUIRemote.shared.press(.select)
        let player = element(identifier: "player.screen", in: app)
        XCTAssertTrue(
            player.waitForExistence(timeout: screenTimeout),
            "The player did not come back with the next episode"
        )
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(
            setSwitch(identifier: "settings.endings", on: false, in: app),
            "Could not turn ending auto-skip off"
        )
        attach(app, named: "player-auto-skip-ending-started")
    }

    // MARK: Steps

    @MainActor
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra
        app.launch()
        return app
    }

    /// Closes the player and the detail screen until the feed is back.
    @MainActor
    private func leaveToFeed(in app: XCUIApplication) {
        let card = element(identifier: "latest.posterCard", in: app)
        let player = element(identifier: "player.screen", in: app)
        let detail = element(identifier: "detail.screen", in: app)
        // Player → detail → feed. Menu is pressed **only** while one of those covers is on screen: at the
        // section root a Menu press hands the screen to tvOS itself, and the app then cannot reach the
        // sidebar at all (that is how this helper used to fail when the feed was merely still loading).
        for _ in 0 ..< 6 {
            if card.exists {
                return
            }
            guard player.exists || detail.exists else {
                _ = card.waitForExistence(timeout: 3)
                continue
            }
            XCUIRemote.shared.press(.menu)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        XCTAssertTrue(
            card.waitForExistence(timeout: screenTimeout),
            "Menu never brought the feed back, so the sidebar cannot be reached"
        )
    }

    /// Opens «Настройки», flips one switch and returns to the feed.
    @MainActor
    private func setSwitch(identifier: String, on: Bool, in app: XCUIApplication) -> Bool {
        // The player is a full-screen cover and the sidebar deliberately is not drawn over it, so the
        // panel can only be reached after the player is closed.
        leaveToFeed(in: app)
        XCTAssertTrue(openSection(.settings, in: app), "The sidebar never reached «Настройки»")
        guard let toggle = waitForElement(identifier: identifier, in: app),
              focusToggle(toggle, in: app) else { return false }
        let currentlyOn = isOn(toggle)
        if currentlyOn != on {
            XCUIRemote.shared.press(.select)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        guard isOn(toggle) == on else { return false }
        XCTAssertTrue(openSection(.home, in: app), "The sidebar never reached «Главная»")
        return true
    }

    @MainActor
    private func focusToggle(_ toggle: XCUIElement, in _: XCUIApplication) -> Bool {
        // Down walks from the sidebar into the switches; Up covers the case where focus already overshot
        // into the second one.
        let directions: [XCUIRemote.Button] = [.down, .down, .up]
        for step in 0 ..< focusAttempts * directions.count {
            if toggle.exists, toggle.hasFocus {
                return true
            }
            XCUIRemote.shared.press(directions[step % directions.count])
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        return toggle.exists && toggle.hasFocus
    }

    /// Walks focus into the sidebar and opens `section` (ADR 0028: the panel replaced the tab bar).
    @MainActor
    private func openSection(_ section: ShellSection, in app: XCUIApplication) -> Bool {
        ShellNavigator.open(section, in: app, settle: settleTimeout)
    }

    @MainActor
    private func isFocusOnFeed(in app: XCUIApplication) -> Bool {
        isFocused(identifier: "latest.posterCard", in: app)
    }

    /// Waits for the feed, opens the first release, «Смотреть», the picker's default episode and the player.
    @MainActor
    private func openFeedAndPlay(in app: XCUIApplication) {
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        _ = posterCards.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(
            ShellNavigator.focus("latest.posterCard", in: app),
            "Focus never reached a poster card"
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).waitForExistence(timeout: screenTimeout),
            "The poster card did not open the detail screen"
        )
        for _ in 0 ..< focusAttempts where !isFocused(identifier: "detail.playButton", in: app) {
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        XCTAssertTrue(isFocused(identifier: "detail.playButton", in: app), "«Смотреть» cannot be focused")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element(identifier: "episodePicker.screen", in: app).waitForExistence(timeout: screenTimeout),
            "«Смотреть» did not open the episode picker"
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element(identifier: "player.screen", in: app).waitForExistence(timeout: screenTimeout),
            "Picking an episode did not open the player"
        )
    }

    @MainActor
    private func requireHint(in app: XCUIApplication, kind: SegmentKind) throws {
        let skip = element(identifier: "player.skipButton", in: app)
        guard skip.waitForExistence(timeout: hintTimeout) else {
            throw XCTSkip("The episode played here has no usable \(kind.rawValue) in the API")
        }
        let expected = kind == .opening ? "опенинг" : "эндинг"
        XCTAssertTrue(
            skip.label.localizedCaseInsensitiveContains(expected),
            "The hint is worded «\(skip.label)», expected it to name the \(expected)"
        )
    }

    enum SegmentKind: String {
        case opening
        case ending
    }

    /// Focuses the hint, retrying because a cold simulator can still be settling when it appears.
    @MainActor
    private func waitForHintFocus(in app: XCUIApplication) -> Bool {
        let hint = element(identifier: "player.skipButton", in: app)
        for _ in 0 ..< focusAttempts {
            if hint.exists, hint.hasFocus {
                return true
            }
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        return hint.exists && hint.hasFocus
    }

    /// Reads the elapsed time shown by the system transport bar, opening the bar when needed.
    @MainActor
    private func playhead(in app: XCUIApplication) -> Int? {
        let marker = app.descendants(matching: .any)["AXElapsedTime"].firstMatch
        for _ in 0 ..< 3 where !marker.exists {
            XCUIRemote.shared.press(.select)
            Thread.sleep(forTimeInterval: 2)
        }
        guard marker.exists else { return nil }
        let parts = marker.label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: settleTimeout)
        return parts[0] * 60 + parts[1]
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return !element.exists
    }

    @MainActor
    private func waitForElement(identifier: String, in app: XCUIApplication) -> XCUIElement? {
        let element = element(identifier: identifier, in: app)
        return element.waitForExistence(timeout: screenTimeout) ? element : nil
    }

    // MARK: Queries

    @MainActor
    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func isFocused(identifier: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", identifier))
            .firstMatch.exists
    }

    @MainActor
    private func isOn(_ toggle: XCUIElement) -> Bool {
        let value = (toggle.value as? String) ?? ""
        return value == "1" || value.localizedCaseInsensitiveContains("on")
            || value.localizedCaseInsensitiveContains("вкл")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
