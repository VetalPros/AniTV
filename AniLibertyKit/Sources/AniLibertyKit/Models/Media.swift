import Foundation

/// Shape of the nested `poster` and `preview` objects of the API.
///
/// Newer payloads carry an additional `optimized` group with the same three keys, which
/// keeps the tvOS grid cheap to load:
///
/// ```json
/// { "src": "…", "preview": "…", "thumbnail": "…", "optimized": { "src": "…" } }
/// ```
///
/// Both absolute URLs and site-relative paths such as `/storage/…` occur on the wire.
struct Picture: Decodable, Sendable {
    /// Optimised variants of the picture; present on the releases feed.
    struct Variants: Decodable, Sendable {
        /// Optimised full-size source.
        let src: String?
        /// Optimised mid-size preview.
        let preview: String?
        /// Optimised thumbnail for compact rows.
        let thumbnail: String?
    }

    /// Full-size image source.
    let src: String?
    /// Mid-size preview.
    let preview: String?
    /// Small thumbnail.
    let thumbnail: String?
    /// Additional derivative group added by the service in 2026.
    let optimized: Variants?
}

/// URL helpers shared by the models, the client and the image cache.
///
/// The app must never assemble service URLs itself, so the resolution of relative media
/// paths and of API endpoint paths lives here and stays internal to the kit.
enum ServiceURL {
    /// Site root of the service; every media and API URL is built from it.
    static let base: URL = {
        guard let url = URL(string: "https://aniliberty.top") else {
            preconditionFailure("The hard-coded AniLiberty base URL is malformed.")
        }
        return url
    }()

    /// Version prefix shared by every REST endpoint.
    static let apiPrefix = "api/v1"

    /// Turns an API media path into an absolute URL.
    ///
    /// Absolute URLs (the HLS playlists on `cache.libria.fun`) pass through unchanged,
    /// while relative paths (`/storage/releases/…/poster.jpg`) are resolved against
    /// `base`. Empty and whitespace-only strings count as missing.
    ///
    /// - Parameter raw: Value straight from the payload, or `nil`.
    /// - Returns: An absolute URL, or `nil` when nothing usable was provided.
    static func absoluteURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        if trimmed.hasPrefix("//"), let url = URL(string: "https:" + trimmed) {
            return url
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    /// Builds an absolute endpoint URL from the configured site root and an API path.
    ///
    /// - Parameters:
    ///   - base: Site root, normally `https://aniliberty.top`.
    ///   - path: Path with the version prefix, for example `api/v1/anime/releases/latest`.
    /// - Returns: The endpoint URL, or `nil` when the parts do not form a usable URL.
    static func endpoint(base: URL, path: String) -> URL? {
        let url = base.appending(path: path)
        guard url.scheme != nil, url.host() != nil else {
            return nil
        }
        return url
    }
}
