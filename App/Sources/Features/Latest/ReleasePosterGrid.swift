import AniLibertyKit
import SwiftUI

/// Six-column poster grid. The first card takes default focus so the grid is usable with the
/// remote the moment the tab appears.
struct ReleasePosterGrid: View {
    let releases: [Release]
    /// Whether the first card claims default focus. Screens that own a control above the grid (the
    /// catalogue's search field) pass `false`, otherwise entering the screen jumps into the grid.
    var takesDefaultFocus = true
    let onSelect: (Release) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: DesignTokens.gridSpacing, alignment: .top),
        count: DesignTokens.posterColumns
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.gridRowSpacing) {
            ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                PosterCard(release: release, takesDefaultFocus: takesDefaultFocus && index == 0) {
                    onSelect(release)
                }
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
    }
}
