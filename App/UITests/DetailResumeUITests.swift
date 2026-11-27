import XCTest

/// End-to-end proof that a position survives leaving the player and coming back: play a bit, leave,
/// reopen the release and continue from where the viewer stopped.
///
/// The whole loop is real — the player writes the position through the Kit store into the app's
/// `UserDefaults`, the detail screen reads it back on the next open, and the resumed stream is checked
/// against the system transport bar's elapsed time, not against an internal counter. Like the other UI
/// tests it drives the focus engine with `XCUIRemote`, because the touch APIs are unavailable on tvOS.
final class DetailResumeUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    private let focusAttempts = 6
    private let settleTimeout: TimeInterval = 1.0

    /// Seconds of playback watched in the first pass. Comfortably past the Kit's 15-second resume
    /// threshold, short enough to keep the test quick.
    private let watchedSeconds: TimeInterval = 20

    @MainActor
    func testPlayingEpisodeOffersResumeAtTheSavedPosition() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openFirstRelease(in: app)

        // Play the primary episode from the beginning and let it run long enough for the player to
        // persist a position (it saves every few seconds and once more on the way out).
        XCUIRemote.shared.press(.select)
        let playerScreen = app.descendants(matching: .any)["player.screen"].firstMatch
        // «Смотреть» opens the episode picker first; the picker focuses the episode the player would
        // have started, so one more Select starts it.
        let picker = app.descendants(matching: .any)["episodePicker.screen"].firstMatch
        if picker.waitForExistence(timeout: 10) {
            let pickerCards = app.descendants(matching: .any).matching(identifier: "detail.pickerEpisodeCard")
            XCTAssertGreaterThan(pickerCards.count, 0, "The episode picker rendered no episodes")
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(
            playerScreen.waitForExistence(timeout: screenTimeout),
            "Selecting the hero action (picker path included) did not open the player"
        )
        Thread.sleep(forTimeInterval: watchedSeconds)

        // Menu dismisses the player (not the app), Menu once more returns to the feed.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).waitForExistence(timeout: screenTimeout),
            "Menu did not dismiss the player back to the detail screen"
        )
        XCUIRemote.shared.press(.menu)
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: screenTimeout),
            "Menu did not return to the feed"
        )

        // Reopen the release that was just watched: the store has to have survived the round trip.
        //
        // The pop back to the feed can leave focus in the sidebar instead of the card that was open, and a
        // dropped Select then goes nowhere, so focus is re-established and the press repeated.
        let detail = element(identifier: "detail.screen", in: app)
        for step in 0 ..< 6 where !isFocused(identifier: "latest.posterCard", in: app) {
            XCUIRemote.shared.press(step.isMultiple(of: 2) ? .right : .down)
            Thread.sleep(forTimeInterval: 0.6)
        }
        for _ in 0 ..< 3 where !detail.exists {
            XCUIRemote.shared.press(.select)
            _ = detail.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(
            detail.waitForExistence(timeout: screenTimeout),
            "Reopening the release did not show its detail screen"
        )
        let resumeButton = element(identifier: "detail.resumeButton", in: app)
        XCTAssertTrue(
            resumeButton.waitForExistence(timeout: screenTimeout),
            "The detail screen offers no «Продолжить» after \(Int(watchedSeconds))s of playback"
        )
        attach(app, named: "detail-resume")

        assertOneEpisodeShowsProgress(in: app)
        // Scroll the grid into view so the screenshot actually shows the bar, then come back to the hero.
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settleTimeout)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settleTimeout)
        attach(app, named: "detail-episode-progress")
        let backCycle: [XCUIRemote.Button] = [.up, .up, .up, .down]
        for step in 0 ..< focusAttempts * returnCycleMultiplier where !isFocused(
            identifier: "detail.resumeButton",
            in: app
        ) {
            XCUIRemote.shared.press(returnCycle[step % returnCycle.count])
            Thread.sleep(forTimeInterval: settleTimeout)
        }

        // «Смотреть» keeps default focus, so the resume action is one press to the left.
        XCTAssertTrue(focus(resumeButton, in: app, pressing: .left), "«Продолжить» cannot be focused with the remote")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            playerScreen.waitForExistence(timeout: screenTimeout),
            "Selecting «Продолжить» did not open the player"
        )
        Thread.sleep(forTimeInterval: 4)
        attach(app, named: "player-resumed")

        // The system transport bar reports the stream's own playhead: it must continue from where the
        // first pass stopped instead of restarting at 00:00.
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 2)
        let resumed = elapsedSeconds(in: app)
        XCTAssertNotNil(resumed, "The transport bar does not show the elapsed time after resuming")
        if let resumed {
            XCTAssertGreaterThanOrEqual(
                resumed,
                Int(watchedSeconds) - 5,
                "Playback restarted at 00:\(resumed) instead of continuing from the saved position"
            )
        }
    }

    /// Per-episode progress: exactly one episode card carries a watched fraction, exposed through the
    /// card's accessibility value because a card is a single accessibility element.
    @MainActor
    private func assertOneEpisodeShowsProgress(in app: XCUIApplication) {
        let cards = app.descendants(matching: .any).matching(identifier: "detail.episodeCard")
        let watched = cards.allElementsBoundByIndex.filter { ($0.value as? String)?.hasSuffix("%") == true }
        XCTAssertGreaterThan(
            watched.count,
            0,
            "No episode card shows a watched-progress bar after \(Int(watchedSeconds))s of playback"
        )
        XCTAssertLessThan(
            watched.count,
            cards.count,
            "Every episode card claims progress, so the bar does not reflect a single watched episode"
        )
    }

    // MARK: Steps

    /// Opens the first poster of the feed and waits for its detail screen to take focus.
    @MainActor
    private func openFirstRelease(in app: XCUIApplication) {
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card"
        )
        XCTAssertTrue(
            ShellNavigator.focus("latest.posterCard", in: app),
            "Focus never reached a poster card"
        )

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).waitForExistence(timeout: screenTimeout),
            "The poster card did not open the detail screen"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "hasFocus == 1 AND identifier IN %@",
                        ["detail.playButton", "detail.resumeButton", "detail.synopsisToggle"]
                    )
                )
                .firstMatch.waitForExistence(timeout: screenTimeout),
            "The detail screen never took focus"
        )
    }

    /// Presses `button` until `target` holds focus.
    /// Multiplier for long focus walks: each cycle costs a couple of presses.
    @MainActor
    private var returnCycleMultiplier: Int {
        4
    }

    /// Alternating direction used when walking back to the hero action.
    private var returnCycle: [XCUIRemote.Button] {
        [.up, .up, .up, .down]
    }

    @MainActor
    private func focus(_ target: XCUIElement, in app: XCUIApplication, pressing button: XCUIRemote.Button) -> Bool {
        // The first presses go in the requested direction; after that the opposite direction is mixed in, so a
        // focus that overshoots (into the sidebar, for instance) can still come back.
        let opposite: XCUIRemote.Button = switch button {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        default: button
        }
        let cycle: [XCUIRemote.Button] = [button, button, button, opposite]
        for step in 0 ..< focusAttempts * cycle.count {
            if isFocused(identifier: target.identifier, in: app) {
                return true
            }
            XCUIRemote.shared.press(cycle[step % cycle.count])
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        return isFocused(identifier: target.identifier, in: app)
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

    /// Elapsed playback time shown by the system transport bar, in seconds.
    @MainActor
    private func elapsedSeconds(in app: XCUIApplication) -> Int? {
        let marker = app.descendants(matching: .any)["AXElapsedTime"].firstMatch
        guard marker.exists else { return nil }
        let parts = marker.label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
