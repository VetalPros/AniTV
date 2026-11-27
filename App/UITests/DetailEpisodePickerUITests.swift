import XCTest

/// End-to-end proof of the episode picker behind «Смотреть»: a modal grid in the new card style that
/// starts the chosen episode, and closes on Menu without playing anything.
///
/// The cards are asserted by count against the grid on the detail screen itself, and the chosen episode
/// is checked by its title in the system player's info panel, so nothing here depends on coordinates or
/// on private state.
final class DetailEpisodePickerUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    private let focusAttempts = 6
    private let settleTimeout: TimeInterval = 1.0

    @MainActor
    func testWatchOpensPickerAndStartsTheFocusedEpisode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openFirstRelease(in: app)
        focusPlayButton(in: app)

        XCUIRemote.shared.press(.select)
        let picker = element(identifier: "episodePicker.screen", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: screenTimeout), "«Смотреть» did not open the episode picker")
        attach(app, named: "episode-picker")

        // The picker shows the same episodes as the detail grid — no more, no less.
        let detailCards = app.descendants(matching: .any).matching(identifier: "detail.episodeCard")
        let pickerCards = app.descendants(matching: .any).matching(identifier: "detail.pickerEpisodeCard")
        XCTAssertGreaterThan(pickerCards.count, 0, "The episode picker rendered no episodes")
        XCTAssertEqual(
            pickerCards.count,
            detailCards.count,
            "The picker lists a different number of episodes than the release has"
        )

        // The picker starts on the episode the player would have started, so Select plays it.
        let focusedCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", "detail.pickerEpisodeCard"))
            .firstMatch
        XCTAssertTrue(
            focusedCard.waitForExistence(timeout: 10),
            "The episode picker never focused one of its cards"
        )
        // The card label is "<title>, <ordinal>"; the player repeats only the title.
        let expectedTitle = focusedCard.label
            .components(separatedBy: ", ")
            .dropLast()
            .joined(separator: ", ")
        XCUIRemote.shared.press(.select)

        let player = element(identifier: "player.screen", in: app)
        XCTAssertTrue(
            player.waitForExistence(timeout: screenTimeout),
            "Selecting an episode in the picker did not open the player"
        )
        attach(app, named: "player-picked-episode")

        // The system player's info panel repeats the episode it is playing, which is the only honest way
        // to tell "this episode" from "some episode" from the outside.
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 2)
        let shown = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let titlePrefix = String(expectedTitle.prefix(16))
        XCTAssertTrue(
            shown.contains { $0.hasPrefix(titlePrefix) },
            "The player does not show the episode that was picked in the picker («\(titlePrefix)…»)"
        )
    }

    @MainActor
    func testMenuClosesThePickerWithoutPlaying() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openFirstRelease(in: app)

        // Screenshot the new episode cards on the detail screen: Down walks from the hero to the grid.
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settleTimeout)
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settleTimeout)
        attach(app, named: "detail-episode-grid")

        // Back up to the hero: Up walks the chain the other way and lands on the hero action that holds
        // focus, which is «Продолжить» when the release has saved progress.
        let heroActions = app.descendants(matching: .any).matching(
            NSPredicate(format: "hasFocus == 1 AND identifier IN %@", ["detail.playButton", "detail.resumeButton"])
        )
        // Up walks back towards the hero, but a walk that ends in the sidebar has to be steered out again,
        // so the direction alternates instead of assuming focus is always below the hero.
        let returnCycle: [XCUIRemote.Button] = [.up, .up, .up, .down]
        for step in 0 ..< focusAttempts * returnCycle.count where !heroActions.firstMatch.exists {
            // The sidebar is the new overshoot: Up there only walks its rows, so leave it first.
            if ShellNavigator.panelRowIsFocused(in: app) {
                XCUIRemote.shared.press(.right)
            } else {
                XCUIRemote.shared.press(returnCycle[step % returnCycle.count])
            }
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        XCTAssertTrue(heroActions.firstMatch.exists, "Up never returned to a hero action")
        focusPlayButton(in: app)

        XCUIRemote.shared.press(.select)
        let picker = element(identifier: "episodePicker.screen", in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: screenTimeout), "«Смотреть» did not open the episode picker")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            element(identifier: "detail.screen", in: app).waitForExistence(timeout: screenTimeout),
            "Menu did not dismiss the picker back to the detail screen"
        )
        XCTAssertFalse(picker.exists, "The episode picker is still presented after Menu")
        XCTAssertFalse(
            element(identifier: "player.screen", in: app).exists,
            "Closing the picker with Menu started playback anyway"
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
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "hasFocus == 1 AND identifier IN %@",
                    ["detail.playButton", "detail.resumeButton", "detail.synopsisToggle"]
                )
            ).firstMatch.waitForExistence(timeout: screenTimeout),
            "The detail screen never took focus"
        )
    }

    /// Puts focus on «Смотреть»: when «Продолжить» is present it sits to the left of it and takes the
    /// focus first, so one Right press is enough.
    @MainActor
    private func focusPlayButton(in app: XCUIApplication) {
        for _ in 0 ..< focusAttempts {
            if isFocused(identifier: "detail.playButton", in: app) {
                return
            }
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: settleTimeout)
        }
        XCTAssertTrue(isFocused(identifier: "detail.playButton", in: app), "«Смотреть» cannot be focused")
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
