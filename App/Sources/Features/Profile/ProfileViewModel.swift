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

    init(
        client: AniLibertyClient = AniLibertyClient(),
        tokenStore: AuthTokenStoring = KeychainTokenStore(),
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

    /// Re-reads the stored token and rebuilds the screen from it.
    func refresh() async {
        stopPairing()
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
            Self.logger.info("Profile loaded, favourites pagination starts")
            await loadFavorites(reset: true)
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            if Self.isUnauthorized(mapped) {
                // A dead token is not an error screen: forget it and pair this TV again.
                Self.logger.info("Stored token was rejected, falling back to pairing")
                await forgetToken()
                await startPairing()
                return
            }
            Self.logger.error("Profile request failed: \(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }

    /// Ends the session: the token leaves the Keychain and the screen returns to pairing.
    func signOut() async {
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
            try? await tokenStore.save(token)
            self.token = token
            stopPairing()
            challenge = nil
            pairingError = nil
            Self.logger.info("Pairing accepted, profile is loading")
            isSigningIn = true
            await loadProfile(with: token)
            isSigningIn = false
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
