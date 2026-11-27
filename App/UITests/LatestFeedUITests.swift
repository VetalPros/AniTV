import XCTest

/// End-to-end proof that the latest-releases feed navigates to a release detail screen on the
/// tvOS simulator.
///
/// `XCUIElement.tap()` and the rest of the touch APIs are unavailable on tvOS, so the test does
/// what a person with a remote does: it drives the real focus engine through `XCUIRemote` and
/// activates the focused poster card with the select button. Assertions are keyed on the
/// accessibility identifiers the views publish (`latest.posterCard`, `detail.screen`,
/// `detail.playButton`), never on layout coordinates.
///
/// Two simulator behaviours shape the helpers below and neither weakens the assertions:
/// the remote channel occasionally drops a single press, and Menu is routed through the focus
/// engine — with nothing focused the press falls through to the system and the app is sent to the
/// home screen instead of popping the navigation stack. A press is therefore repeated, always
/// after re-checking the state it depends on (`openDetail`, `returnToFeed`).
///
/// If a run fails inside `XCUIApplication.launch()` with "Application 'tv.anitv.client' does not
/// have a process ID", the simulator is wedged rather than the app: reboot it with
/// `xcrun simctl shutdown <udid> && xcrun simctl boot <udid>` and rerun.
final class LatestFeedUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 45
    private let detailTimeout: TimeInterval = 30
    private let focusTimeout: TimeInterval = 20
    /// How long a single remote press is given to take effect before it is sent again.
    private let pressTimeout: TimeInterval = 12
    /// How many times one remote press may be repeated.
    private let pressAttempts = 3
    /// How many Down presses may be spent looking for something the focus engine calls focused.
    private let focusAttempts = 4

    @MainActor
    func testSelectingPosterOpensDetailAndMenuReturnsToFeed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        // The feed needs a real network round-trip, so the first card can take a while to appear.
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card within \(feedTimeout)s"
        )
        XCTAssertGreaterThan(posterCards.count, 1, "The grid should render more than one poster card")
        XCTAssertFalse(posterCards.firstMatch.label.isEmpty, "A poster card must expose a title for VoiceOver")
        keepScreenshot(of: app, named: "1-feed")

        // Focus starts in the sidebar; Right leaves it for the grid, Down lands on a poster card.
        let focusedCard = focusPosterCard(in: app)
        XCTAssertNotNil(focusedCard, "Down presses never moved focus onto a poster card within \(focusTimeout)s")
        XCTAssertEqual(
            focusedCard?.identifier,
            "latest.posterCard",
            "Focus must sit on a poster card before the select button is pressed"
        )
        let selectedLabel = focusedCard?.label ?? ""
        XCTAssertFalse(selectedLabel.isEmpty, "The focused poster card must expose its title")

        // Select is what the remote sends when the user opens a release.
        let detailScreen = app.descendants(matching: .any)["detail.screen"].firstMatch
        XCTAssertTrue(
            openDetail(in: app, showing: detailScreen),
            "Selecting a poster card did not push the detail screen"
        )
        let playButtons = app.buttons.matching(identifier: "detail.playButton")
        let playButton = playButtons.firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: detailTimeout), "The detail screen shows no play button")
        keepScreenshot(of: app, named: "2-detail")
        // The pushed screen has to take focus. On tvOS a Menu press with nothing focused is handled
        // by the system, which backgrounds the app instead of popping the stack — the back path is
        // only real if the detail screen claims focus for one of its actions.
        let focusedControl = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "hasFocus == 1 AND identifier IN %@",
                ["detail.playButton", "detail.resumeButton", "detail.synopsisToggle"]
            )
        )
        XCTAssertTrue(
            focusedControl.firstMatch.waitForExistence(timeout: focusTimeout),
            "The detail screen never took focus, so Menu would leave the app instead of popping"
        )
        // The detail screen must describe the release that was actually selected: the card label is
        // "<title>. <subtitle>", so the title it starts with has to be on screen.
        let titles = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        XCTAssertTrue(
            titles.contains(where: selectedLabel.hasPrefix),
            "The detail screen does not show the title of the selected poster card"
        )

        // Menu is the remote's back button: the detail screen must pop and the feed must come back.
        XCTAssertTrue(
            returnToFeed(in: app, showing: posterCards, leaving: detailScreen),
            "Menu did not return to the feed"
        )
        XCTAssertFalse(detailScreen.exists, "The detail screen is still on screen after Menu")
    }

    @MainActor
    func testPlayButtonOpensPlayerAndMenuReturnsToDetail() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card within \(feedTimeout)s"
        )
        XCTAssertNotNil(focusPosterCard(in: app), "Down presses never moved focus onto a poster card")

        let detailScreen = app.descendants(matching: .any)["detail.screen"].firstMatch
        XCTAssertTrue(
            openDetail(in: app, showing: detailScreen),
            "Selecting a poster card did not push the detail screen"
        )

        // Focus must land on the hero's action, otherwise Select cannot reach the player at all. Which
        // of the two it is depends on whether this release has saved progress («Продолжить» then).
        let focusedHeroAction = app.descendants(matching: .any).matching(
            NSPredicate(format: "hasFocus == 1 AND identifier IN %@", ["detail.playButton", "detail.resumeButton"])
        )
        XCTAssertTrue(
            focusedHeroAction.firstMatch.waitForExistence(timeout: focusTimeout),
            "The detail screen never focused its primary action, so Select could not start playback"
        )
        // «Смотреть» now opens the episode picker; «Продолжить» still starts the saved position
        // directly, and which of the two holds focus depends on the stored progress. Both paths are
        // asserted, the picker one explicitly.
        let playerScreen = startPlaybackFromHeroAction(in: app)
        XCTAssertTrue(
            playerScreen.waitForExistence(timeout: detailTimeout),
            "The hero action did not reach the player (picker path included)"
        )
        keepScreenshot(of: app, named: "3-player")

        // Menu is the player's exit path: the cover must dismiss back to the detail screen.
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            detailScreen.waitForExistence(timeout: detailTimeout),
            "Menu did not dismiss the player back to the detail screen"
        )
        XCTAssertFalse(playerScreen.exists, "The player screen is still presented after Menu")
    }

    /// Selects the focused hero action and, when that opens the episode picker (what «Смотреть» does now),
    /// picks the episode the picker starts on. Returns once the player is on screen.
    @MainActor
    private func startPlaybackFromHeroAction(in app: XCUIApplication) -> XCUIElement {
        let player = app.descendants(matching: .any)["player.screen"].firstMatch
        let picker = app.descendants(matching: .any)["episodePicker.screen"].firstMatch
        XCUIRemote.shared.press(.select)
        if picker.waitForExistence(timeout: 10) {
            let pickerCards = app.descendants(matching: .any).matching(identifier: "detail.pickerEpisodeCard")
            XCTAssertGreaterThan(
                pickerCards.count,
                0,
                "The episode picker behind «Смотреть» rendered no episodes"
            )
            // The picker focuses the episode the player would have started, so Select starts it.
            XCUIRemote.shared.press(.select)
        }
        return player
    }

    /// Presses Select while a poster card holds focus and waits for the detail screen to be pushed.
    ///
    /// A press is repeated only while the app is demonstrably still on the feed, so a retry can
    /// never land on the detail screen (where Select would start playback).
    @MainActor
    private func openDetail(in app: XCUIApplication, showing detailScreen: XCUIElement) -> Bool {
        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        for attempt in 0 ..< pressAttempts {
            // The feed re-renders when the images arrive and can drop focus back to the sidebar, so
            // every attempt starts by making sure a poster card is the focused element again.
            if !cards.matching(NSPredicate(format: "hasFocus == 1")).firstMatch.exists {
                _ = focusPosterCard(in: app)
            }
            XCUIRemote.shared.press(.select)
            if detailScreen.waitForExistence(timeout: pressTimeout) {
                return true
            }
            guard attempt < pressAttempts - 1, isShowingFeed(in: app) else { return false }
        }
        return false
    }

    /// Presses Menu until the feed is back, and reports whether it came back.
    ///
    /// Menu reaches the app through the focused element, so focus is confirmed first; if the press
    /// went to the system instead and backgrounded the app, the app is re-activated and the press
    /// repeated once.
    @MainActor
    private func returnToFeed(
        in app: XCUIApplication,
        showing cards: XCUIElementQuery,
        leaving detailScreen: XCUIElement
    ) -> Bool {
        for attempt in 0 ..< pressAttempts {
            if app.state != .runningForeground {
                app.activate()
            }
            ensureFocus(in: app)
            XCUIRemote.shared.press(.menu)
            if cards.firstMatch.waitForExistence(timeout: pressTimeout) {
                return true
            }
            // Still on the detail screen, or backgrounded by the system: another press may help.
            // Anything else means the pop happened but the feed is empty, which no press can fix.
            guard attempt < pressAttempts - 1, detailScreen.exists || app.state != .runningForeground else {
                return false
            }
        }
        return false
    }

    /// Presses Down until the focus engine reports a focused element carrying the poster-card
    /// identifier, which is what a person does with a remote.
    @MainActor
    private func focusPosterCard(in app: XCUIApplication) -> XCUIElement? {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == 1"))
        let deadline = Date().addingTimeInterval(focusTimeout)
        // Right leaves the panel for the grid; Down walks the rows. Alternating covers both "focus is in
        // the sidebar" and "focus is already in the grid, above the cards".
        let cycle: [XCUIRemote.Button] = [.right, .down, .down, .right]
        var step = 0
        while Date() < deadline {
            let element = focused.firstMatch
            if element.exists, element.identifier == "latest.posterCard" {
                return element
            }
            XCUIRemote.shared.press(cycle[step % cycle.count])
            step += 1
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    /// Gives the focus engine something to deliver Menu to. On tvOS a Menu press with no focused
    /// view is handled by the system, which leaves the app instead of popping the screen.
    @MainActor
    private func ensureFocus(in app: XCUIApplication) {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == 1"))
        for _ in 0 ..< focusAttempts {
            guard !focused.firstMatch.exists else { return }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Keeps a screenshot in the result bundle, so the evidence of each verified screen survives the
    /// run instead of depending on somebody watching the simulator at the right moment.
    @MainActor
    private func keepScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Whether the app is in the foreground on the latest-releases feed.
    @MainActor
    private func isShowingFeed(in app: XCUIApplication) -> Bool {
        guard app.state == .runningForeground else { return false }
        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        return cards.firstMatch.exists
    }
}
