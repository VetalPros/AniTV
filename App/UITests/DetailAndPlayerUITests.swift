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
    func testTransportBarQualityMenuSwitchesTheStream() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        openFirstRelease(in: app)

        // «Смотреть» opens the episode picker; «Продолжить» holds default focus when the release has saved
        // progress and skips the picker, so «Смотреть» is focused explicitly first.
        focusPlayButton(in: app)
        XCUIRemote.shared.press(.select)
        let picker = app.descendants(matching: .any)["episodePicker.screen"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: screenTimeout), "«Смотреть» did not open the episode picker")
        attach(app, named: "episode-picker")
        XCUIRemote.shared.press(.select)
        let player = app.descendants(matching: .any)["player.screen"].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: screenTimeout), "Picking an episode did not open the player")
        Thread.sleep(forTimeInterval: 5)
        attach(app, named: "player-idle")

        // The entry lives in the system transport bar, so it only exists once the bar is up.
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 2)
        // The menu is a system element without an accessibility identifier, so it is addressed by the
        // title the catalog gives it in either app language.
        let qualityEntry = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN %@", ["Качество", "Quality"])
        ).firstMatch
        XCTAssertTrue(
            qualityEntry.waitForExistence(timeout: screenTimeout),
            "The transport bar has no quality entry"
        )
        XCTAssertTrue(
            focusInTransportBar(qualityEntry, in: app),
            "The quality entry is in the transport bar but the remote never focuses it"
        )
        attach(app, named: "transport-quality-focused")

        let current = player.value as? String
        let target = try XCTUnwrap(qualityLabels.first { $0 != current }, "The episode offers a single stream")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "quality-menu-open")

        // The menu is a system popup: its items are addressed through the focus engine (Down walks
        // them) rather than by label, because "1080p" also names an episode card underneath.
        var focusedLabel = focusedElementLabel(in: app)
        for _ in 0 ..< focusAttempts where focusedLabel != target {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.6)
            focusedLabel = focusedElementLabel(in: app)
        }
        XCTAssertEqual(focusedLabel, target, "The quality menu never focused \(target)")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 4)

        XCTAssertEqual(player.value as? String, target, "The player did not switch to \(target)")
        attach(app, named: "quality-switched")
    }

    /// Walks the transport bar until `element` holds focus.
    ///
    /// The bar is a system collection with its own traversal order (timeline, info row, trailing
    /// buttons), so a single direction is not enough: the cycle below is the sequence that reaches the
    /// trailing entries in practice.
    @MainActor
    private func focusInTransportBar(_ element: XCUIElement, in _: XCUIApplication) -> Bool {
        let cycle: [XCUIRemote.Button] = [.right, .down, .left, .up]
        for step in 0 ..< cycle.count * 3 {
            if element.exists, element.hasFocus {
                return true
            }
            XCUIRemote.shared.press(cycle[step % cycle.count])
            Thread.sleep(forTimeInterval: 0.8)
        }
        return element.exists && element.hasFocus
    }

    /// Label of whatever currently holds focus.
    @MainActor
    private func focusedElementLabel(in app: XCUIApplication) -> String? {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == 1"))
        guard !focused.allElementsBoundByIndex.isEmpty else { return nil }
        return focused.firstMatch.label
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
        XCTAssertTrue(
            ShellNavigator.focus("latest.posterCard", in: app),
            "Focus never reached a poster card"
        )

        XCUIRemote.shared.press(.select)
        let detail = app.descendants(matching: .any)["detail.screen"].firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: screenTimeout), "The poster card did not open the detail screen")
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

    /// Puts focus on «Смотреть», which sits next to «Продолжить» and is not necessarily the focused action.
    @MainActor
    private func focusPlayButton(in app: XCUIApplication) {
        for _ in 0 ..< focusAttempts {
            if isFocused(identifier: "detail.playButton", in: app) {
                return
            }
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(
            isFocused(identifier: "detail.playButton", in: app),
            "«Смотреть» cannot be focused with the remote"
        )
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
