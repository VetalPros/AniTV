import Foundation
import os

/// Account endpoints: OTP pairing, password login, the profile and favourites.
///
/// The token always arrives as a parameter, never as actor state, so signing out is
/// forgetting it in the ``AuthTokenStoring`` store rather than resetting the client.
public extension AniLibertyClient {
    private static let accountLogger = Logger(subsystem: "tv.anitv.client", category: "Account")

    /// Requests a one-time pairing code for a TV device.
    ///
    /// `POST /api/v1/accounts/otp/get` is anonymous: it takes the device identifier and
    /// returns a code the user confirms in an already signed-in client or on the site.
    ///
    /// - Parameter deviceID: Stable identifier of this device; the same value must be
    ///   used when polling ``loginWithOTP(code:deviceID:)``.
    /// - Returns: The code to display together with its lifetime.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func requestOTP(deviceID: String) async throws -> OTPChallenge {
        let body = try Self.encode(OTPRequestBody(deviceID: deviceID))
        let request = try makeRequest(
            path: "\(ServiceURL.apiPrefix)/accounts/otp/get",
            method: "POST",
            body: body
        )
        let (data, status) = try await perform(request, over: accountTransport)
        guard (200 ..< 300).contains(status) else {
            throw AniLibertyError.httpStatus(status)
        }
        return try decode(OTPChallenge.self, from: data)
    }

    /// Polls the pairing endpoint until the user has confirmed the code.
    ///
    /// While the code is still waiting for confirmation the service answers
    /// `POST /api/v1/accounts/otp/login` with **HTTP 500** and `{"message":"Server Error"}`
    /// — an API wart, not a failure of this kit. That status is mapped to
    /// ``AniLibertyError/otpNotAccepted`` so the caller can keep waiting, while a token
    /// remains the only success signal.
    ///
    /// The code is sent as an integer when it consists of digits, as the API expects;
    /// anything else is forwarded as a string and rejected by the service with HTTP 422.
    ///
    /// - Parameters:
    ///   - code: Code from ``OTPChallenge/code``.
    ///   - deviceID: The same device identifier that requested the code.
    /// - Returns: Session token to store in ``AuthTokenStoring``.
    /// - Throws: ``AniLibertyError/otpNotAccepted`` while waiting, `AniLibertyError`
    ///   otherwise.
    func loginWithOTP(code: String, deviceID: String) async throws -> String {
        let body = try Self.encode(OTPLoginBody(code: code, deviceID: deviceID))
        let request = try makeRequest(
            path: "\(ServiceURL.apiPrefix)/accounts/otp/login",
            method: "POST",
            body: body
        )

        Self.accountLogger.debug(
            "otp/login body: \(request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<none>", privacy: .public)"
        )
        let (data, status) = try await perform(request, over: accountTransport)
        if (200 ..< 300).contains(status) {
            return try decode(TokenResponse.self, from: data).token
        }
        // A code that nobody has accepted yet is refused with whatever the service feels like that day:
        // 500 `{"message": "Server Error"}` from a request made with a bare `curl`, 403
        // `{"message": "This action is unauthorized."}` from the app's URLSession (which carries the
        // cookies of the `otp/get` call). Both mean "keep waiting". A 422 is different — it is the
        // service rejecting the code itself — and stays a real error so the screen can say so.
        let refusal = String(bytes: data.prefix(120), encoding: .utf8) ?? ""
        Self.accountLogger.debug("otp/login refused with \(status, privacy: .public): \(refusal, privacy: .public)")
        if status == 403 || status == 500 {
            throw AniLibertyError.otpNotAccepted
        }
        throw AniLibertyError.httpStatus(status)
    }

    /// Signs in with a login and a password.
    ///
    /// `POST /api/v1/accounts/users/auth/login` returns `{ "token": … }`. The TV flow uses
    /// OTP pairing instead, because typing a password with a remote is painful; this
    /// method exists for clients that have a keyboard.
    ///
    /// - Parameters:
    ///   - login: Login name.
    ///   - password: Password, never logged by the kit.
    /// - Returns: Session token to store in ``AuthTokenStoring``.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func login(login: String, password: String) async throws -> String {
        let body = try Self.encode(PasswordLoginBody(login: login, password: password))
        return try await fetch(
            path: "\(ServiceURL.apiPrefix)/accounts/users/auth/login",
            method: "POST",
            body: body,
            as: TokenResponse.self
        ).token
    }

    /// Fetches the profile of the authenticated user.
    ///
    /// Without a valid token the service answers 403; the kit surfaces that as
    /// ``AniLibertyError/httpStatus(_:)`` so the screen can route the user back to sign-in.
    ///
    /// - Parameter token: Session token from ``loginWithOTP(code:deviceID:)`` or
    ///   ``login(login:password:)``.
    /// - Returns: The profile of the token's owner.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func profile(token: String) async throws -> UserProfile {
        let request = try makeRequest(
            path: "\(ServiceURL.apiPrefix)/accounts/users/me/profile",
            method: "GET",
            token: token
        )
        let started = Date()
        // Try the clean session first; if it does not answer in time, ask again over the shared one and
        // log which of the two worked. The app has been observed waiting forever on this call while the
        // same request from a test runner answers in 300 ms, so the fallback is also the diagnosis.
        var result: (data: Data, status: Int)?
        do {
            result = try await withTimeout(seconds: 12) { [self] in
                try await perform(request, over: accountTransport)
            }

        } catch {
            Self.accountLogger
                .error(
                    "profile: clean session failed after \(Date().timeIntervalSince(started), privacy: .public)s: \(String(describing: error), privacy: .public)"
                )
            result = try await withTimeout(seconds: 12) { [self] in
                try await perform(request)
            }
        }
        guard let result else { throw AniLibertyError.network("The profile request produced nothing.") }
        Self.accountLogger.info(
            "profile: status \(result.status, privacy: .public), \(result.data.count, privacy: .public) bytes in \(Date().timeIntervalSince(started), privacy: .public)s"
        )
        let (data, status) = (result.data, result.status)
        guard (200 ..< 300).contains(status) else {
            throw AniLibertyError.httpStatus(status)
        }
        return try decode(UserProfile.self, from: data)
    }

    /// Fetches one page of the authenticated user's favourite releases.
    ///
    /// The endpoint returns the same `data`/`meta.pagination` envelope as the catalogue,
    /// so ``CatalogPage`` is reused. `page` and `limit` are clamped like the catalogue's.
    ///
    /// - Parameters:
    ///   - token: Session token.
    ///   - page: One-based page number; values below 1 become 1.
    ///   - limit: Page size; clamped into `1...CatalogPage.maximumLimit`.
    /// - Returns: The favourite releases of this page with their pagination.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func favorites(
        token: String,
        page: Int = 1,
        limit: Int = CatalogPage.defaultLimit
    ) async throws -> CatalogPage {
        let safePage = max(1, page)
        let safeLimit = min(max(1, limit), CatalogPage.maximumLimit)
        let request = try makeRequest(
            path: "\(ServiceURL.apiPrefix)/accounts/users/me/favorites/releases",
            method: "GET",
            query: [
                URLQueryItem(name: "page", value: String(safePage)),
                URLQueryItem(name: "limit", value: String(safeLimit)),
            ],
            token: token
        )
        let (data, status) = try await perform(request, over: accountTransport)
        guard (200 ..< 300).contains(status) else {
            throw AniLibertyError.httpStatus(status)
        }
        return try decode(CatalogPage.self, from: data)
    }

    /// Fetches the identifiers of the releases in the user's favourites.
    ///
    /// `GET /api/v1/accounts/users/me/favorites/ids` returns a bare JSON array of release
    /// identifiers (`[9023, 9024, 9025]`), which is far cheaper than paging the favourites
    /// list — use it to mark hearts in the catalogue.
    ///
    /// - Parameter token: Session token.
    /// - Returns: Release identifiers, in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func favoriteReleaseIDs(token: String) async throws -> [Int] {
        let request = try makeRequest(
            path: "\(ServiceURL.apiPrefix)/accounts/users/me/favorites/ids",
            method: "GET",
            token: token
        )
        let (data, status) = try await perform(request, over: accountTransport)
        guard (200 ..< 300).contains(status) else {
            throw AniLibertyError.httpStatus(status)
        }
        return try decode([Int].self, from: data)
    }

    /// Adds releases to the user's favourites.
    ///
    /// `POST /api/v1/accounts/users/me/favorites` takes an array of `{"release_id": …}`
    /// objects and answers with the identifiers now in favourites, so the screen can update
    /// its hearts without a second call. An empty array sends nothing and answers `[]`.
    ///
    /// - Parameters:
    ///   - releaseIDs: Release identifiers to add.
    ///   - token: Session token.
    /// - Returns: Release identifiers in favourites after the change.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func addFavorites(_ releaseIDs: [Int], token: String) async throws -> [Int] {
        try await updateFavorites(releaseIDs, token: token, method: "POST")
    }

    /// Removes releases from the user's favourites.
    ///
    /// `DELETE /api/v1/accounts/users/me/favorites` takes the same `{"release_id": …}`
    /// array as the `POST` and answers with the identifiers that remain. A `DELETE` with a
    /// body is unusual but perfectly valid, so the identifiers travel in the body instead
    /// of an ever-growing query string.
    ///
    /// - Parameters:
    ///   - releaseIDs: Release identifiers to remove.
    ///   - token: Session token.
    /// - Returns: Release identifiers in favourites after the removal.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    func removeFavorites(_ releaseIDs: [Int], token: String) async throws -> [Int] {
        try await updateFavorites(releaseIDs, token: token, method: "DELETE")
    }

    /// Sends one favourites mutation and decodes the resulting identifier list.
    private func updateFavorites(
        _ releaseIDs: [Int],
        token: String,
        method: String
    ) async throws -> [Int] {
        guard !releaseIDs.isEmpty else {
            return []
        }
        let body = try Self.encode(releaseIDs.map(FavoriteBody.init))
        let request = try makeRequest(
            path: "\(ServiceURL.apiPrefix)/accounts/users/me/favorites",
            method: method,
            body: body,
            token: token
        )
        let (data, status) = try await perform(request, over: accountTransport)
        guard (200 ..< 300).contains(status) else {
            throw AniLibertyError.httpStatus(status)
        }
        return try decode([Int].self, from: data)
    }
}

/// Body of `POST /accounts/otp/get`.
private struct OTPRequestBody: Encodable {
    let deviceID: String

    private enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
    }
}

/// Body of `POST /accounts/otp/login`.
///
/// The code goes out as an integer when it is made of digits — the API schema says
/// `integer` even though `otp/get` returns a string — and as a string otherwise, so the
/// service decides what an unusual code means.
private struct OTPLoginBody: Encodable {
    let code: String
    let deviceID: String

    private enum CodingKeys: String, CodingKey {
        case code
        case deviceID = "device_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let numeric = Int(code) {
            try container.encode(numeric, forKey: .code)
        } else {
            try container.encode(code, forKey: .code)
        }
        try container.encode(deviceID, forKey: .deviceID)
    }
}

/// Body of `POST /accounts/users/auth/login`.
private struct PasswordLoginBody: Encodable {
    let login: String
    let password: String
}

/// Response of both login endpoints.
private struct TokenResponse: Decodable {
    let token: String
}

/// Body element of the favourites `POST` and `DELETE`: `{"release_id": …}`.
private struct FavoriteBody: Encodable {
    let releaseID: Int

    private enum CodingKeys: String, CodingKey {
        case releaseID = "release_id"
    }
}
