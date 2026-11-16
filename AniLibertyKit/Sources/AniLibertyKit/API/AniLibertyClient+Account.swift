import Foundation

/// Account endpoints: OTP pairing, password login, the profile and favourites.
///
/// The token always arrives as a parameter, never as actor state, so signing out is
/// forgetting it in the ``AuthTokenStoring`` store rather than resetting the client.
public extension AniLibertyClient {
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
        return try await fetch(
            path: "\(ServiceURL.apiPrefix)/accounts/otp/get",
            method: "POST",
            body: body,
            as: OTPChallenge.self
        )
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

        let (data, status) = try await perform(request)
        if (200 ..< 300).contains(status) {
            return try decode(TokenResponse.self, from: data).token
        }
        if status == 500 {
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
        try await fetch(
            path: "\(ServiceURL.apiPrefix)/accounts/users/me/profile",
            method: "GET",
            token: token,
            as: UserProfile.self
        )
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
        return try await fetch(
            path: "\(ServiceURL.apiPrefix)/accounts/users/me/favorites/releases",
            method: "GET",
            query: [
                URLQueryItem(name: "page", value: String(safePage)),
                URLQueryItem(name: "limit", value: String(safeLimit)),
            ],
            token: token,
            as: CatalogPage.self
        )
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
