import Foundation

/// A generic `{ value, description }` pair the API returns for enumerated fields
/// such as the release type or the season.
///
/// The service sends a machine-readable `value` (`"TV"`, `"autumn"`) together with a
/// localised Russian `description` (`"ТВ"`, `"Осень"`). Either side may be missing, so
/// the UI has to fall back to the other one, or to nothing at all.
public struct NamedValue: Sendable, Equatable, Decodable {
    /// Machine-readable value, for example `"TV"` or `"autumn"`.
    public let value: String?
    /// Localised Russian label, for example `"ТВ"` or `"Осень"`.
    public let description: String?
}
