import Foundation

/// A single episode of a release, with its HLS playlists and skip ranges.
///
/// Episodes only arrive from the release detail endpoint; the latest-releases feed never
/// contains them. Every stream URL is absolute by the time the model exists, so the app
/// can hand `StreamResolver` output straight to `AVPlayer`.
public struct Episode: Sendable, Identifiable, Equatable, Decodable {
    /// Opening or ending range the player can skip over.
    ///
    /// Both bounds are optional in the payload: the service sometimes publishes only one
    /// of them, or a zero-length range that must be ignored.
    public struct SkipRange: Sendable, Equatable, Decodable {
        /// First second of the range, as returned by the API.
        public let start: Double?
        /// Last second of the range, as returned by the API.
        public let stop: Double?
    }

    /// Stable episode identifier; the API sends it as a UUID string.
    public let id: UUID
    /// One-based position of the episode inside the release.
    public let ordinal: Int
    /// Episode title, usually `nil` for currently airing shows.
    public let name: String?
    /// Duration in seconds, when the API knows it.
    public let duration: Double?
    /// 480p HLS playlist, resolved to an absolute URL.
    public let hls480: URL?
    /// 720p HLS playlist, resolved to an absolute URL.
    public let hls720: URL?
    /// 1080p HLS playlist, resolved to an absolute URL.
    public let hls1080: URL?
    /// Absolute preview frame URL used by the player placeholder.
    public let previewURL: URL?
    /// Opening range, when the service published one.
    public let opening: SkipRange?
    /// Ending range, when the service published one.
    public let ending: SkipRange?

    /// Keys of the episode payload after `.convertFromSnakeCase` has been applied.
    private enum CodingKeys: String, CodingKey {
        case id
        case ordinal
        case name
        case duration
        case hls480
        case hls720
        case hls1080
        case preview
        case opening
        case ending
    }

    /// Decodes an episode tolerantly: missing or `null` fields never fail the whole
    /// release, they simply stay empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        ordinal = try container.decode(Int.self, forKey: .ordinal)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        duration = try? container.decodeIfPresent(Double.self, forKey: .duration)
        hls480 = Self.streamURL(from: container, forKey: .hls480)
        hls720 = Self.streamURL(from: container, forKey: .hls720)
        hls1080 = Self.streamURL(from: container, forKey: .hls1080)
        previewURL = Self.previewURL(from: container)
        opening = try? container.decodeIfPresent(SkipRange.self, forKey: .opening)
        ending = try? container.decodeIfPresent(SkipRange.self, forKey: .ending)
    }

    /// Title for lists and the player: the API name, or `"Серия <ordinal>"`.
    public var displayTitle: String {
        guard let name else {
            return "Серия \(ordinal)"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Серия \(ordinal)" : trimmed
    }

    private static func streamURL(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> URL? {
        ServiceURL.absoluteURL(from: try? container.decodeIfPresent(String.self, forKey: key))
    }

    private static func previewURL(from container: KeyedDecodingContainer<CodingKeys>) -> URL? {
        guard let picture = try? container.decode(Picture.self, forKey: .preview) else {
            return nil
        }
        let raw = picture.optimized?.preview ?? picture.preview ?? picture.src
        return ServiceURL.absoluteURL(from: raw)
    }
}
