import AniLibertyKit
import SwiftUI

/// Six-column poster grid. The first card takes default focus so the grid is usable with the
/// remote the moment the tab appears.
struct ReleasePosterGrid: View {
    let releases: [Release]
    let onSelect: (Release) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: DesignTokens.gridSpacing, alignment: .top),
        count: DesignTokens.posterColumns
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.gridRowSpacing) {
            ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                PosterCard(release: release, takesDefaultFocus: index == 0) {
                    onSelect(release)
                }
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
    }
}
