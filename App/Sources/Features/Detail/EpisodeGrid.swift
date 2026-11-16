import AniLibertyKit
import SwiftUI

/// Three-column grid of episode cards, shared by the detail screen and the picker.
///
/// Built with the eager `Grid` on purpose: `LazyVGrid` only instantiates the cells that intersect the
/// visible area, and on the detail screen the first row sits below the fold — no cell would ever exist,
/// nothing would be focusable, so focus could never scroll down to the list and the list would never
/// materialise. The grids hold a handful of rows, so building them eagerly costs nothing.
struct EpisodeGrid: View {
    let episodes: [Episode]
    /// Accessibility identifier every card carries, so each screen can be queried on its own.
    let identifier: String
    /// Focus owner when the enclosing screen decides which card starts focused, as the picker does.
    var focus: FocusState<UUID?>.Binding?
    let playableQuality: (Episode) -> StreamQuality?
    let onSelect: (Episode) -> Void

    private static let columns = 3
    private static let spacing: CGFloat = 20

    var body: some View {
        let rowCount = (episodes.count + Self.columns - 1) / Self.columns
        Grid(alignment: .leading, horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(0 ..< rowCount, id: \.self) { row in
                GridRow(alignment: .top) {
                    ForEach(columnRange(of: row), id: \.self) { index in
                        let episode = episodes[index]
                        EpisodeCard(
                            episode: episode,
                            playableQuality: playableQuality(episode),
                            identifier: identifier,
                            focus: focus
                        ) {
                            onSelect(episode)
                        }
                    }
                }
            }
        }
    }

    private func columnRange(of row: Int) -> Range<Int> {
        let start = row * Self.columns
        return start ..< min(start + Self.columns, episodes.count)
    }
}
