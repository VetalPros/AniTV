import Foundation

/// One page of the catalogue together with the pagination the API reports.
///
/// The screen shows `total` in its «N найдено» header and uses ``hasNextPage`` to decide
/// whether to request the next page. `Release.episodes` is empty on this endpoint: the
/// catalogue returns list items only.
public struct CatalogPage: Sendable, Equatable {
    /// Page size the API documentation uses as an example.
    public static let defaultLimit = 15

    /// Largest page size the service accepts.
    ///
    /// Verified against the live service: `limit` above this value is rejected with
    /// HTTP 422 (`Поле limit не может быть больше 50.`), so the client clamps instead of
    /// letting a slider break the screen.
    public static let maximumLimit = 50

    /// Releases of this page, in the order the service returned them.
    public let releases: [Release]
    /// Total number of releases matching the filter.
    public let total: Int
    /// One-based number of this page.
    public let currentPage: Int
    /// Total number of pages the current filter produces.
    public let totalPages: Int
    /// Page size the service actually used.
    public let perPage: Int

    /// Whether a page after this one exists.
    public var hasNextPage: Bool {
        currentPage < totalPages
    }

    /// Creates a page manually; the client always decodes it from the response.
    ///
    /// - Parameters:
    ///   - releases: Releases of this page.
    ///   - total: Total number of matching releases.
    ///   - currentPage: One-based number of this page.
    ///   - totalPages: Total number of pages.
    ///   - perPage: Page size used by the service.
    public init(releases: [Release], total: Int, currentPage: Int, totalPages: Int, perPage: Int) {
        self.releases = releases
        self.total = total
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.perPage = perPage
    }
}

extension CatalogPage: Decodable {
    /// Decodes the `{ "data": …, "meta": { "pagination": … } }` envelope.
    ///
    /// The release array is required; pagination is defensive, because a missing or
    /// malformed `meta` should cost the page numbers rather than the whole list. Such a
    /// payload falls back to a single page made of the releases that did arrive.
    ///
    /// - Parameter decoder: Decoder positioned on the response body.
    /// - Throws: `DecodingError` when `data` is missing or a release cannot be decoded.
    public init(from decoder: any Decoder) throws {
        let envelope = try CatalogPageEnvelope(from: decoder)
        releases = envelope.releases

        let pagination = envelope.pagination
        perPage = pagination?.perPage ?? envelope.releases.count
        total = pagination?.total ?? envelope.releases.count
        currentPage = pagination?.currentPage ?? 1
        totalPages = pagination?.totalPages
            ?? Self.totalPages(total: total, perPage: perPage)
    }

    private static func totalPages(total: Int, perPage: Int) -> Int {
        guard perPage > 0 else {
            return 1
        }
        return max(1, (total + perPage - 1) / perPage)
    }
}

/// Wire shape of the catalogue response envelope.
private struct CatalogPageEnvelope: Decodable {
    enum Keys: String, CodingKey {
        case data
        case meta
    }

    let releases: [Release]
    let pagination: CatalogPagePagination?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        releases = try container.decode([Release].self, forKey: .data)
        pagination = try? container.decode(CatalogPageMeta.self, forKey: .meta).pagination
    }
}

/// Wire shape of `meta`; only `pagination` is used.
private struct CatalogPageMeta: Decodable {
    let pagination: CatalogPagePagination?
}

/// Wire shape of `meta.pagination`; every field is optional on purpose.
private struct CatalogPagePagination: Decodable {
    let total: Int?
    let perPage: Int?
    let currentPage: Int?
    let totalPages: Int?
}
