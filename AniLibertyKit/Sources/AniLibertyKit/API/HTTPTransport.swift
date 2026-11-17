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

    /// Session built as given: no cache is reinstated, so ``ephemeral()`` really is clean.
    private init(clean sessionConfiguration: URLSessionConfiguration) {
        session = URLSession(configuration: sessionConfiguration)
    }

    /// Performs the request through the underlying `URLSession`.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// A transport with no cache and no cookies, for the pairing handshake.
    ///
    /// The live service answers `otp/login` from the app's shared session with
    /// 403 `{"message": "This action is unauthorized."}` while the same request from a session that has
    /// no accumulated cache or cookies gets the documented answer. A one-time-code exchange has nothing
    /// to cache, so it gets a clean session instead of inheriting the app's.
    public static func ephemeral() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSessionTransport(clean: configuration)
    }
}
