import Foundation
import SwiftUI

/// Invisible marker that keeps auto-refresh observable now that no screen shows a freshness caption.
///
/// «Обновлено HH:mm» was debug information in front of a viewer, so it is gone from the UI. The
/// auto-refresh tests still have to prove that a timer fired, which needs the instant somewhere a test can
/// read but a viewer cannot see: a launch argument therefore puts it into the accessibility tree as a
/// one-point transparent element. No production launch passes the argument, and without it the element is
/// not built at all, so it can never reach a real television.
enum RefreshProbe {
    /// Launch argument that exposes the freshness instants to the UI tests.
    static let argument = "-uiTestingRefreshProbe"

    /// Identifier carried by the «Главная» probe.
    static let latestIdentifier = "latest.updatedAt"
    /// Identifier carried by the «Профиль» probe.
    static let profileIdentifier = "profile.updatedAt"

    /// Whether this process should expose probes at all.
    ///
    /// - Parameter arguments: Process arguments; injectable so the rule stays testable.
    /// - Returns: `true` when the UI-test argument is present.
    static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(argument)
    }

    /// Stamp for `identifier`, or `nil` when this launch is not a probe launch.
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier the test looks the element up by.
    ///   - date: Instant the screen last reloaded; `nil` while it has never loaded.
    ///   - arguments: Process arguments; injectable for tests.
    /// - Returns: A stamp the screen can place in an overlay, or `nil` in production.
    static func stamp(
        _ identifier: String,
        date: Date?,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> RefreshProbeStamp? {
        guard let date, isEnabled(arguments: arguments) else { return nil }
        return RefreshProbeStamp(identifier: identifier, date: date)
    }
}

/// The probe element itself: one transparent point that draws nothing and only carries a value.
///
/// `XCUIElement.value` is where the timestamp lives — the label is empty on purpose, so nothing about the
/// clock leaks into VoiceOver either.
struct RefreshProbeStamp: View {
    let identifier: String
    let date: Date

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityIdentifier(identifier)
            .accessibilityValue(Text(verbatim: date.formatted(date: .omitted, time: .standard)))
    }
}
