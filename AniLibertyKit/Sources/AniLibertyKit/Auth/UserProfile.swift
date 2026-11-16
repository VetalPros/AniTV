import Foundation

/// The signed-in user, as returned by `GET /accounts/users/me/profile`.
///
/// The service marks most fields as «own profile only»: `login`, `email` and the torrent
/// passkey are only filled in for the authenticated user, and the model keeps them
/// optional accordingly. Everything is tolerant except ``id``, so an API addition or a
/// removed field cannot break the profile screen.
///
/// The torrent **passkey** is deliberately not exposed: it is a credential, the screen
/// does not need it, and the kit never logs or surfaces secrets.
public struct UserProfile: Sendable, Equatable, Decodable {
    /// Traffic statistics of the user's torrent client.
    public struct TorrentStatistics: Sendable, Equatable, Decodable {
        /// Bytes uploaded to other peers.
        public let uploaded: Int?
        /// Bytes downloaded from other peers.
        public let downloaded: Int?
    }

    /// Stable numeric identifier of the account.
    public let id: Int
    /// Login name, filled in for the account owner only.
    public let login: String?
    /// E-mail address, filled in for the account owner only.
    public let email: String?
    /// Display name chosen by the user.
    public let nickname: String?
    /// Absolute URL of the full-size avatar.
    public let avatarURL: URL?
    /// Absolute URL of the avatar thumbnail.
    public let avatarThumbnailURL: URL?
    /// Torrent traffic counters, when the payload carries them.
    public let torrents: TorrentStatistics?
    /// Whether the account is currently banned.
    public let isBanned: Bool?
    /// Whether the e-mail is unconfirmed or the account is very young.
    public let isNew: Bool?
    /// Whether the account belongs to an administrator.
    public let isAdmin: Bool?
    /// Permission strings of every role the user holds.
    public let permissions: [String]
    /// Registration moment.
    public let createdAt: Date?
    /// Whether the account is shown advertisements.
    public let isWithAds: Bool?

    /// Creates a profile manually; the client always decodes it from the response.
    ///
    /// - Parameters:
    ///   - id: Stable numeric identifier.
    ///   - login: Login name.
    ///   - email: E-mail address.
    ///   - nickname: Display name.
    ///   - avatarURL: Full-size avatar.
    ///   - avatarThumbnailURL: Avatar thumbnail.
    ///   - torrents: Torrent traffic counters.
    ///   - isBanned: Ban flag.
    ///   - isNew: New-account flag.
    ///   - isAdmin: Administrator flag.
    ///   - permissions: Permission strings.
    ///   - createdAt: Registration moment.
    ///   - isWithAds: Advertisement flag.
    public init(
        id: Int,
        login: String? = nil,
        email: String? = nil,
        nickname: String? = nil,
        avatarURL: URL? = nil,
        avatarThumbnailURL: URL? = nil,
        torrents: TorrentStatistics? = nil,
        isBanned: Bool? = nil,
        isNew: Bool? = nil,
        isAdmin: Bool? = nil,
        permissions: [String] = [],
        createdAt: Date? = nil,
        isWithAds: Bool? = nil
    ) {
        self.id = id
        self.login = login
        self.email = email
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.avatarThumbnailURL = avatarThumbnailURL
        self.torrents = torrents
        self.isBanned = isBanned
        self.isNew = isNew
        self.isAdmin = isAdmin
        self.permissions = permissions
        self.createdAt = createdAt
        self.isWithAds = isWithAds
    }

    /// Name to show in the profile: nickname, then login, then the numeric identifier.
    public var displayName: String {
        nickname ?? login ?? "ID \(id)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case login
        case email
        case nickname
        case avatar
        case torrents
        case isBanned
        case isNew
        case isAdmin
        case permissions
        case createdAt
        case isWithAds
    }

    /// Decodes the user object, requiring only ``id``.
    ///
    /// - Parameter decoder: Decoder positioned on the response body.
    /// - Throws: `DecodingError` when the identifier is missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        login = try? container.decodeIfPresent(String.self, forKey: .login)
        email = try? container.decodeIfPresent(String.self, forKey: .email)
        nickname = try? container.decodeIfPresent(String.self, forKey: .nickname)
        let picture = try? container.decode(Picture.self, forKey: .avatar)
        avatarURL = ServiceURL.absoluteURL(from: picture?.optimized?.src ?? picture?.src)
        avatarThumbnailURL = ServiceURL.absoluteURL(
            from: picture?.optimized?.thumbnail ?? picture?.thumbnail
        )
        torrents = try? container.decodeIfPresent(TorrentStatistics.self, forKey: .torrents)
        isBanned = try? container.decodeIfPresent(Bool.self, forKey: .isBanned)
        isNew = try? container.decodeIfPresent(Bool.self, forKey: .isNew)
        isAdmin = try? container.decodeIfPresent(Bool.self, forKey: .isAdmin)
        permissions = (try? container.decodeIfPresent([String].self, forKey: .permissions)) ?? []
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        isWithAds = try? container.decodeIfPresent(Bool.self, forKey: .isWithAds)
    }
}
