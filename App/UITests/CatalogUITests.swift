import XCTest

/// End-to-end proof of the «Каталог» tab: the tab loads the catalogue from the live API, a filter
/// changes the result set, and a poster still opens the release detail screen.
final class CatalogUITests: XCTestCase {
    private let loadTimeout: TimeInterval = 60
    private let settle: TimeInterval = 1.2

    @MainActor
    func testCatalogLoadsAndFiltersNarrowTheResult() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        openCatalog(in: app, mode: .catalog)
        attach(app, named: "catalog-grid")

        let count = app.staticTexts["catalog.resultCount"]
        XCTAssertTrue(count.waitForExistence(timeout: loadTimeout), "The catalogue never reported a result count")
        let unfiltered = count.label
        XCTAssertFalse(unfiltered.isEmpty)

        let cards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        XCTAssertTrue(
            cards.firstMatch.waitForExistence(timeout: loadTimeout),
            "The catalogue grid stayed empty"
        )

        chooseGenre(in: app)
        attach(app, named: "catalog-filtered")

        let filtered = UITestWait.forLabelChange(of: count, from: unfiltered, timeout: loadTimeout)
        XCTAssertNotEqual(
            filtered,
            unfiltered,
            "Filtering by genre did not change the result count (still \(filtered))"
        )
        attach(app, named: "catalog-filtered")

        // The chip now carries the chosen genre.
        let genreChip = app.buttons["catalog.genreChip"]
        XCTAssertNotNil(genreChip.value as? String, "The genre chip does not show the active filter")

        // A poster still opens the detail screen.
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: loadTimeout))
        var reachedGrid = false
        for _ in 0 ..< 8 {
            if cards.matching(NSPredicate(format: "hasFocus == 1")).firstMatch.exists {
                reachedGrid = true
                break
            }
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(reachedGrid, "Focus never reached the catalogue grid")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            app.descendants(matching: .any)["detail.screen"].firstMatch.waitForExistence(timeout: 30),
            "Selecting a catalogue poster did not open the detail screen"
        )
    }

    @MainActor
    func testResetClearsTheFilter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        openCatalog(in: app, mode: .catalog)
        let count = app.staticTexts["catalog.resultCount"]
        XCTAssertTrue(count.waitForExistence(timeout: loadTimeout))
        let unfiltered = count.label

        chooseGenre(in: app)
        let filtered = UITestWait.forLabelChange(of: count, from: unfiltered, timeout: loadTimeout)
        XCTAssertNotEqual(filtered, unfiltered, "The genre filter did not apply")

        let reset = app.buttons["catalog.resetButton"]
        XCTAssertTrue(reset.waitForExistence(timeout: 15), "The reset control did not appear")
        XCTAssertTrue(focusReset(in: app), "The remote never reached the reset control")
        XCUIRemote.shared.press(.select)
        let restored = UITestWait.forLabelChange(of: count, from: filtered, timeout: loadTimeout)
        XCTAssertEqual(restored, unfiltered, "Reset did not restore the unfiltered result count")
    }

    @MainActor
    func testSearchTypingNarrowsTheCatalogue() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        openCatalog(in: app, mode: .search)
        let count = app.staticTexts["catalog.resultCount"]
        XCTAssertTrue(count.waitForExistence(timeout: loadTimeout))
        let unfiltered = count.label

        // «Поиск» has no chip row (ADR 0030), so the field is the only control above the grid: walk a
        // little until it holds focus instead of assuming Down-then-Up lands on it.
        let field = app.descendants(matching: .any)["catalog.searchField"].firstMatch
        for direction in [XCUIRemote.Button.up, .down, .up, .down, .right] where !field.hasFocus {
            XCUIRemote.shared.press(direction)
            Thread.sleep(forTimeInterval: 0.8)
        }
        XCTAssertTrue(field.hasFocus, "The search field did not take focus")

        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Select on the search field did not raise the keyboard")
        app.typeText("маска")
        Thread.sleep(forTimeInterval: 2)
        // Menu closes the keyboard and leaves the screen where it is.
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 5)

        XCTAssertNotEqual(count.label, unfiltered, "Typing a query did not change the result count")
        XCTAssertEqual(field.value as? String, "маска", "The search field lost the typed query")
        attach(app, named: "catalog-search")
    }

    // MARK: Helpers

    @MainActor
    private func openCatalog(in app: XCUIApplication, mode: ShellSection) {
        let marker = mode == .search ? "catalog.searchField" : "catalog.genreChip"
        XCTAssertTrue(ShellNavigator.open(mode, in: app), "The sidebar never reached \(mode)")
        XCTAssertTrue(
            app.descendants(matching: .any)[marker].firstMatch.waitForExistence(timeout: loadTimeout),
            "\(mode) never opened its screen"
        )
    }

    /// Opens the genre picker, moves off «Любой» onto a real genre and confirms it.
    @MainActor
    private func chooseGenre(in app: XCUIApplication) {
        XCTAssertTrue(focusChip("catalog.genreChip", in: app), "The remote never reached the genre chip")
        XCUIRemote.shared.press(.select)
        let picker = app.descendants(matching: .any)["filterPicker.screen"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "The genre chip did not open its picker")
        for _ in 0 ..< 8 where focusedOptionIdentifier(in: app) == "filterPicker.option.any" {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertNotEqual(
            focusedOptionIdentifier(in: app),
            "filterPicker.option.any",
            "The picker never moved off «Любой», so the filter could not change"
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(
            UITestWait.forDisappearance(of: picker, timeout: 10),
            "Choosing a genre did not close the picker"
        )
    }

    /// The accessibility identifier of the option that holds focus inside the filter picker, if any.
    @MainActor
    private func focusedOptionIdentifier(in app: XCUIApplication) -> String? {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == 1 AND identifier BEGINSWITH %@", "filterPicker.option."))
            .firstMatch
        return element.exists ? element.identifier : nil
    }

    @MainActor
    private func focusChip(_ identifier: String, in app: XCUIApplication) -> Bool {
        let chip = app.buttons[identifier]
        guard chip.waitForExistence(timeout: loadTimeout) else { return false }
        // The screen opens on the search field; Down drops into the chip row, where the engine picks
        // the chip under the field's centre — usually not the first one — so walk that row.
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: 0.8)
        for _ in 0 ..< 6 {
            if chip.hasFocus {
                return true
            }
            XCUIRemote.shared.press(.left)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return chip.hasFocus
    }

    @MainActor
    private func focusReset(in app: XCUIApplication) -> Bool {
        let reset = app.buttons["catalog.resetButton"]
        guard reset.waitForExistence(timeout: 15) else { return false }
        for _ in 0 ..< 10 {
            if reset.hasFocus {
                return true
            }
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
        }
        return reset.hasFocus
    }

    @MainActor
    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
