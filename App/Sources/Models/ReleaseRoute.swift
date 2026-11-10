import AniLibertyKit
import Foundation

/// Hashable snapshot of a release, used as the value of a `NavigationStack` path.
///
/// Routing carries only what the destination screen needs to draw its hero before the detail
/// request lands, so the push never flashes an empty screen.
struct ReleaseRoute: Hashable {
    let id: Int
    let alias: String
    let title: String
    let subtitle: String
    let posterURL: URL?

    init(release: Release) {
        id = release.id
        alias = release.alias
        title = release.title
        subtitle = release.subtitle
        posterURL = release.posterURL
    }
}
