import Foundation
import os

/// Actor-based client for the public AniLiberty REST API.
///
/// The implemented endpoints are the latest-releases feed, a single release with its
/// episodes, the filtered catalogue with its reference data, and the account layer: OTP
/// pairing, password login, the profile and favourites. URL building, headers and error
/// mapping live here, so the app never touches `URLSession` directly.
///
/// Authenticated calls take the session token as a parameter and send it as
/// `Authorization: Bearer`. The client keeps no auth state of its own, so signing out is
/// simply forgetting the token in the ``AuthTokenStoring`` store.
public actor AniLibertyClient {
    static let logger = Logger(subsystem: "tv.anitv.client", category: "Transport")
    private let configuration: AniLibertyConfiguration
    private let transport: any HTTPTransport
    /// Clean session used for every account call (handshake, profile, favourites); see
    /// ``URLSessionTransport/ephemeral()``.
    let accountTransport: any HTTPTransport

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - configuration: Base URL and `User-Agent`; the default value is production.
    ///   - transport: HTTP seam; the default value uses `URLSession` with caching on.
    public init(
        configuration: AniLibertyConfiguration = .default,
        transport: any HTTPTransport = URLSessionTransport(),
        accountTransport: any HTTPTransport = URLSessionTransport.ephemeral()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.accountTransport = accountTransport
    }

    /// Fetches the latest releases feed.
    ///
    /// `GET /api/v1/anime/releases/latest` returns a bare JSON array without episodes, so
    /// `Release.episodes` is empty for every element.
    ///
    /// - Returns: Releases in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func latestReleases() async throws -> [Release] {
        try await fetch(path: "\(ServiceURL.apiPrefix)/anime/releases/latest", as: [Release].self)
    }

    /// Fetches one release by numeric identifier or by URL slug.
    ///
    /// `GET /api/v1/anime/releases/{idOrAlias}` includes the episode list with absolute
    /// HLS URLs and the opening/ending timecodes.
    ///
    /// - Parameter idOrAlias: Numeric identifier (`"10308"`) or slug (`"demons-crest"`).
    /// - Returns: The release with its episodes sorted by `ordinal`.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func release(idOrAlias: String) async throws -> Release {
        try await fetch(path: "\(ServiceURL.apiPrefix)/anime/releases/\(idOrAlias)", as: Release.self)
    }

    /// Fetches one page of the filtered catalogue.
    ///
    /// `POST /api/v1/anime/catalog/releases` takes the filter nested under `f`, which
    /// `CatalogFilter` handles; the response is the `data`/`meta.pagination` envelope
    /// carried by ``CatalogPage``.
    ///
    /// The service rejects page sizes outside `1...50` with HTTP 422, so `page` and
    /// `limit` are clamped into `1...` and ``CatalogPage/maximumLimit`` respectively
    /// instead of letting a bad slider value fail the screen.
    ///
    /// - Parameters:
    ///   - page: One-based page number; values below 1 become 1.
    ///   - limit: Page size; clamped into `1...CatalogPage.maximumLimit`.
    ///   - filter: Filter to apply; ``CatalogFilter/empty`` lists everything.
    /// - Returns: The decoded page with its pagination.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func catalog(
        page: Int = 1,
        limit: Int = CatalogPage.defaultLimit,
        filter: CatalogFilter = .empty
    ) async throws -> CatalogPage {
        let safePage = max(1, page)
        let safeLimit = min(max(1, limit), CatalogPage.maximumLimit)
        let body: Data
        do {
            body = try filter.body(page: safePage, limit: safeLimit)
        } catch {
            throw AniLibertyError.decoding("Could not encode the catalogue filter: \(error)")
        }
        return try await fetch(
            path: "\(ServiceURL.apiPrefix)/anime/catalog/releases",
            method: "POST",
            body: body,
            as: CatalogPage.self
        )
    }

    /// Fetches the genre catalogue.
    ///
    /// `GET /api/v1/anime/catalog/references/genres` returns `{ id, name }` rows; the
    /// identifiers are what ``CatalogFilter/genreIDs`` expects.
    ///
    /// - Returns: Genres in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func referenceGenres() async throws -> [Genre] {
        try await fetch(path: Self.referencePath("genres"), as: [Genre].self)
    }

    /// Fetches the release type catalogue (`TV`, `MOVIE`, …).
    ///
    /// - Returns: Type rows in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func referenceTypes() async throws -> [CatalogReference] {
        try await fetch(path: Self.referencePath("types"), as: [CatalogReference].self)
    }

    /// Fetches the season catalogue (`winter`, `autumn`, …).
    ///
    /// - Returns: Season rows in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func referenceSeasons() async throws -> [CatalogReference] {
        try await fetch(path: Self.referencePath("seasons"), as: [CatalogReference].self)
    }

    /// Fetches the sorting catalogue for the catalogue screen.
    ///
    /// - Returns: Sorting rows in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func referenceSorting() async throws -> [CatalogReference] {
        try await fetch(path: Self.referencePath("sorting"), as: [CatalogReference].self)
    }

    /// Fetches the years that occur in the catalogue.
    ///
    /// The endpoint returns a bare array of integers rather than objects, so there is no
    /// localised text to show.
    ///
    /// - Returns: Years in the order the service sends them.
    /// - Throws: `AniLibertyError` mapped from the failure that occurred.
    public func referenceYears() async throws -> [Int] {
        try await fetch(path: Self.referencePath("years"), as: [Int].self)
    }

    private static func referencePath(_ name: String) -> String {
        "\(ServiceURL.apiPrefix)/anime/catalog/references/\(name)"
    }

    private func fetch<T: Decodable>(path: String, as _: T.Type) async throws -> T {
        try await fetch(path: path, method: "GET", as: T.self)
    }

    func fetch<T: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = [],
        token: String? = nil,
        as _: T.Type
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, body: body, query: query, token: token)
        let data = try await send(request)
        return try decode(T.self, from: data)
    }

    func makeRequest(
        path: String,
        method: String,
        body: Data? = nil,
        query: [URLQueryItem] = [],
        token: String? = nil
    ) throws -> URLRequest {
        guard let endpoint = ServiceURL.endpoint(base: configuration.baseURL, path: path) else {
            throw AniLibertyError.invalidURL(path)
        }
        let url = query.isEmpty ? endpoint : endpoint.appending(queryItems: query)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Decodes a payload with the shared, tolerant decoder.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.aniLiberty.decode(type, from: data)
        } catch {
            throw AniLibertyError.decoding(Self.describe(error))
        }
    }

    /// Encodes a request body, mapping the (practically impossible) failure to the kit's
    /// error type.
    static func encode(_ value: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw AniLibertyError.decoding("Could not encode the request body: \(error)")
        }
    }

    /// Performs a request and returns the payload with its status, without judging it.
    func perform(
        _ request: URLRequest,
        over transport: (any HTTPTransport)? = nil
    ) async throws -> (data: Data, status: Int) {
        if Task.isCancelled {
            throw AniLibertyError.cancelled
        }
        let data: Data
        let response: URLResponse
        let sent = request.url?.path ?? "-"
        Self.logger.debug("transport: sending \(sent, privacy: .public)")
        do {
            (data, response) = try await (transport ?? self.transport).data(for: request)
        } catch {
            Self.logger
                .debug("transport: failed \(sent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw AniLibertyError.transportFailure(error)
        }
        Self.logger
            .debug(
                "transport: received \(sent, privacy: .public) status \((response as? HTTPURLResponse)?.statusCode ?? -1, privacy: .public)"
            )
        guard let http = response as? HTTPURLResponse else {
            throw AniLibertyError.network("The server returned a non-HTTP response.")
        }
        return (data, http.statusCode)
    }

    /// Performs a request and rejects any non-2xx status.
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, status) = try await perform(request)
        guard (200 ..< 300).contains(status) else {
            throw AniLibertyError.httpStatus(status)
        }
        return data
    }

    private static func describe(_ error: any Error) -> String {
        String(describing: error)
    }
}

/// Runs `operation` and gives up after `seconds`.
///
/// The tvOS simulator occasionally leaves a request in flight forever — no response, no error, and the
/// per-request timeout does not fire (observed on the profile call: the log recorded the request being
/// sent and then nothing). A watchdog turns that into a visible failure instead of a screen that waits.
func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw AniLibertyError.network("The request did not finish within \(Int(seconds)) seconds.")
        }
        guard let first = try await group.next() else {
            throw AniLibertyError.network("The request produced no result.")
        }
        group.cancelAll()
        return first
    }
}
