import XCTest

/// End-to-end proof of the journeys the remote has to make possible on the detail screen and in the
/// player: the detail screen must scroll from the hero down to the episode list, an episode has to
/// open the player, and the system transport bar has to offer every quality of the running episode.
///
/// Like `LatestFeedUITests`, the tests drive the real focus engine through `XCUIRemote` because the
/// touch APIs are unavailable on tvOS, and they key their assertions on accessibility identifiers
/// and on the system transport UI, never on layout coordinates.
final class DetailAndPlayerUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    /// Remote presses allowed while looking for a focusable target.
    private let focusAttempts = 8
    /// Qualities the transport bar can offer, best first (see `StreamResolver`).
    private let qualityLabels = ["1080p", "720p", "480p"]

    // MARK: Detail screen

    @MainActor
    func testDetailScrollsToEpisodeListAndPlaysAnEpisode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openFirstRelease(in: app)

        // The episode grid sits below the hero, so focus can only get there if the screen scrolls —
        // which is exactly what did not happen before the fix.
        XCTAssertTrue(
            focusEpisodeCard(in: app),
            "Down presses never reached the episode list: the detail screen does not scroll to it"
        )
        attach(app, named: "detail-episodes")

        XCUIRemote.shared.press(.select)
        let player = app.descendants(matching: .any)["player.screen"].firstMatch
        XCTAssertTrue(
            player.waitForExistence(timeout: screenTimeout),
            "Selecting an episode did not open the player"
        )
        // Give the player a moment to render frames before the screenshot.
        Thread.sleep(forTimeInterval: 4)
        attach(app, named: "player-episode")
    }

    // MARK: Player transport bar

    @MainActor
    func testQualityControlSwitchesTheStream() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openFirstRelease(in: app)

        // The primary action holds default focus on the detail screen (ADR 0012).
        XCUIRemote.shared.press(.select)
        let player = app.descendants(matching: .any)["player.screen"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: screenTimeout), "The play button did not open the player")
        // The system transport bar owns the remote until it hides itself again.
        Thread.sleep(forTimeInterval: 9)
        attach(app, named: "player-quality")

        let current = player.value as? String
        XCTAssertNotNil(current, "The player does not report the quality it is running")

        let button = app.buttons["player.qualityButton"]
        XCTAssertTrue(button.waitForExistence(timeout: screenTimeout), "The player offers no quality control")
        XCTAssertTrue(button.hasFocus, "The quality control does not hold focus when the player opens")
        XCUIRemote.shared.press(.select)

        let picker = app.descendants(matching: .any)["qualityPicker.screen"].firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: screenTimeout),
            "Selecting the quality control did not open the chooser"
        )
        attach(app, named: "quality-picker")

        let target = try XCTUnwrap(
            qualityLabels.first { $0 != current },
            "The episode offers a single stream, so there is nothing to switch to"
        )
        let targetButton = app.buttons["qualityPicker.\(target.prefix(3))"]
        XCTAssertTrue(targetButton.waitForExistence(timeout: screenTimeout), "The chooser does not offer \(target)")
        XCTAssertTrue(focus(targetButton, in: app, vertical: true), "The chooser cannot focus \(target)")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 4)

        XCTAssertFalse(picker.exists, "Choosing a quality did not close the chooser")
        XCTAssertEqual(player.value as? String, target, "The player did not switch to \(target)")
        attach(app, named: "player-quality-switched")
    }

    /// Presses Down (or Right, when the target shares the row) until `element` holds focus.
    @MainActor
    private func focus(
        _ element: XCUIElement,
        in _: XCUIApplication,
        vertical: Bool = true
    ) -> Bool {
        for _ in 0 ..< focusAttempts {
            if element.exists, element.hasFocus {
                return true
            }
            XCUIRemote.shared.press(vertical ? .down : .right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return element.exists && element.hasFocus
    }

    /// Opens the first poster of the feed and waits for its detail screen to take focus.
    @MainActor
    private func openFirstRelease(in app: XCUIApplication) {
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            posterCards.firstMatch.waitForExistence(timeout: feedTimeout),
            "The latest releases feed exposed no poster card"
        )
        for _ in 0 ..< focusAttempts {
            if isFocused(identifier: "latest.posterCard", in: app) {
                break
            }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(isFocused(identifier: "latest.posterCard", in: app), "Focus never reached a poster card")

        XCUIRemote.shared.press(.select)
        let detail = app.descendants(matching: .any)["detail.screen"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: screenTimeout), "The poster card did not open the detail screen")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "hasFocus == 1 AND identifier IN %@",
                    ["detail.playButton", "detail.synopsisToggle"]
                )
            ).firstMatch.waitForExistence(timeout: screenTimeout),
            "The detail screen never took focus"
        )
    }

    /// Presses Down until an episode card holds focus, i.e. until the screen scrolled the list into
    /// view.
    @MainActor
    private func focusEpisodeCard(in app: XCUIApplication) -> Bool {
        let cards = app.descendants(matching: .any).matching(identifier: "detail.episodeCard")
        let focusedCards = cards.matching(NSPredicate(format: "hasFocus == 1"))
        for _ in 0 ..< focusAttempts {
            if focusedCards.firstMatch.exists {
                return true
            }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.8)
        }
        return focusedCards.firstMatch.exists
    }

    // MARK: Queries

    @MainActor
    private func element(label: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    private func isFocused(identifier: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier == %@", identifier))
            .firstMatch.exists
    }

    @MainActor
    private func isFocused(label: String, in root: XCUIElement) -> Bool {
        root.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND label == %@", label))
            .firstMatch.exists
    }

    /// Elapsed playback time shown by the system transport bar, in seconds.
    @MainActor
    private func elapsedSeconds(in root: XCUIElement) -> Int? {
        let marker = root.descendants(matching: .any)["AXElapsedTime"].firstMatch
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
