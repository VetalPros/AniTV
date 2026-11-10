import AniLibertyKit
import Foundation
import Observation
import os

/// Drives the "Новинки" screen: one request per activation, explicit reload on failure.
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

    @ObservationIgnored private let client: AniLibertyClient
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    init(client: AniLibertyClient = AniLibertyClient()) {
        self.client = client
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
