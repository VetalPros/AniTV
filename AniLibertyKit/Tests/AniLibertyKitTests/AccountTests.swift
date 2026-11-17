@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Account")
struct AccountTests {
    private static let token = "session-token-never-logged"
    private static let deviceID = "65bed6eb-6f16-4a9f-a0f9-02e6832b36d5"

    // MARK: - OTP

    @Test("An OTP challenge decodes the recorded payload")
    func otpChallengeDecoding() throws {
        let challenge = try JSONDecoder.aniLiberty.decode(OTPChallenge.self, from: Fixtures.otpGet())

        // The service sends the code as a string; `otp/accept` takes an integer.
        #expect(challenge.code == "489544")
        let isNumeric = challenge.code.allSatisfy(\.isNumber)
        #expect(isNumeric)

        let formatter = ISO8601DateFormatter()
        let expectedExpiry = try #require(formatter.date(from: "2026-11-16T15:29:35+00:00"))
        #expect(challenge.expiresAt == expectedExpiry)

        // `remaining_time` is a float on the wire although the schema claims an integer.
        #expect(abs(challenge.remainingSeconds - 299.87) < 0.01)

        #expect(challenge.isExpired(at: expectedExpiry))
        #expect(challenge.isExpired(at: expectedExpiry.addingTimeInterval(-1)) == false)
        #expect(challenge.secondsRemaining(at: expectedExpiry) == 0)
    }

    @Test("The OTP request is an anonymous POST carrying the device id")
    func otpRequest() async throws {
        let transport = try StubTransport.serving(Fixtures.otpGet())
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        let challenge = try await client.requestOTP(deviceID: Self.deviceID)

        #expect(challenge.code == "489544")
        let request = try #require(await transport.recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/accounts/otp/get")
        #expect(request.method == "POST")
        #expect(request.contentType == "application/json")
        #expect(request.accept == "application/json")
        #expect(request.userAgent == AniLibertyConfiguration.default.userAgent)
        #expect(request.authorization == nil)

        let body = try Self.jsonObject(#require(request.body))
        #expect(body["device_id"] as? String == Self.deviceID)
    }

    @Test("An avatar without src still resolves, because the service fills preview")
    func avatarWithoutSource() throws {
        // Shaped after `commons.v1.models.components.image` in the OpenAPI document: a user picture is
        // described with preview and thumbnail only, unlike a release poster which carries src.
        let payload = Data(#"""
        {
            "id": 42,
            "login": "viewer",
            "nickname": "Viewer",
            "avatar": {
                "preview": "/storage/users/avatars/42/avatar-preview.jpg",
                "thumbnail": "/storage/users/avatars/42/avatar-thumbnail.jpg",
                "optimized": {
                    "preview": "/storage/users/avatars/42/avatar-optimized.webp",
                    "thumbnail": "/storage/users/avatars/42/avatar-thumbnail-optimized.webp"
                }
            }
        }
        """#.utf8)

        let profile = try JSONDecoder.aniLiberty.decode(UserProfile.self, from: payload)

        #expect(profile.avatarURL?.absoluteString.hasSuffix("avatar-optimized.webp") == true)
        #expect(profile.avatarURL?.host == "aniliberty.top")
        #expect(profile.avatarThumbnailURL?.absoluteString.hasSuffix("avatar-thumbnail-optimized.webp") == true)
    }

    @Test("A pending pairing maps to the dedicated otpNotAccepted case")
    func otpPendingMapping() async throws {
        let transport = try StubTransport.serving(Fixtures.otpLoginPending(), status: 500)
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        await #expect(throws: AniLibertyError.otpNotAccepted) {
            _ = try await client.loginWithOTP(code: "489544", deviceID: Self.deviceID)
        }

        // The dedicated case exists so the UI can keep polling instead of showing a failure.
        let error = AniLibertyError.otpNotAccepted
        #expect(error.errorDescription == "The one-time code has not been confirmed yet.")
        #expect(error.errorDescription?.contains("489544") == false)
    }

    @Test("The OTP login sends the numeric code the schema expects")
    func otpLoginBody() async throws {
        let transport = StubTransport.serving(Data(#"{"token":"issued-token"}"#.utf8))
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        let token = try await client.loginWithOTP(code: "048954", deviceID: Self.deviceID)
        #expect(token == "issued-token")

        let request = try #require(await transport.recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/accounts/otp/login")
        #expect(request.method == "POST")
        #expect(request.authorization == nil)

        let body = try Self.jsonObject(#require(request.body))
        // "048954" becomes the integer 48954: the API accepts an integer, not a padded string.
        #expect(body["code"] as? Int == 48954)
        #expect(body["device_id"] as? String == Self.deviceID)
    }

    @Test("An expired code surfaces the HTTP status instead of a token")
    func otpExpiredCode() async throws {
        let transport = StubTransport.serving(Data(#"{"message":"Unauthenticated."}"#.utf8), status: 422)
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        await #expect(throws: AniLibertyError.httpStatus(422)) {
            _ = try await client.loginWithOTP(code: "000000", deviceID: Self.deviceID)
        }
    }

    // MARK: - Password login

    @Test("Password login posts the credentials and returns the token")
    func passwordLogin() async throws {
        let transport = StubTransport.serving(Data(#"{"token":"password-token"}"#.utf8))
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        let token = try await client.login(login: "animeshnik_488", password: "hunter2")

        #expect(token == "password-token")
        let request = try #require(await transport.recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/accounts/users/auth/login")
        #expect(request.method == "POST")
        let body = try Self.jsonObject(#require(request.body))
        #expect(body["login"] as? String == "animeshnik_488")
        #expect(body["password"] as? String == "hunter2")
    }

    // MARK: - Profile

    @Test("The profile request carries the bearer token")
    func profileRequest() async throws {
        // SYNTHESIZED fixture: see Fixtures/README.md — no account exists to record one.
        let transport = try StubTransport.serving(Fixtures.userProfile())
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        let profile = try await client.profile(token: Self.token)

        let request = try #require(await transport.recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/accounts/users/me/profile")
        #expect(request.method == "GET")
        #expect(request.authorization == "Bearer \(Self.token)")

        #expect(profile.id == 4_837_362)
        #expect(profile.displayName == "Animeshnik488")
        #expect(profile.login == "animeshnik_488")
        #expect(profile.email == "animeshnik_488@example.com")
        #expect(
            profile.avatarURL?.absoluteString
                == "https://aniliberty.top/storage/users/avatars/4837362/avatar-optimized.webp"
        )
        #expect(
            profile.avatarThumbnailURL?.absoluteString
                == "https://aniliberty.top/storage/users/avatars/4837362/avatar-thumbnail-optimized.webp"
        )
        #expect(profile.torrents?.uploaded == 998_234_623)
        #expect(profile.torrents?.downloaded == 2_397_162_874_432)
        #expect(profile.isAdmin == false)
        #expect(profile.isBanned == false)
        #expect(profile.permissions == ["anime:releases:release:access"])
        #expect(profile.createdAt != nil)
    }

    @Test("A profile decodes tolerantly from the identifier alone")
    func profileTolerance() throws {
        let payload = Data(#"{"id":7,"unknown_future_field":{"a":1}}"#.utf8)
        let profile = try JSONDecoder.aniLiberty.decode(UserProfile.self, from: payload)

        #expect(profile.id == 7)
        #expect(profile.login == nil)
        #expect(profile.email == nil)
        #expect(profile.nickname == nil)
        #expect(profile.avatarURL == nil)
        #expect(profile.torrents == nil)
        #expect(profile.permissions.isEmpty)
        #expect(profile.createdAt == nil)
        #expect(profile.displayName == "ID 7")
    }

    @Test("An unauthorized profile surfaces the HTTP status without the token")
    func profileUnauthorized() async throws {
        let transport = StubTransport.serving(
            Data(#"{"message":"This action is unauthorized."}"#.utf8),
            status: 403
        )
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        do {
            _ = try await client.profile(token: Self.token)
            Issue.record("Expected the unauthorized request to fail.")
        } catch let error as AniLibertyError {
            #expect(error == .httpStatus(403))
            #expect(error.errorDescription?.contains(Self.token) == false)
        }
    }

    // MARK: - Favourites

    @Test("Favourites decode into the catalogue page")
    func favoritesDecoding() async throws {
        // SYNTHESIZED fixture: see Fixtures/README.md — no account exists to record one.
        let transport = try StubTransport.serving(Fixtures.favoritesReleases())
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        let page = try await client.favorites(token: Self.token, page: 2, limit: 10)

        let request = try #require(await transport.recorded.first)
        #expect(
            request.url?.path(percentEncoded: false)
                == "/api/v1/accounts/users/me/favorites/releases"
        )
        #expect(request.method == "GET")
        #expect(request.authorization == "Bearer \(Self.token)")
        let query = try #require(request.url?.query(percentEncoded: false))
        #expect(query.contains("page=2"))
        #expect(query.contains("limit=10"))

        #expect(page.total == 2)
        #expect(page.releases.count == 2)
        #expect(page.perPage == 2)
        #expect(page.hasNextPage == false)
        #expect(page.releases.first?.alias == "magicalexplorer")
        #expect(page.releases.first?.episodes.isEmpty == true)
    }

    @Test("Favourites paging is clamped like the catalogue's")
    func favoritesClamping() async throws {
        let transport = try StubTransport.serving(Fixtures.favoritesReleases())
        let client = AniLibertyClient(transport: transport, accountTransport: transport)

        _ = try await client.favorites(token: Self.token, page: 0, limit: 500)

        let request = try #require(await transport.recorded.first)
        let query = try #require(request.url?.query(percentEncoded: false))
        #expect(query.contains("page=1"))
        #expect(query.contains("limit=50"))
    }

    // MARK: - Token store seam

    @Test("A fake token store round-trips without the Keychain")
    func fakeTokenStore() async throws {
        let store = InMemoryTokenStore()

        #expect(try await store.load() == nil)

        try await store.save(Self.token)
        #expect(try await store.load() == Self.token)

        let replacement = "another-token"
        try await store.save(replacement)
        #expect(try await store.load() == replacement)

        try await store.delete()
        #expect(try await store.load() == nil)

        // Deleting twice is not an error.
        try await store.delete()
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
