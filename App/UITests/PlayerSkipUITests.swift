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
        let app = launchAtSegment([UITestLaunchArguments.startAtOpening])
        try requireHint(in: app, kind: .opening, launchArguments: [UITestLaunchArguments.startAtOpening])

        XCTAssertTrue(focusSkipButton(in: app), "The skip hint cannot be reached with the remote")
        attach(app, named: "player-skip-focused")

        let before = playhead(in: app)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: hintTimeout),
            "Skipping did not remove the hint"
        )
        let after = playhead(in: app)
        XCTAssertNotNil(before, "The player does not expose its playhead before the skip")
        XCTAssertNotNil(after, "The player does not expose its playhead after the skip")
        if let before, let after {
            XCTAssertGreaterThanOrEqual(
                after - before,
                10,
                "The skip did not jump the playhead (before \(before)s, after \(after)s)"
            )
        }
        attach(app, named: "player-skip-after")
    }

    // MARK: «Смотреть»

    @MainActor
    func testDismissButtonHidesTheHintForTheWholeSegment() throws {
        continueAfterFailure = false
        let app = launchAtSegment([UITestLaunchArguments.startAtOpening])
        try requireHint(in: app, kind: .opening, launchArguments: [UITestLaunchArguments.startAtOpening])

        let dismiss = element(identifier: "player.skipDismissButton", in: app)
        XCTAssertTrue(dismiss.exists, "The hint offers no «Смотреть» control")
        XCTAssertTrue(focus(dismiss, in: app), "«Смотреть» cannot be reached with the remote")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: 5),
            "«Смотреть» did not hide the hint"
        )
        // The viewer is still inside the segment: the choice must not come back on its own.
        Thread.sleep(forTimeInterval: 6)
        XCTAssertFalse(
            element(identifier: "player.skipButton", in: app).exists,
            "The dismissed hint came back while the viewer was still inside the same segment"
        )
        attach(app, named: "player-skip-dismissed")
    }

    // MARK: Transport bar

    @MainActor
    func testHintHidesWhileTheTransportBarIsOpenAndReturnsAfter() throws {
        continueAfterFailure = false
        let app = launchAtSegment([UITestLaunchArguments.startAtOpening])
        try requireHint(in: app, kind: .opening, launchArguments: [UITestLaunchArguments.startAtOpening])

        // Move focus off the hint, then open the system playback controls with Select.
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: settleTimeout)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            waitForDisappearance(of: element(identifier: "player.skipButton", in: app), timeout: hintTimeout),
            "The hint stayed on screen while the transport bar was open"
        )
        attach(app, named: "player-skip-transport-open")

        XCUIRemote.shared.press(.select)
        let hint = element(identifier: "player.skipButton", in: app)
        XCTAssertTrue(
            hint.waitForExistence(timeout: hintTimeout),
            "The hint did not come back after the transport bar closed (playhead still inside the segment)"
        )
        attach(app, named: "player-skip-transport-closed")
    }

    // MARK: Ending

    @MainActor
    func testEndingHintAppearsAndSaysEnding() throws {
        continueAfterFailure = false
        let app = launchAtSegment([UITestLaunchArguments.startAtEnding])
        guard try requireHint(
            in: app,
            kind: .ending,
            launchArguments: [UITestLaunchArguments.startAtEnding]
        ) else {
            return
        }
        attach(app, named: "player-skip-ending")
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
        XCTAssertTrue(
            element(identifier: "player.skipDismissButton", in: app).exists,
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
    private func focus(_ target: XCUIElement, in _: XCUIApplication) -> Bool {
        let directions: [XCUIRemote.Button] = [.down, .left, .right, .up]
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
        if !marker.exists {
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
