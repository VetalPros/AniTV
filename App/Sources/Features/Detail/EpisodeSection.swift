import AniLibertyKit
import SwiftUI

/// The "Серии" block of the detail screen: section title plus the episode grid, in its own focus
/// section so Down/Up walk hero → synopsis → episodes.
struct EpisodeSection: View {
    let episodes: [Episode]
    let playableQuality: (Episode) -> StreamQuality?
    var progressFraction: (UUID) -> Double? = { _ in nil }
    var currentEpisodeID: UUID?
    let onSelect: (Episode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("detail.episodes.title")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
            if episodes.isEmpty {
                Text("detail.episodes.empty")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
            } else {
                EpisodeGrid(
                    episodes: episodes,
                    identifier: "detail.episodeCard",
                    playableQuality: playableQuality,
                    progressFraction: progressFraction,
                    currentEpisodeID: currentEpisodeID,
                    onSelect: onSelect
                )
            }
        }
        .focusSection()
    }
}
