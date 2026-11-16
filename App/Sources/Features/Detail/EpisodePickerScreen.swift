import AniLibertyKit
import SwiftUI

/// Modal episode chooser behind «Смотреть»: the same card grid as the detail screen, with its own focus
/// engine and a single job — hand the chosen episode back to the caller.
///
/// Menu closes it without playing anything; the caller starts playback once the cover is dismissed, so
/// the player never fights the picker for the screen.
struct EpisodePickerScreen: View {
    let episodes: [Episode]
    /// Episode that owns focus when the picker opens: the one the player would have started.
    let initialFocusEpisodeID: UUID?
    let playableQuality: (Episode) -> StreamQuality?
    let onSelect: (Episode) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedEpisodeID: UUID?

    var body: some View {
        ZStack {
            AniTVBackground()
            VStack(alignment: .leading, spacing: 28) {
                Text("detail.episodes.title")
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(.white)
                ScrollView(.vertical) {
                    EpisodeGrid(
                        episodes: episodes,
                        identifier: "detail.pickerEpisodeCard",
                        focus: $focusedEpisodeID,
                        playableQuality: playableQuality,
                        onSelect: onSelect
                    )
                    .padding(.bottom, 48)
                }
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.vertical, 48)
        }
        .onAppear(perform: takeDefaultFocus)
        .onExitCommand { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("episodePicker.screen")
    }

    /// Claims focus for the intended episode. The assignment happens on the next run loop turn because
    /// the cover is often still animating in when the grid appears, and the focus engine drops requests
    /// made during the transition.
    private func takeDefaultFocus() {
        guard let initialFocusEpisodeID else { return }
        Task {
            focusedEpisodeID = initialFocusEpisodeID
            try? await Task.sleep(for: .milliseconds(400))
            focusedEpisodeID = initialFocusEpisodeID
        }
    }
}
