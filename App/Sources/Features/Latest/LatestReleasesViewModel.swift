import AniLibertyKit
import Foundation
import Observation
import os

/// Drives the "Новинки" screen: one request per activation, background refreshes while the tab is on
/// display, explicit reload on failure.
@MainActor
@Observable
final class LatestReleasesViewModel {
    /// Every state the screen can be in. `empty` is distinct from `loaded([])` on purpose: the
    /// catalogue being empty is a message, not a grid with nothing in it.
    enum State {
        case idle
        case loading
        case loaded([Release])
        case empty
        case failed(AniLibertyError)
    }

    private static let logger = Logger(subsystem: "tv.anitv.client", category: "Latest")

    private(set) var state: State = .idle
    /// When the grid was last brought up to date; drives the «Обновлено 15:42» caption.
    private(set) var updatedAt: Date?

    @ObservationIgnored private let client: AniLibertyClient
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private lazy var refreshLoop = RefreshLoop(
        policy: AutoRefreshPolicy.make(kind: .latest)
    ) { [weak self] in
        await self?.refreshIfVisible()
    }

    init(client: AniLibertyClient = AniLibertyClient()) {
        self.client = client
    }

    // MARK: Auto-refresh

    /// Tells the loop whether the tab is on display and the app is in the foreground.
    func setVisible(_ visible: Bool) async {
        await refreshLoop.setVisible(visible)
    }

    /// Stops the timer, e.g. when the scene goes to the background.
    func stopAutoRefresh() {
        refreshLoop.stop()
    }

    /// Reloads without disturbing what the viewer is looking at.
    ///
    /// The loading state is only entered when there is nothing on screen yet; an already filled grid is
    /// updated in place, and an unchanged list keeps its identity so focus and scroll survive.
    private func refreshIfVisible() async {
        guard case let .loaded(current) = state else {
            if case .empty = state {
                await refreshInPlace(current: [])
            }
            return
        }
        await refreshInPlace(current: current)
    }

    private func refreshInPlace(current: [Release]) async {
        do {
            let releases = try await client.latestReleases()
            guard !Task.isCancelled else { return }
            updatedAt = .now
            if releases.map(\.id) == current.map(\.id), case .loaded = state {
                // Same list: keep the exact value that is on screen, so nothing re-renders and focus
                // stays where the viewer left it.
                Self.logger.info("Latest releases unchanged (\(releases.count, privacy: .public))")
                return
            }
            state = releases.isEmpty ? .empty : .loaded(releases)
            Self.logger.info("Refreshed \(releases.count, privacy: .public) latest releases")
        } catch {
            guard !Task.isCancelled else { return }
            // A background refresh never replaces a working grid with an error screen: the viewer did
            // not ask for anything, so the old list simply stays.
            Self.logger
                .error("Latest refresh failed: \(String(describing: AniLibertyError.mapped(error)), privacy: .public)")
        }
    }

    /// Loads once per app run; subsequent tab visits reuse the loaded grid instead of refetching.
    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await load()
    }

    /// Cancels any in-flight request and starts a fresh one (the retry action).
    func reload() {
        reloadTask?.cancel()
        reloadTask = Task { await load() }
    }

    private func load() async {
        state = .loading
        do {
            let releases = try await client.latestReleases()
            guard !Task.isCancelled else { return }
            updatedAt = .now
            state = releases.isEmpty ? .empty : .loaded(releases)
            Self.logger.info("Loaded \(releases.count, privacy: .public) latest releases")
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            Self.logger.error("Latest releases failed: \(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }
}
