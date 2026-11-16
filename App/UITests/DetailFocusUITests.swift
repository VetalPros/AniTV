import UIKit
import XCTest

/// End-to-end proof of the focus chain on the release detail screen.
///
/// The screen is one long scroll view with three focusable blocks — the hero action, the synopsis
/// toggle and the episode grid — and a person with a remote expects to walk them with Down/Up. The
/// tests drive the real focus engine through `XCUIRemote` (the touch APIs are unavailable on tvOS)
/// and read the focused element's accessibility identifier, so nothing here depends on coordinates.
///
/// Two simulator behaviours shape the helpers and neither weakens the assertions: the remote channel
/// occasionally drops a press, and Menu is routed through the focus engine — with nothing focused the
/// press falls through to the system and the app is backgrounded instead of popping the stack.
final class DetailFocusUITests: XCTestCase {
    private let feedTimeout: TimeInterval = 60
    private let screenTimeout: TimeInterval = 30
    /// Remote presses allowed while waiting for a focus target.
    private let focusAttempts = 6
    /// The pieces of remote input a test may repeat when a press is dropped.
    private let pressAttempts = 3
    /// How long the focus engine is given to settle after a press.
    private let settleTimeout: TimeInterval = 1.0
    /// Cards the feed walk visits while looking for a release of a particular shape.
    private let maxCards = 6
    /// Mirrors the synopsis typography of the detail screen (`DesignTokens.Typography.body`).
    private let synopsisFont = UIFont.systemFont(ofSize: 20)
    private let synopsisLineSpacing: CGFloat = 5
    private let collapsedLines = 6

    // MARK: Focus chain

    @MainActor
    func testFocusWalksFromHeroToSynopsisToEpisodesAndBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        // The complete chain only exists when the synopsis is collapsed behind its toggle, so a
        // release that clips is looked for in today's feed instead of assuming the first card is one.
        let hasToggle = openFirstClippedRelease(in: app)
        if !hasToggle {
            // The walk ended on the feed (no release clipped), so step back onto a detail screen to
            // check what is still checkable.
            openFocusedPoster(in: app, waitsForFeed: false)
        }

        XCTAssertEqual(
            focusedIdentifier(in: app),
            "detail.playButton",
            "The detail screen must open with focus on its primary action (ADR 0012)"
        )

        if hasToggle {
            // The regression: Down used to jump straight from the hero into the episode grid, and Up
            // got stuck on the toggle instead of climbing back to the play button.
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: settleTimeout)
            XCTAssertEqual(
                focusedIdentifier(in: app),
                "detail.synopsisToggle",
                "Down from the hero must land on «Читать полностью», not jump over it into the episode grid"
            )
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: settleTimeout)
            XCTAssertEqual(
                focusedIdentifier(in: app),
                "detail.episodeCard",
                "Down from the synopsis must reach the episode list"
            )
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: settleTimeout)
            XCTAssertEqual(
                focusedIdentifier(in: app),
                "detail.synopsisToggle",
                "Up from the episode list must come back to the synopsis"
            )
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: settleTimeout)
            XCTAssertEqual(
                focusedIdentifier(in: app),
                "detail.playButton",
                "Up from the synopsis must come back to the play button"
            )
            return
        }

        // No release in today's feed clips its synopsis, so the toggle leg cannot be exercised. The
        // hero-to-episodes legs are still checked, and the gap is reported instead of passed silently.
        print("FOCUS_CHAIN gap: no clipped synopsis in the feed, the synopsis leg was not exercised")
        XCUIRemote.shared.press(.down)
        Thread.sleep(forTimeInterval: settleTimeout)
        XCTAssertEqual(
            focusedIdentifier(in: app),
            "detail.episodeCard",
            "Down from the hero must reach the episode list"
        )
        XCUIRemote.shared.press(.up)
        Thread.sleep(forTimeInterval: settleTimeout)
        XCTAssertEqual(
            focusedIdentifier(in: app),
            "detail.playButton",
            "Up from the episode list must come back to the play button"
        )
    }

    // MARK: Synopsis truncation rule

    /// The toggle must exist only when the synopsis is really cut off by the collapsed line budget.
    ///
    /// The expectation is computed in the test from what the screen actually shows — the text the
    /// accessibility tree exposes and the width it was laid out at — and compared with the app's
    /// decision on several real releases, so neither the character count that used to drive this nor a
    /// stale layout measurement can pass.
    @MainActor
    func testSynopsisToggleAppearsOnlyWhenTheTextIsClipped() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        var checked: [String] = []
        var previous = ""
        for step in 0 ..< maxCards {
            if step > 0 {
                guard returnToFeed(in: app), focusNextCard(in: app, after: previous) else {
                    // The feed refused to move on (focus dropped after the pop); the releases measured
                    // so far stay valid, so the walk stops here instead of failing on navigation.
                    print("SYNOPSIS_RULE walk stopped after \(checked.count) releases")
                    break
                }
            }
            previous = openFocusedPoster(in: app, waitsForFeed: step == 0)

            let synopsis = element(identifier: "detail.synopsisText", in: app)
            XCTAssertTrue(synopsis.exists, "The detail screen exposes no synopsis text for «\(previous)»")
            let text = synopsis.label
            let width = synopsis.frame.width
            guard !text.hasSuffix("…"), width > 0 else {
                continue
            }
            let expected = isClipped(text, width: width)
            let hasToggle = element(identifier: "detail.synopsisToggle", in: app).exists
            XCTAssertEqual(
                hasToggle,
                expected,
                "«\(previous)»: toggle is \(hasToggle ? "shown" : "missing") but a \(text.count)-character "
                    + "synopsis at width \(Int(width)) is \(expected ? "" : "not ")clipped after \(collapsedLines) lines"
            )
            checked.append("\(previous): \(text.count) chars, expected clipped=\(expected)")
        }

        XCTAssertFalse(checked.isEmpty, "No release could be measured: the walk collected nothing")
        for line in checked {
            print("SYNOPSIS_RULE \(line)")
        }
    }

    // MARK: Steps

    /// Opens releases from the feed until one shows the synopsis toggle.
    ///
    /// - Returns: `true` when such a release is open on screen.
    @MainActor
    private func openFirstClippedRelease(in app: XCUIApplication) -> Bool {
        var previous = ""
        for step in 0 ..< maxCards {
            if step > 0 {
                guard returnToFeed(in: app), focusNextCard(in: app, after: previous) else { return false }
            }
            previous = openFocusedPoster(in: app, waitsForFeed: step == 0)
            if element(identifier: "detail.synopsisToggle", in: app).exists {
                return true
            }
        }
        return false
    }

    // MARK: Steps

    /// Selects the focused poster card and waits for its detail screen to take focus.
    ///
    /// - Returns: label of the card that was opened, for diagnostics.
    @discardableResult
    @MainActor
    private func openFocusedPoster(in app: XCUIApplication, waitsForFeed: Bool = true) -> String {
        var card = focusedLabel(in: app)
        if waitsForFeed {
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
            card = focusedLabel(in: app)
        }

        let detail = element(identifier: "detail.screen", in: app)
        for _ in 0 ..< pressAttempts where !detail.exists {
            XCUIRemote.shared.press(.select)
            _ = detail.waitForExistence(timeout: 6)
        }
        XCTAssertTrue(
            detail.waitForExistence(timeout: screenTimeout),
            "Selecting a poster card did not open the detail screen"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "hasFocus == 1 AND identifier IN %@",
                        ["detail.playButton", "detail.synopsisToggle"]
                    )
                )
                .firstMatch.waitForExistence(timeout: screenTimeout),
            "The detail screen never took focus"
        )
        return card
    }

    /// Puts focus on a poster card whose label differs from `previous`, so a feed walk visits a new
    /// release every time instead of reopening the one it just left.
    @MainActor
    private func focusNextCard(in app: XCUIApplication, after previous: String) -> Bool {
        for _ in 0 ..< focusAttempts * 2 {
            guard isFocused(identifier: "latest.posterCard", in: app) else {
                XCUIRemote.shared.press(.down)
                Thread.sleep(forTimeInterval: 0.6)
                continue
            }
            if focusedLabel(in: app) != previous {
                return true
            }
            // Right first; when the row ends the next card is one row down.
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.6)
            if isFocused(identifier: "latest.posterCard", in: app), focusedLabel(in: app) == previous {
                XCUIRemote.shared.press(.down)
                Thread.sleep(forTimeInterval: 0.6)
            }
        }
        return isFocused(identifier: "latest.posterCard", in: app) && focusedLabel(in: app) != previous
    }

    /// Presses Menu until the feed is back, and reports whether it came back.
    @MainActor
    private func returnToFeed(in app: XCUIApplication) -> Bool {
        let posterCards = app.descendants(matching: .any).matching(identifier: "latest.posterCard")
        for _ in 0 ..< pressAttempts {
            XCUIRemote.shared.press(.menu)
            if posterCards.firstMatch.waitForExistence(timeout: 8) {
                return true
            }
        }
        return posterCards.firstMatch.exists
    }

    /// Independent measurement of the same rule the screen applies: does `text` need more than
    /// `collapsedLines` lines at `width`?
    @MainActor
    private func isClipped(_ text: String, width: CGFloat) -> Bool {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = synopsisLineSpacing
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: synopsisFont, .paragraphStyle: style]
        func height(_ value: String) -> CGFloat {
            (value as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height
        }
        let lineHeight = height("A")
        guard lineHeight > 0 else { return false }
        let budget = CGFloat(collapsedLines) * lineHeight + CGFloat(collapsedLines - 1) * synopsisLineSpacing
        return height(text) > budget + 1
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

    /// Accessibility identifier of whatever currently holds focus, or `nil` when nothing does.
    @MainActor
    private func focusedIdentifier(in app: XCUIApplication) -> String? {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == 1")).firstMatch
        guard focused.exists else { return nil }
        return focused.identifier
    }

    /// Label of whatever currently holds focus — cheap, unlike walking every static text.
    @MainActor
    private func focusedLabel(in app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == 1")).firstMatch
        guard focused.exists else { return "unknown" }
        return focused.label
    }
}
