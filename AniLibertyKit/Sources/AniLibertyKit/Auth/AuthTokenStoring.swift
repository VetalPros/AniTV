import Foundation

/// Persistence seam for the session token.
///
/// The app talks to this protocol instead of a concrete store, so previews and tests can
/// inject an in-memory fake. Methods are asynchronous because a Keychain call may be
/// implemented asynchronously later, and because the production store is shared between
/// isolated contexts.
///
/// Implementations must treat the token as a secret: it may be returned, never logged,
/// never embedded into an error message.
public protocol AuthTokenStoring: Sendable {
    /// Reads the stored token.
    ///
    /// - Returns: The token, or `nil` when nobody is signed in.
    /// - Throws: A store-specific failure; the error must not contain the token itself.
    func load() async throws -> String?

    /// Stores a token, replacing any previous one.
    ///
    /// - Parameter token: Session token issued by the service.
    /// - Throws: A store-specific failure; the error must not contain the token itself.
    func save(_ token: String) async throws

    /// Removes the stored token.
    ///
    /// Deleting a token that is not there is not an error.
    ///
    /// - Throws: A store-specific failure.
    func delete() async throws
}
