import Foundation

/// Inclusive range of release years used by ``CatalogFilter/years``.
///
/// The API models the range as an object (`{"from_year": 2010, "to_year": 2012}`), not as
/// an array, and either bound may be omitted.
public struct CatalogYearRange: Sendable, Equatable, Encodable {
    /// Earliest year to include, or `nil` for no lower bound.
    public var from: Int?
    /// Latest year to include, or `nil` for no upper bound.
    public var to: Int?

    /// Creates a year range.
    ///
    /// - Parameters:
    ///   - from: Earliest year to include.
    ///   - to: Latest year to include.
    public init(from: Int? = nil, to: Int? = nil) {
        self.from = from
        self.to = to
    }

    /// Whether neither bound is set; such a range is dropped from the payload.
    public var isEmpty: Bool {
        from == nil && to == nil
    }

    private enum CodingKeys: String, CodingKey {
        case from = "from_year"
        case to = "to_year"
    }
}

/// Filter the catalogue screen applies to the release list.
///
/// The API accepts the whole filter under a single `f` key of the `POST` body and silently
/// ignores filter-shaped keys placed at the top level, so a misplaced key costs a wrong
/// result set without any error. ``body(page:limit:)`` therefore builds the nested payload
/// and leaves out every empty group; an ``empty`` filter produces the plain list call.
///
/// Values for ``types``, ``seasons`` and ``sorting`` come from the catalogue reference
/// endpoints, so the UI never hard-codes the service's enums.
public struct CatalogFilter: Sendable, Equatable {
    /// Free-text query matched by the service against the release name.
    public var search: String?
    /// Genre identifiers, as returned by the genres reference endpoint.
    public var genreIDs: [Int]
    /// Release type values (`"TV"`, `"MOVIE"`, …).
    public var types: [String]
    /// Season values (`"winter"`, …).
    public var seasons: [String]
    /// Release year range.
    public var years: CatalogYearRange?
    /// Sorting value, for example `"FRESH_AT_DESC"`.
    public var sorting: String?

    /// Creates a filter; every component defaults to "not filtering".
    ///
    /// - Parameters:
    ///   - search: Free-text query.
    ///   - genreIDs: Genre identifiers to keep.
    ///   - types: Release type values to keep.
    ///   - seasons: Season values to keep.
    ///   - years: Release year range to keep.
    ///   - sorting: Sorting value.
    public init(
        search: String? = nil,
        genreIDs: [Int] = [],
        types: [String] = [],
        seasons: [String] = [],
        years: CatalogYearRange? = nil,
        sorting: String? = nil
    ) {
        self.search = search
        self.genreIDs = genreIDs
        self.types = types
        self.seasons = seasons
        self.years = years
        self.sorting = sorting
    }

    /// Filter that keeps every release, producing the plain list body.
    public static let empty = CatalogFilter()

    /// Whether the filter would be dropped from the payload entirely.
    public var isEmpty: Bool {
        payload.isEmpty
    }

    /// Encodes the request body the API expects.
    ///
    /// Only non-empty groups are written, and everything filter-shaped is nested under
    /// `f`; the returned bytes are what `AniLibertyClient.catalog(page:limit:filter:)`
    /// sends, which is also what the tests pin down.
    ///
    /// - Parameters:
    ///   - page: One-based page number, already clamped by the caller.
    ///   - limit: Page size, already clamped by the caller.
    /// - Returns: UTF-8 JSON body of the `POST` request.
    /// - Throws: Any `JSONEncoder` failure; the payload contains only strings and integers,
    ///   so in practice it never throws.
    func body(page: Int, limit: Int) throws -> Data {
        let filter = payload
        let body = CatalogRequestBody(page: page, limit: limit, filter: filter.isEmpty ? nil : filter)
        return try JSONEncoder().encode(body)
    }

    /// The `f` object, with empty groups already stripped.
    private var payload: CatalogFilterPayload {
        CatalogFilterPayload(
            search: Self.trimmed(search),
            genres: genreIDs.isEmpty ? nil : genreIDs,
            types: types.isEmpty ? nil : types,
            seasons: seasons.isEmpty ? nil : seasons,
            years: years.flatMap { $0.isEmpty ? nil : $0 },
            sorting: Self.trimmed(sorting)
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Wire shape of the `POST /anime/catalog/releases` body.
private struct CatalogRequestBody: Encodable {
    let page: Int
    let limit: Int
    let filter: CatalogFilterPayload?

    private enum CodingKeys: String, CodingKey {
        case page
        case limit
        case filter = "f"
    }
}

/// Wire shape of the `f` object; `nil` members are omitted by `JSONEncoder`.
private struct CatalogFilterPayload: Encodable {
    let search: String?
    let genres: [Int]?
    let types: [String]?
    let seasons: [String]?
    let years: CatalogYearRange?
    let sorting: String?

    var isEmpty: Bool {
        search == nil
            && genres == nil
            && types == nil
            && seasons == nil
            && years == nil
            && sorting == nil
    }
}
