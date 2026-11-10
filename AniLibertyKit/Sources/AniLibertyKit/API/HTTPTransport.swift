import Foundation

/// Async HTTP seam used by `AniLibertyClient` and `ImageCache`.
///
/// The app must not use this protocol directly; it exists so the kit can be tested
/// without network access and so a different transport can be injected later.
public protocol HTTPTransport: Sendable {
    /// Performs `request` and returns the raw payload together with the response.
    ///
    /// - Parameter request: Fully built request, including headers.
    /// - Returns: The body bytes and the server response.
    /// - Throws: Any transport-level failure, including cancellation.
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// `URLSession`-backed transport.
///
/// The shared `URLCache` stays enabled, which is what the politeness rules ask for:
/// repeated poster and feed requests are served from the cache instead of the service.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport around a `URLSession`.
    ///
    /// - Parameter configuration: Session configuration. When it carries no cache, the
    ///   shared cache is installed.
    public init(configuration: URLSessionConfiguration = .default) {
        let sessionConfiguration = configuration
        if sessionConfiguration.urlCache == nil {
            sessionConfiguration.urlCache = URLCache.shared
        }
        session = URLSession(configuration: sessionConfiguration)
    }

    /// Performs the request through the underlying `URLSession`.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
