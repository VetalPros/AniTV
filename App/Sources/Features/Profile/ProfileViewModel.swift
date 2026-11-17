import AniLibertyKit
import Foundation
import Observation
import os

/// Owns the «Профиль» tab: the pairing handshake, the signed-in profile with favourites, and sign-out.
///
/// The session token never leaves this type. It is read from the ``AuthTokenStoring`` store, handed to
/// the client as a parameter and dropped on sign-out; it is never logged, never stored anywhere else
/// and never exposed to a view.
@MainActor
@Observable
final class ProfileViewModel {
    /// What the screen shows. The token is deliberately not part of it.
    enum State {
        case loading
        case pairing
        case signedIn
        /// The stored token was rejected by the service: keep it out of the way, but do not lose the
        /// account silently — the viewer decides when to pair the TV again.
        case expired
        case failed(AniLibertyError)
    }

    /// One code the screen asked the service for, kept so an older confirmation still logs the TV in.
    private struct PendingPairing {
        let deviceID: String
        let code: String
        let expiresAt: Date
    }

    private static let logger = Logger(subsystem: "tv.anitv.client", category: "Profile")

    /// How often the pairing code is polled while it is alive.
    private static let pollInterval: Duration = .seconds(5)
    /// Granularity of the countdown.
    private static let tickInterval: Duration = .milliseconds(500)

    private(set) var state: State = .loading
    /// Code the viewer has to confirm, `nil` while a new one is being requested.
    private(set) var challenge: OTPChallenge?
    private(set) var profile: UserProfile?
    private(set) var favorites: [Release] = []
    private(set) var isPagingFavorites = false
    private(set) var favoritesError: AniLibertyError?
    private(set) var hasMoreFavorites = false
    /// Seconds left on the pairing code, refreshed by the countdown ticker.
    private(set) var secondsRemaining = 0
    /// True between "the code was accepted" and "the profile is on screen".
    private(set) var isSigningIn = false
    /// Reason the last pairing attempt failed, shown next to the code without leaving the screen.
    private(set) var pairingError: AniLibertyError?
    /// When the profile and the favourites were last brought up to date.
    private(set) var updatedAt: Date?

    @ObservationIgnored private let client: AniLibertyClient
    @ObservationIgnored private let tokenStore: AuthTokenStoring
    @ObservationIgnored private var deviceID: String
    /// Every (device id, code) pair this screen asked for and that has not expired yet.
    ///
    /// «Обновить код» has to rotate the device id — the service answers a repeated request for the same
    /// id with the same pending code — and rotating orphans whatever the viewer may already be typing.
    /// Polling the whole set means a confirmation of the previous code still lets this TV in.
    @ObservationIgnored private var pendingPairings: [PendingPairing] = []
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var favoritesPage = 0
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private lazy var refreshLoop = RefreshLoop(
        policy: AutoRefreshPolicy.make(kind: .favorites)
    ) { [weak self] in
        await self?.refreshSignedInContent()
    }

    init(
        client: AniLibertyClient = AniLibertyClient(),
        tokenStore: AuthTokenStoring = AuthTokenStoreFactory.make(),
        deviceID: String = DeviceIdentity.current()
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.deviceID = deviceID
    }

    // MARK: Lifecycle

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh()
    }

    // MARK: Auto-refresh

    /// Tells the loop whether the «Профиль» tab is on display and the app is in the foreground.
    ///
    /// Coming back to the tab re-reads the profile and the favourites at once — that is what makes a
    /// release favourited on the website appear without restarting the app.
    func setVisible(_ visible: Bool) async {
        await refreshLoop.setVisible(visible)
    }

    /// Stops the timer, e.g. when the app goes to the background or the session ends.
    func stopAutoRefresh() {
        refreshLoop.stop()
    }

    /// Re-reads the profile and the first page of favourites without disturbing what is on screen.
    ///
    /// Failures keep the current grid: nobody asked for this refresh, so a hiccup must not turn a working
    /// screen into an error. A dead token, on the other hand, is a state change and is surfaced.
    private func refreshSignedInContent() async {
        guard case .signedIn = state, let token, let currentProfile = profile else { return }
        do {
            let profile = try await client.profile(token: token)
            guard !Task.isCancelled else { return }
            self.profile = profile
            if profile.id != currentProfile.id {
                // A different account: the favourites have to start over.
                favoritesPage = 0
                hasMoreFavorites = false
            }
            let page = try await client.favorites(token: token, page: 1)
            guard !Task.isCancelled else { return }
            favorites = page.releases
            favoritesPage = page.currentPage
            hasMoreFavorites = page.hasNextPage
            favoritesError = nil
            updatedAt = .now
            Self.logger.info("Refreshed profile with \(page.releases.count, privacy: .public) favourites")
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            if Self.isUnauthorized(mapped) {
                stopAutoRefresh()
                state = .expired
                return
            }
            Self.logger
                .error("Profile refresh failed: \(String(describing: mapped), privacy: .public)")
        }
    }

    /// Re-reads the stored token and rebuilds the screen from it.
    func refresh() async {
        stopPairing()
        stopAutoRefresh()
        state = .loading
        let stored = try? await tokenStore.load()
        guard let stored, !stored.isEmpty else {
            token = nil
            await startPairing()
            return
        }
        token = stored
        await loadProfile(with: stored)
    }

    // MARK: Signed-in state

    private func loadProfile(with token: String) async {
        do {
            let profile = try await client.profile(token: token)
            guard !Task.isCancelled else { return }
            self.profile = profile
            state = .signedIn
            updatedAt = .now
            Self.logger.info(
                "Profile loaded, avatar=\(profile.avatarURL != nil, privacy: .public), favourites pagination starts"
            )
            await loadFavorites(reset: true)
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            if Self.isUnauthorized(mapped) {
                // A rejected token used to be forgotten on the spot, which looked like the account
                // disappearing by itself. It now stays until the viewer asks to pair the TV again.
                Self.logger
                    .error("Stored token was rejected: \(String(describing: mapped), privacy: .public)")
                stopAutoRefresh()
                state = .expired
                return
            }
            Self.logger.error("Profile request failed: \(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }

    /// Forgets a rejected token and asks the service for a fresh pairing code.
    func reconnect() async {
        await forgetToken()
        await startPairing()
    }

    /// Ends the session: the token leaves the Keychain, the refresh loop stops and the screen returns to
    /// pairing.
    func signOut() async {
        stopAutoRefresh()
        await forgetToken()
        profile = nil
        favorites = []
        favoritesError = nil
        favoritesPage = 0
        hasMoreFavorites = false
        await startPairing()
    }

    private func forgetToken() async {
        try? await tokenStore.delete()
        token = nil
    }

    // MARK: Favourites

    func loadFavorites(reset: Bool) async {
        guard let token else { return }
        if reset {
            favoritesPage = 0
            favorites = []
            hasMoreFavorites = false
        }
        favoritesError = nil
        let nextPage = favoritesPage + 1
        do {
            let page = try await client.favorites(token: token, page: nextPage)
            guard !Task.isCancelled else { return }
            favoritesPage = page.currentPage
            favorites.append(contentsOf: page.releases)
            hasMoreFavorites = page.hasNextPage
            Self.logger.info("Favourites page \(page.currentPage, privacy: .public) loaded")
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            if Self.isUnauthorized(mapped) {
                await forgetToken()
                await startPairing()
                return
            }
            favoritesError = mapped
            Self.logger.error("Favourites request failed: \(String(describing: mapped), privacy: .public)")
        }
    }

    func loadMoreFavorites() async {
        guard hasMoreFavorites, !isPagingFavorites else { return }
        isPagingFavorites = true
        await loadFavorites(reset: false)
        isPagingFavorites = false
    }

    // MARK: Pairing

    /// Requests a fresh code, replacing the previous one.
    ///
    /// The request goes out on behalf of a rotated device id: the service hands back the pending code when
    /// the same device id asks again, so without the rotation the button would appear to do nothing.
    func requestNewCode() async {
        stopPairing()
        deviceID = DeviceIdentity.rotate()
        await startPairing()
    }

    private func startPairing() async {
        state = .pairing
        challenge = nil
        pairingError = nil
        secondsRemaining = 0
        do {
            let challenge = try await client.requestOTP(deviceID: deviceID)
            guard !Task.isCancelled else { return }
            self.challenge = challenge
            rememberPairing(code: challenge.code, deviceID: deviceID, expiresAt: challenge.expiresAt)
            secondsRemaining = Int(challenge.secondsRemaining(at: .now).rounded())
            // The code is shown on screen and is single-use, so logging it is safe and it is the only way
            // to tell which code the app is actually polling when a confirmation "does not arrive".
            Self.logger.info(
                "Pairing code requested: \(challenge.code, privacy: .public), expires in \(self.secondsRemaining, privacy: .public)s"
            )
            pollUntilAccepted()
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            Self.logger.error("OTP request failed: \(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }

    /// Polls `loginWithOTP` while the code is alive: every answer other than a token means "keep
    /// waiting", and `otpNotAccepted` is the expected one.
    private func pollUntilAccepted() {
        stopPairing()
        pairingTask = Task { [weak self] in
            var ticksSincePoll = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, let challenge else { return }
                secondsRemaining = max(0, Int(challenge.secondsRemaining(at: .now).rounded()))
                if challenge.isExpired(at: .now), livePairings().isEmpty {
                    secondsRemaining = 0
                    return
                }
                ticksSincePoll += 1
                guard ticksSincePoll * 500 >= Int(Self.pollInterval.components.seconds * 1000) else { continue }
                ticksSincePoll = 0
                for pairing in livePairings() where await attemptLogin(code: pairing.code, deviceID: pairing.deviceID) {
                    return
                }
            }
        }
    }

    @discardableResult
    private func attemptLogin(code: String, deviceID: String) async -> Bool {
        do {
            let token = try await client.loginWithOTP(code: code, deviceID: deviceID)
            guard !Task.isCancelled else { return false }
            do {
                try await tokenStore.save(token)
            } catch {
                // The token cannot be stored: the session will not survive a relaunch, and saying so is
                // better than a silent "signed in until you restart".
                Self.logger.error("Token could not be saved: \(String(describing: error), privacy: .public)")
            }
            self.token = token
            stopPairing()
            challenge = nil
            pairingError = nil
            Self.logger.info("Pairing accepted, profile is loading")
            isSigningIn = true
            // Load the profile from a fresh task: the polling task that got here is cancelled a few lines
            // above, and a cancelled task cannot start the URLSession child that the request needs — the
            // call then never returns and the screen keeps the pairing panel (observed in the app, not in
            // tests, which is why this is spelled out).
            Task { [weak self] in
                await self?.loadProfile(with: token)
                self?.isSigningIn = false
            }
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            let mapped = AniLibertyError.mapped(error)
            if case .otpNotAccepted = mapped {
                return false
            }
            if case .cancelled = mapped {
                return false
            }
            pairingError = mapped
            Self.logger.error("Pairing poll failed: \(String(describing: mapped), privacy: .public)")
            return false
        }
    }

    // MARK: Pending codes

    /// Keeps the last few requested codes; anything expired is dropped on the way.
    private func rememberPairing(code: String, deviceID: String, expiresAt: Date) {
        pendingPairings.removeAll { $0.expiresAt <= .now || $0.code == code }
        pendingPairings.append(PendingPairing(deviceID: deviceID, code: code, expiresAt: expiresAt))
        if pendingPairings.count > 3 {
            pendingPairings.removeFirst(pendingPairings.count - 3)
        }
    }

    /// Codes still worth polling: the service only binds a code for a while.
    private func livePairings() -> [PendingPairing] {
        pendingPairings.removeAll { $0.expiresAt <= .now }
        return pendingPairings
    }

    private func stopPairing() {
        pairingTask?.cancel()
        pairingTask = nil
    }

    // MARK: Helpers

    private static func isUnauthorized(_ error: AniLibertyError) -> Bool {
        if case let .httpStatus(status) = error {
            return status == 401 || status == 403
        }
        return false
    }
}
