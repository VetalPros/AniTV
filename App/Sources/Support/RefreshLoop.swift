import Foundation
import Observation

/// Drives one screen's auto-refresh: a single timer while the screen is visible, and an immediate
/// reload when the screen becomes visible again after being away for longer than the policy allows.
///
/// Both auto-refreshing screens share this type, so there is exactly one implementation of "when do we
/// reload" in the app. Nothing runs while the screen is hidden or the app is in the background: the loop
/// is cancelled, not paused, so a TV left on a shelf makes no requests at all.
@MainActor
final class RefreshLoop {
    private let policy: AutoRefreshPolicy
    private let refresh: @MainActor () async -> Void

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hiddenAt: Date?

    /// Creates a loop.
    ///
    /// - Parameters:
    ///   - policy: Cadence for this screen.
    ///   - refresh: Work to perform on every reload; it must be idempotent and must not clear what is on
    ///     screen unless the content really changed.
    init(policy: AutoRefreshPolicy, refresh: @escaping @MainActor () async -> Void) {
        self.policy = policy
        self.refresh = refresh
    }

    deinit {
        task?.cancel()
    }

    /// Whether the timer is currently running.
    var isRunning: Bool {
        task != nil
    }

    /// Brings the loop in line with the screen's visibility.
    ///
    /// - Parameter visible: `true` when the screen is on display and the app is in the foreground.
    func setVisible(_ visible: Bool) async {
        guard visible else {
            stop()
            return
        }
        guard task == nil else { return }

        let away = hiddenAt.map { Date().timeIntervalSince($0) } ?? .infinity
        hiddenAt = nil
        if away >= policy.staleAfter {
            await refresh()
            guard task == nil else { return }
        }
        start()
    }

    /// Cancels the timer without touching the visible flag; used on teardown.
    func stop() {
        task?.cancel()
        task = nil
        hiddenAt = .now
    }

    private func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: policy.interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }
}
