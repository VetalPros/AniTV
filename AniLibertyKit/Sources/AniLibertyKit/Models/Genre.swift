import Foundation

/// A genre of a release, for example `Экшен` or `Фэнтези`.
///
/// The API posts the genre name in Russian inside `name`; it is optional because some
/// older payloads only carry the numeric identifier.
public struct Genre: Sendable, Equatable, Decodable {
    /// Stable numeric genre identifier.
    public let id: Int
    /// Localised Russian genre name, when the API provides one.
    public let name: String?
}
