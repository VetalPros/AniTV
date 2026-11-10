import Foundation

/// Streaming qualities the service publishes for an episode.
public enum StreamQuality: String, Sendable, CaseIterable, Comparable {
    /// 480p playlist.
    case sd480 = "480"
    /// 720p playlist.
    case hd720 = "720"
    /// 1080p playlist.
    case uhd1080 = "1080"

    /// Rank used by the comparison operators; higher means better.
    private var rank: Int {
        switch self {
        case .sd480: 0
        case .hd720: 1
        case .uhd1080: 2
        }
    }

    /// Orders qualities from worst to best, so `.uhd1080` is the greatest element.
    public static func < (lhs: StreamQuality, rhs: StreamQuality) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// A playable HLS playlist together with the quality it provides.
///
/// Values come from `StreamResolver`; the app hands `url` to `AVPlayer` as-is.
public struct PlaybackSource: Sendable, Equatable {
    /// Absolute HLS playlist URL.
    public let url: URL
    /// Quality of the playlist behind `url`.
    public let quality: StreamQuality
}

/// Turns the stream URLs of an episode into ordered playback options.
///
/// The order is fixed — 1080p, 720p, 480p — and missing qualities are skipped, so the
/// first element is always the best available source.
public enum StreamResolver {
    /// Every available source of `episode`, best quality first.
    ///
    /// - Parameter episode: Episode decoded from the release detail endpoint.
    /// - Returns: Sources in 1080p, 720p, 480p order; empty when the episode has none.
    public static func sources(for episode: Episode) -> [PlaybackSource] {
        let candidates: [(quality: StreamQuality, url: URL?)] = [
            (.uhd1080, episode.hls1080),
            (.hd720, episode.hls720),
            (.sd480, episode.hls480),
        ]
        return candidates.compactMap { candidate in
            guard let url = candidate.url else {
                return nil
            }
            return PlaybackSource(url: url, quality: candidate.quality)
        }
    }

    /// The best available source of `episode`, or `nil` when no playlist exists.
    ///
    /// - Parameter episode: Episode decoded from the release detail endpoint.
    /// - Returns: The 1080p source when present, otherwise 720p, otherwise 480p.
    public static func preferredSource(for episode: Episode) -> PlaybackSource? {
        sources(for: episode).first
    }
}
