import Foundation

/// Settings of the AniLiberty HTTP client.
///
/// The type is a plain value so previews and tests can build a client pointed at a local
/// stub without any global state.
public struct AniLibertyConfiguration: Sendable, Equatable {
    /// Site root the client builds its endpoint URLs from.
    ///
    /// Production value is `https://aniliberty.top`; it is exposed so tests can redirect
    /// the client to a stub host.
    public var baseURL: URL
    /// `User-Agent` sent with every request; it identifies the client politely.
    public var userAgent: String

    /// Production configuration: the official site root and the repository user agent.
    public static let `default` = AniLibertyConfiguration(
        baseURL: ServiceURL.base,
        userAgent: "AniTV/0.1 (+https://github.com/VetalPros/AniTV)"
    )

    /// Creates a configuration with an explicit site root and user agent.
    ///
    /// - Parameters:
    ///   - baseURL: Site root, normally `https://aniliberty.top`.
    ///   - userAgent: Value of the `User-Agent` header.
    public init(baseURL: URL, userAgent: String) {
        self.baseURL = baseURL
        self.userAgent = userAgent
    }
}
