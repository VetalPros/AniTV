# SCAFFOLD CONTRACT — frozen public API of `AniLibertyKit`

Status: **frozen for the scaffolding sprint (2026-11-10)**. Both the Kit and the tvOS app are built
against this document. Change it only by re-negotiating with the Lead, never unilaterally.

Why it exists: the Kit and the app are written in parallel by different agents. Without a frozen
surface, the integration step becomes guesswork.

Facts behind the shapes below were verified against the live API (`docs/api-notes.md`, fixtures in
`AniLibertyKit/Tests/AniLibertyKitTests/Fixtures/`).

## Ground rules

- Kit is `Foundation`-only (no SwiftUI, no UIKit, no AVFoundation needed for the slice) so that
  `swift test --package-path AniLibertyKit` runs on the host toolchain.
- Every public type is `Sendable`; every public type used in UI is `Equatable`.
- All JSON keys are snake_case; the decoder uses `.convertFromSnakeCase`, so Swift properties are
  lowerCamelCase and no `CodingKeys` are needed except where a name genuinely differs.
- Dates: ISO-8601 with fractional seconds **and** without; a failing date must never fail the whole
  decode (date fields are `Optional`).
- Relative media paths (`/storage/...`) are resolved by the Kit; the app never builds media URLs.

## Module layout (Kit)

```
AniLibertyKit/Sources/AniLibertyKit/
  Models/         Release.swift, Episode.swift, NamedValue.swift, Media.swift, Genre.swift
  API/            AniLibertyClient.swift, AniLibertyConfiguration.swift, HTTPTransport.swift,
                  AniLibertyError.swift, JSONDecoder+AniLiberty.swift
  Cache/          ImageCache.swift
  Player/         StreamResolver.swift, TimecodeResolver.swift
```

## Models

```swift
public struct NamedValue: Sendable, Equatable, Decodable {
    public let value: String?        // "TV", "autumn" …
    public let description: String?  // "ТВ", "Осень" … (Russian, may be nil)
}

public struct Release: Sendable, Identifiable, Equatable, Decodable {
    public let id: Int
    public let alias: String
    public let name: Name            // nested: { main, english, alternative }
    public let year: Int?
    public let type: NamedValue?
    public let season: NamedValue?
    public let ageRating: String?    // "16+"
    public let averageRating: Double?        // rating.average
    public let ratingVotes: Int?             // rating.votes
    public let episodesTotal: Int?
    public let isOngoing: Bool?              // ongoing series ⇢ badge
    public let isBlockedByGeo: Bool          // ⇢ badge + no player
    public let isBlockedByCopyrights: Bool   // ⇢ badge + no player
    public let description: String?          // markdown-ish plain text with \r\n
    public let posterURL: URL?               // absolute, optimized → src fallback
    public let posterThumbnailURL: URL?      // absolute, for compact rows
    public let genres: [Genre]               // [] when absent
    public let episodes: [Episode]           // [] on list endpoints, filled on detail

    public var title: String                 // name.main
    public var originalTitle: String?        // name.english ?? name.alternative
    public var subtitle: String              // "2026 · ТВ · 16+" style, no trailing separators
    public var isPlayable: Bool              // has a playable episode AND not blocked
}

public extension Release {
    struct Name: Sendable, Equatable, Decodable {
        public let main: String
        public let english: String?
        public let alternative: String?
    }
}

public struct Genre: Sendable, Identifiable, Equatable, Decodable {
    public let id: Int
    public let name: String?
}

public struct Episode: Sendable, Identifiable, Equatable, Decodable {
    public let id: UUID
    public let ordinal: Int
    public let name: String?          // usually nil; UI falls back to "Серия N"
    public let duration: Double?      // seconds
    public let hls480: URL?
    public let hls720: URL?
    public let hls1080: URL?
    public let previewURL: URL?       // absolute
    public let opening: SkipRange?    // { start, stop } seconds
    public let ending: SkipRange?     // { start, stop } seconds

    public var displayTitle: String   // name ?? "Серия <ordinal>"
}

public extension Episode {
    struct SkipRange: Sendable, Equatable, Decodable {
        public let start: Double?
        public let stop: Double?
    }
}
```

## Networking

```swift
public struct AniLibertyConfiguration: Sendable, Equatable {
    public var baseURL: URL          // https://aniliberty.top
    public var userAgent: String     // "AniTV/0.1 (+https://github.com/VetalPros/AniTV)"
    public static let `default`: AniLibertyConfiguration
    public init(baseURL: URL, userAgent: String)
}

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init(configuration: URLSessionConfiguration = .default)
}

public actor AniLibertyClient {
    public init(configuration: AniLibertyConfiguration = .default,
                transport: any HTTPTransport = URLSessionTransport())

    public func latestReleases() async throws -> [Release]          // GET /api/v1/anime/releases/latest
    public func release(idOrAlias: String) async throws -> Release  // GET /api/v1/anime/releases/{idOrAlias}
}

public enum AniLibertyError: Error, Sendable, Equatable, LocalizedError {
    case invalidURL(String)
    case httpStatus(Int)
    case decoding(String)
    case network(String)
    case cancelled
}
```

Rules: one `User-Agent`, `Accept: application/json`, `URLCache` on, no retries beyond one transient
401/429-free attempt (the slice does not need retry logic yet), never log the URL's query from
authenticated endpoints.

## Caching

```swift
public actor ImageCache {
    public static let shared: ImageCache
    public init(memoryLimit: Int = 64 << 20, diskDirectory: URL? = nil)
    public func data(for url: URL) async throws -> Data   // memory → disk → network
}
```

## Playback helpers

```swift
public enum StreamQuality: String, Sendable, CaseIterable, Comparable {
    case sd480 = "480", hd720 = "720", uhd1080 = "1080"
}

public struct PlaybackSource: Sendable, Equatable {
    public let url: URL
    public let quality: StreamQuality
}

public enum StreamResolver {
    public static func preferredSource(for episode: Episode) -> PlaybackSource?
    public static func sources(for episode: Episode) -> [PlaybackSource]  // 1080 → 720 → 480
}

public struct SkipTimecode: Sendable, Equatable {
    public enum Kind: Sendable { case opening, ending }
    public let kind: Kind
    public let start: Double
    public let end: Double
    public let releaseEpisodeID: UUID
}

public enum TimecodeResolver {
    public static func timecodes(for episode: Episode) -> [SkipTimecode]
    public static func activeSkip(for episode: Episode, playhead: Double) -> SkipTimecode?
}
```

## Symbols the app may use (nothing else)

`Release`, `Episode`, `Genre`, `NamedValue`, `AniLibertyClient`, `AniLibertyConfiguration`,
`AniLibertyError`, `ImageCache`, `StreamResolver`, `PlaybackSource`, `StreamQuality`,
`TimecodeResolver`, `SkipTimecode`.

The app must not touch `HTTPTransport`, `URLSession` directly, JSON, or `ServiceURL` (internal).

## Fixtures (already committed by the Lead)

- `Fixtures/releases_latest.json` — bare JSON array, 3 real releases from `/anime/releases/latest`.
- `Fixtures/release_detail.json` — one real release with 6 episodes, HLS URLs, opening/ending.

Tests must load these through `Bundle.module` and must never hit the network.
