import Foundation

/// One row of the catalogue reference endpoints.
///
/// The service returns three slightly different shapes for its enumerations:
///
/// * types and seasons carry `{ value, description }`;
/// * sorting additionally carries a short `label` next to the long `description`.
///
/// One type covers all three so the screen can drive every picker with the same view.
/// Machine values are what ``CatalogFilter`` expects; the human text is what the picker
/// shows.
public struct CatalogReference: Sendable, Equatable, Decodable {
    /// Machine-readable value, for example `"TV"`, `"winter"` or `"FRESH_AT_DESC"`.
    public let value: String?
    /// Short human-readable label, present on the sorting endpoint only.
    public let label: String?
    /// Longer human-readable text, usually the picker row title.
    public let description: String?

    /// Best available human-readable title: label, then description, then the raw value.
    public var title: String? {
        label ?? description ?? value
    }
}
