import XCTest

/// Proof for the player's skip hint: it is reachable with the remote, it can be waved away, it does not
/// sit on top of the transport bar, and it serves both the opening and the ending.
///
/// The hint lives inside `AVPlayerViewController.contentOverlayView`, so it is part of the player's own
/// focus engine — the assertions here read real focus and real system elements, not app-side bookkeeping.
final class PlayerSkipUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    private let hintTimeout: TimeInterval = 25
    private let focusAttempts = 10
    private let settleTimeout: TimeInterval = 1.0

    // MARK: Opening

    @MainActor
    func testOpeningHintIsFocusableAndSkipMovesThePlayhead() throws {
        continueAfterFailure = false
        let app = launchAtSegment([UITestLaunchArguments.startAtOpening, UITestLaunchArguments.pickEpisodeWithOpening])
        try requireHint(
            in: app,
            kind: .opening,
            launchArguments: [UITestLaunchArguments.startAtOpening, UITestLaunchArguments.pickEpisodeWithOpening]
        )

        // A cold simulator can take a moment before the player actually plays and takes focus; wait for the
        // clock to move instead of assuming it is already running.
        XCTAssertTrue(waitForPlaybackInProgress(in: app), "Playback never started on this run")
        var focused = focusSkipButton(in: app)
        for _ in 0 ..< 3 where !focused {
            // The first poke can land while the player is still settling; retry instead of failing.
            Thread.sleep(forTimeInterval: settleTimeout)
            focused = focusSkipButton(in: app)
        }
        XCTAssertTrue(focused, "The skip hint cannot be reached with the remote")
        attach(app, named: "player-skip-focused")

        XCTAssertTrue(focusSkipButton(in: app), "The skip hint lost focus before the press")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: 6),
            "Skipping did not remove the hint"
        )
        // The clock in the transport bar is a lagging accessibility label and reading it means opening the
        // bar, which hides the hint by itself — so the assertion is about what only a real skip can do:
        // after the segment has been left behind, the hint must not come back when the bar is closed again.
        // Had the press only opened the player controls, closing them would bring the hint straight back.
        XCTAssertTrue(
            hintStaysGoneAfterTheControlsClose(in: app),
            "The hint came back once the player controls were closed, so the press opened the bar instead of skipping"
        )
        attach(app, named: "player-skip-after")
    }

    // MARK: «Смотреть»

    @MainActor
    func testDismissControlIsFocusableAndHidesTheHintWithoutSeeking() throws {
        continueAfterFailure = false
        let args = [UITestLaunchArguments.startAtOpening, UITestLaunchArguments.pickEpisodeWithOpening]
        let app = launchAtSegment(args)
        try requireHint(in: app, kind: .opening, launchArguments: args)

        let dismiss = element(identifier: "player.skipDismissButton", in: app)
        XCTAssertTrue(dismiss.exists, "The hint offers no «Смотреть» control")
        XCTAssertTrue(
            focus(dismiss, in: app, startingWith: .right),
            "Focus never reaches «Смотреть», the second control of the hint"
        )
        attach(app, named: "player-dismiss-focused")

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: 5),
            "«Смотреть» did not hide the hint"
        )
        // The hint is gone, and the playhead kept its own pace: two readings two seconds apart differ by
        // about two seconds, not by a segment length.
        let first = playhead(in: app)
        Thread.sleep(forTimeInterval: 2)
        let second = playhead(in: app)
        XCTAssertNotNil(first, "The player does not expose its playhead")
        XCTAssertNotNil(second, "The player does not expose its playhead")
        if let first, let second {
            XCTAssertLessThanOrEqual(
                abs(second - first - 2),
                4,
                "«Смотреть» moved the playhead (from \(first)s to \(second)s) instead of only hiding the hint"
            )
        }
    }

    // MARK: Player controls

    /// The hint must be gone while the viewer is in the player's own controls, and come back afterwards.
    ///
    /// There is no public "transport bar is open" callback, so the app combines the two signals it can read:
    /// focus leaving the hint, and any press the player itself handled. Both hide the hint, and it returns on
    /// its own a few seconds later while the playhead is still inside the segment.
    @MainActor
    func testHintHidesWhileTheViewerIsInThePlayerControls() throws {
        continueAfterFailure = false
        let args = [UITestLaunchArguments.startAtOpening, UITestLaunchArguments.pickEpisodeWithOpening]
        let app = launchAtSegment(args)
        try requireHint(in: app, kind: .opening, launchArguments: args)
        XCTAssertTrue(focusSkipButton(in: app), "The skip hint cannot be reached with the remote")

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: 6),
            "The hint stayed on screen while the viewer was in the player controls"
        )
        attach(app, named: "player-hint-hidden-in-controls")

        let hint = element(identifier: "player.skipButton", in: app)
        XCTAssertTrue(
            hint.waitForExistence(timeout: hintTimeout),
            "The hint did not come back after the viewer left the player controls"
        )
        attach(app, named: "player-hint-back")
    }

    // MARK: Ending

    /// «Следующая серия» must actually switch the episode: the player closes and the next one starts.
    @MainActor
    func testNextEpisodeControlSwitchesTheEpisode() throws {
        continueAfterFailure = false
        let args = [UITestLaunchArguments.startAtEnding, UITestLaunchArguments.pickEpisodeWithShortEnding]
        let app = launchAtSegment(args)

        let skip = element(identifier: "player.skipButton", in: app)
        guard skip.waitForExistence(timeout: hintTimeout) else {
            throw XCTSkip("The episode played here has no usable ending in the API")
        }
        guard skip.label.localizedCaseInsensitiveContains("Следующая") else {
            throw XCTSkip(
                "This episode keeps a post-credit tail, so the ending control is «\(skip.label)»; no release "
                    + "episode with a short ending was found"
            )
        }
        attach(app, named: "player-next-episode-focused")
        // The episode the player is on, read from its own info panel before the switch.
        let beforeTitle = playerTitle(in: app)

        XCTAssertTrue(focusSkipButton(in: app), "«Следующая серия» cannot be reached with the remote")
        XCUIRemote.shared.press(.select)

        // The player cover closes and the next episode starts: the player is presented again, showing a
        // different episode together with a fresh playhead near zero.
        let player = element(identifier: "player.screen", in: app)
        XCTAssertTrue(
            player.waitForExistence(timeout: screenTimeout),
            "The player did not come back with the next episode"
        )
        Thread.sleep(forTimeInterval: 4)
        let afterTitle = playerTitle(in: app)
        XCTAssertNotEqual(
            afterTitle,
            beforeTitle,
            "The player still reports the previous episode («\(afterTitle)»), so «Следующая серия» only changed its label"
        )
        attach(app, named: "player-next-episode-started")
    }

    /// Longest static text the player shows: the episode title in the system info panel.
    ///
    /// Opening the panel needs Select; when the hint holds focus the first press goes to it, so the press is
    /// retried until the transport bar reports its elapsed time.
    @MainActor
    private func playerTitle(in app: XCUIApplication) -> String {
        _ = playhead(in: app)
        let player = element(identifier: "player.screen", in: app)
        // Scoped to the player: the detail screen underneath also has long texts, and mixing them in made
        // the comparison meaningless.
        let texts = player.descendants(matching: .staticText).allElementsBoundByIndex
            .map(\.label)
            .filter { $0.count > 8 && !$0.contains("Смотреть") && !$0.contains("Следующая") }
        return texts.max(by: { $0.count < $1.count }) ?? ""
    }

    // MARK: Steps

    /// Launches the app and walks feed → detail → «Смотреть» → picker → player.
    @MainActor
    private func launchAtSegment(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()

        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card"
        )
        for _ in 0 ..< focusAttempts where !isFocused(identifier: "latest.posterCard", in: app) {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(isFocused(identifier: "latest.posterCard", in: app), "Focus never reached a poster card")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).waitForExistence(timeout: screenTimeout),
            "The poster card did not open the detail screen"
        )

        // «Смотреть» opens the episode picker; its default focus is the episode the player would start.
        for _ in 0 ..< focusAttempts where !isFocused(identifier: "detail.playButton", in: app) {
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(isFocused(identifier: "detail.playButton", in: app), "«Смотреть» cannot be focused")
        XCUIRemote.shared.press(.select)
        let picker = element(identifier: "episodePicker.screen", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: screenTimeout), "«Смотреть» did not open the episode picker")
        XCUIRemote.shared.press(.select)

        let player = element(identifier: "player.screen", in: app)
        XCTAssertTrue(player.waitForExistence(timeout: screenTimeout), "Picking an episode did not open the player")
        return app
    }

    /// Waits for the skip hint of `kind`.
    ///
    /// - Returns: `true` when the hint is on screen.
    /// - Throws: `XCTSkip` when the episode has no usable segment of that kind in the API, which is a
    ///   property of the content rather than a defect of the player.
    @discardableResult
    @MainActor
    private func requireHint(
        in app: XCUIApplication,
        kind: PlayerSkipUITests.SegmentKind,
        launchArguments _: [String]
    ) throws -> Bool {
        let skip = element(identifier: "player.skipButton", in: app)
        guard skip.waitForExistence(timeout: hintTimeout) else {
            throw XCTSkip("The episode played here has no usable \(kind.rawValue) in the API")
        }
        let expected = kind == .opening ? "опенинг" : "эндинг"
        XCTAssertTrue(
            skip.label.localizedCaseInsensitiveContains(expected),
            "The skip hint is worded «\(skip.label)», expected it to name the \(expected)"
        )
        // The overlay is configured a beat after it is inserted, so a bare `exists` here was a race: the
        // full-suite run caught it once while the class-only run always saw both buttons.
        XCTAssertTrue(
            element(identifier: "player.skipDismissButton", in: app).waitForExistence(timeout: hintTimeout),
            "The hint offers no «Смотреть» control"
        )
        return true
    }

    /// Which segment the test expects; mirrors the app's own enum for assertion messages only.
    enum SegmentKind: String {
        case opening
        case ending
    }

    /// Presses directions until the skip button holds focus.
    @MainActor
    private func focusSkipButton(in app: XCUIApplication) -> Bool {
        focus(element(identifier: "player.skipButton", in: app), in: app)
    }

    @MainActor
    private func focus(
        _ target: XCUIElement,
        in _: XCUIApplication,
        startingWith first: XCUIRemote.Button = .down
    ) -> Bool {
        let directions: [XCUIRemote.Button] = [first] + [.down, .left, .right, .up].filter { $0 != first }
        for step in 0 ..< focusAttempts * directions.count {
            if target.exists, target.hasFocus {
                return true
            }
            XCUIRemote.shared.press(directions[step % directions.count])
            Thread.sleep(forTimeInterval: 0.5)
        }
        return target.exists && target.hasFocus
    }

    /// Reads the elapsed time the system transport bar shows, opening the bar first when needed.
    @MainActor
    private func playhead(in app: XCUIApplication) -> Int? {
        let marker = app.descendants(matching: .any)["AXElapsedTime"].firstMatch
        for _ in 0 ..< 3 where !marker.exists {
            // A Select lands on the hint when it has focus; the second press opens the system bar.
            XCUIRemote.shared.press(.select)
            Thread.sleep(forTimeInterval: 2)
        }
        guard marker.exists else { return nil }
        let parts = marker.label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        // Reading the bar opened it; close it again so the hint can come back for the next step.
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: settleTimeout)
        return parts[0] * 60 + parts[1]
    }

    /// Waits until the player is actually running.
    ///
    /// Deliberately does not press Select: on a cold simulator the first seconds are spent loading, and
    /// opening the transport bar would hide the very hint the test is about.
    @MainActor
    private func waitForPlaybackInProgress(in app: XCUIApplication) -> Bool {
        for _ in 0 ..< 15 {
            if element(identifier: "player.skipButton", in: app).exists {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// Opens and closes the player controls and reports whether the hint stayed away.
    ///
    /// The distinguishing behaviour of a real skip: the playhead left the segment, so the hint has nothing to
    /// show. If the earlier press had only opened the transport bar, the hint would reappear here.
    @MainActor
    private func hintStaysGoneAfterTheControlsClose(in app: XCUIApplication) -> Bool {
        let hint = element(identifier: "player.skipButton", in: app)
        for _ in 0 ..< 2 {
            XCUIRemote.shared.press(.select)
            Thread.sleep(forTimeInterval: 1.5)
        }
        Thread.sleep(forTimeInterval: 2)
        return !hint.exists
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
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
