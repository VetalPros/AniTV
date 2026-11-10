import Foundation

/// Actor-based client for the public AniLiberty REST API.
///
/// Only the endpoints needed by the first slice are implemented: the latest-releases
/// feed and a single release with its episodes. URL building, headers and error mapping
/// live here, so the app never touches `URLSession` directly.
public actor AniLibertyClient {
    private let configuration: AniLibertyConfiguration
    private let transport: any HTTPTransport

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - configuration: Base URL and `User-Agent`; the default value is production.
    ///   - transport: HTTP seam; the default value uses `URLSession` with caching on.
    public init(
        configuration: AniLibertyConfiguration = .default,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
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

    private func fetch<T: Decodable>(path: String, as _: T.Type) async throws -> T {
        let request = try makeRequest(path: path)
        let data = try await send(request)
        do {
            return try JSONDecoder.aniLiberty.decode(T.self, from: data)
        } catch {
            throw AniLibertyError.decoding(Self.describe(error))
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = ServiceURL.endpoint(base: configuration.baseURL, path: path) else {
            throw AniLibertyError.invalidURL(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .useProtocolCachePolicy
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        if Task.isCancelled {
            throw AniLibertyError.cancelled
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw AniLibertyError.transportFailure(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AniLibertyError.network("The server returned a non-HTTP response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AniLibertyError.httpStatus(http.statusCode)
        }
        return data
    }

    private static func describe(_ error: any Error) -> String {
        String(describing: error)
    }
}
