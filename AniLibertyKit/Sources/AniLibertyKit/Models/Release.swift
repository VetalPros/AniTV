import Foundation

/// A release as returned by the latest-releases feed and the release detail endpoint.
///
/// Decoding is deliberately tolerant: apart from `id`, `alias` and `name.main` every
/// field may be missing or `null`, and unknown keys are ignored. The feed endpoint does
/// not return episodes, so `episodes` is empty there; the detail endpoint fills it in and
/// the array is sorted by `ordinal`.
public struct Release: Sendable, Identifiable, Equatable, Decodable {
    /// Titles of a release: the main one plus optional English and alternative variants.
    public struct Name: Sendable, Equatable, Decodable {
        /// Primary (usually Russian) title.
        public let main: String
        /// English title, when the service knows one.
        public let english: String?
        /// Alternative title, when the service knows one.
        public let alternative: String?
    }

    /// Stable numeric identifier of the release.
    public let id: Int
    /// URL slug of the release, accepted by `AniLibertyClient.release(idOrAlias:)`.
    public let alias: String
    /// Titles of the release.
    public let name: Name
    /// Year of the first broadcast, when known.
    public let year: Int?
    /// Release type (`TV`, `MOVIE`, …) with its Russian label.
    public let type: NamedValue?
    /// Season (`autumn`, `winter`, …) with its Russian label.
    public let season: NamedValue?
    /// Age restriction label, for example `"16+"`.
    public let ageRating: String?
    /// Average user rating taken from `rating.average`.
    public let averageRating: Double?
    /// Number of votes behind `averageRating`, taken from `rating.votes`.
    public let ratingVotes: Int?
    /// Announced number of episodes, when the API provides one.
    public let episodesTotal: Int?
    /// `true` while the release is still airing.
    public let isOngoing: Bool?
    /// Geo-block flag; blocked releases must never reach the player.
    public let isBlockedByGeo: Bool
    /// Copyright-block flag; blocked releases must never reach the player.
    public let isBlockedByCopyrights: Bool
    /// Plain-text description with `\r\n` line breaks.
    public let description: String?
    /// Absolute poster URL, preferring the optimised variant.
    public let posterURL: URL?
    /// Absolute thumbnail URL for compact rows.
    public let posterThumbnailURL: URL?
    /// Genres of the release; empty when the API omits them.
    public let genres: [Genre]
    /// Episodes of the release; empty on the feed endpoint, filled on the detail endpoint.
    public let episodes: [Episode]

    /// Keys of the release payload after `.convertFromSnakeCase` has been applied.
    private enum CodingKeys: String, CodingKey {
        case id
        case alias
        case name
        case year
        case type
        case season
        case ageRating
        case rating
        case episodesTotal
        case isOngoing
        case isBlockedByGeo
        case isBlockedByCopyrights
        case description
        case poster
        case genres
        case episodes
    }

    /// Decodes a release tolerantly: only the identity and the main title are required.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        alias = try container.decode(String.self, forKey: .alias)
        name = try container.decode(Name.self, forKey: .name)
        year = try? container.decodeIfPresent(Int.self, forKey: .year)
        type = try? container.decodeIfPresent(NamedValue.self, forKey: .type)
        season = try? container.decodeIfPresent(NamedValue.self, forKey: .season)
        ageRating = Self.ageRating(from: container)
        let rating = Self.rating(from: container)
        averageRating = rating.average
        ratingVotes = rating.votes
        episodesTotal = try? container.decodeIfPresent(Int.self, forKey: .episodesTotal)
        isOngoing = try? container.decodeIfPresent(Bool.self, forKey: .isOngoing)
        isBlockedByGeo = (try? container.decodeIfPresent(Bool.self, forKey: .isBlockedByGeo)) ?? false
        isBlockedByCopyrights = (try? container.decodeIfPresent(Bool.self, forKey: .isBlockedByCopyrights)) ?? false
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        let pictures = Self.pictures(from: container)
        posterURL = pictures.poster
        posterThumbnailURL = pictures.thumbnail
        genres = (try? container.decodeIfPresent([Genre].self, forKey: .genres)) ?? []
        episodes = ((try? container.decodeIfPresent([Episode].self, forKey: .episodes)) ?? [])
            .sorted { $0.ordinal < $1.ordinal }
    }

    /// Title for lists and the player, taken from `name.main`.
    public var title: String {
        name.main
    }

    /// Original title, preferring the English variant over the alternative one.
    public var originalTitle: String? {
        name.english ?? name.alternative
    }

    /// One-line metadata summary, for example `"2026 · ТВ · 16+"`.
    ///
    /// Missing parts are skipped so the string never ends with a separator.
    public var subtitle: String {
        var parts: [String] = []
        if let year {
            parts.append(String(year))
        }
        if let label = type?.description ?? type?.value {
            parts.append(label)
        }
        if let ageRating {
            parts.append(ageRating)
        }
        return parts.joined(separator: " · ")
    }

    /// `true` when the release is not blocked and at least one episode can be played.
    public var isPlayable: Bool {
        guard !isBlockedByGeo, !isBlockedByCopyrights else {
            return false
        }
        return episodes.contains { $0.hls1080 != nil || $0.hls720 != nil || $0.hls480 != nil }
    }
}

private extension Release {
    /// Shape of the `age_rating` object used by the current API.
    struct AgeRating: Decodable {
        let value: String?
        let label: String?
    }

    /// Shape of the `rating` object: average score and vote count.
    struct Rating: Decodable {
        let average: Double?
        let votes: Int?
    }

    private static func ageRating(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        if let label = try? container.decode(String.self, forKey: .ageRating) {
            return label
        }
        guard let object = try? container.decode(AgeRating.self, forKey: .ageRating) else {
            return nil
        }
        return object.label ?? object.value
    }

    private static func rating(from container: KeyedDecodingContainer<CodingKeys>) -> (average: Double?, votes: Int?) {
        guard let rating = try? container.decode(Rating.self, forKey: .rating) else {
            return (nil, nil)
        }
        return (rating.average, rating.votes)
    }

    private static func pictures(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> (poster: URL?, thumbnail: URL?) {
        if let picture = try? container.decode(Picture.self, forKey: .poster) {
            return (
                ServiceURL.absoluteURL(from: picture.optimized?.src ?? picture.src),
                ServiceURL.absoluteURL(from: picture.optimized?.thumbnail ?? picture.thumbnail)
            )
        }
        let single = ServiceURL.absoluteURL(from: try? container.decode(String.self, forKey: .poster))
        return (single, single)
    }
}
