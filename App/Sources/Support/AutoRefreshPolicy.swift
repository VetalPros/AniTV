import Foundation

/// One place that decides how often screens refresh themselves, and how long "away" has to be before
/// coming back triggers an immediate reload.
///
/// Both auto-refreshing screens take their numbers from here, so the cadence is a product decision
/// instead of two timers that happen to agree. UI tests need to observe a real refresh within seconds,
/// so the intervals are injectable through launch arguments; production never passes them.
struct AutoRefreshPolicy: Sendable {
    /// How often a screen that is on display reloads its content.
    let interval: Duration
    /// How long the screen must have been hidden before becoming visible again forces a reload.
    let staleAfter: TimeInterval

    /// Which screen the policy is for; only the interval differs.
    enum Kind: Sendable {
        case latest
        case favorites
    }

    /// Launch argument that overrides ``interval`` for both screens, in seconds.
    static let intervalArgument = "-uiTestingRefreshInterval"
    /// Launch argument that overrides ``staleAfter``, in seconds.
    static let staleAfterArgument = "-uiTestingStaleAfter"

    /// Five minutes for «Новинки»: a feed of fresh episodes does not change faster than that, the API
    /// document asks clients to be polite, and one request per five minutes per TV is invisible for the
    /// service while still making the grid feel live.
    static let latestInterval: Duration = .seconds(300)
    /// Three minutes for favourites: the interesting trigger there is the viewer adding a title on the
    /// site and coming back, which the visibility rule already covers; the timer only keeps a screen
    /// left open in front of somebody current.
    static let favoritesInterval: Duration = .seconds(180)
    /// A minute away is enough for the content behind a tab switch to have moved on; shorter and a quick
    /// look at «Каталог» would refetch for nothing.
    static let defaultStaleAfter: TimeInterval = 60

    /// Policy for a screen.
    ///
    /// - Parameters:
    ///   - kind: Screen the policy is for.
    ///   - arguments: Process arguments; the UI-test overrides are honoured when present.
    /// - Returns: The resolved policy.
    static func make(kind: Kind, arguments: [String] = ProcessInfo.processInfo.arguments) -> AutoRefreshPolicy {
        let production = kind == .latest ? latestInterval : favoritesInterval
        let interval = seconds(for: intervalArgument, in: arguments)
            .map { Duration.seconds($0) } ?? production
        let staleAfter = seconds(for: staleAfterArgument, in: arguments) ?? defaultStaleAfter
        return AutoRefreshPolicy(interval: interval, staleAfter: staleAfter)
    }

    /// Value that follows `flag` in the argument list, when it is a positive number.
    private static func seconds(for flag: String, in arguments: [String]) -> TimeInterval? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1),
              let value = TimeInterval(arguments[index + 1]), value > 0
        else {
            return nil
        }
        return value
    }
}
