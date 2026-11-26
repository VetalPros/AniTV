import AniLibertyKit
import SwiftUI

/// Full-screen playback: system player, the single skip hint, failure surface and the exit path back to the
/// detail screen.
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    /// Episode, source and the release's next episode, resolved by the detail screen.
    private let request: PlaybackRequest
    /// Asked when the hint offers the next episode; the detail screen owns that navigation, exactly like the
    /// episode picker.
    private let onNextEpisode: () -> Void
    @State private var model: PlayerModel?

    init(request: PlaybackRequest, onNextEpisode: @escaping () -> Void = {}) {
        self.request = request
        self.onNextEpisode = onNextEpisode
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let model {
                player(for: model)
                failureOverlay(for: model)
            }
        }
        .task {
            await prepareModel()
        }
        .onDisappear { model?.stop() }
        .onExitCommand { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.screen")
        // Announced by VoiceOver and asserted by the UI tests: the stream the player is running.
        .accessibilityValue(Text(verbatim: qualityDescription))
    }

    /// Stream the player is running, exposed to VoiceOver and to the UI tests.
    private var qualityDescription: String {
        guard let model else { return "unknown" }
        return "\(model.selectedQuality.rawValue)p"
    }

    private func player(for model: PlayerModel) -> some View {
        PlayerViewController(
            player: model.player,
            qualities: model.sources.map(\.quality),
            selectedQuality: model.selectedQuality,
            onSelectQuality: model.selectQuality,
            hint: model.hint,
            onHintAction: model.performHintAction
        )
        .ignoresSafeArea()
    }

    /// Reads the settings once and starts the session with them.
    ///
    /// The player never watches ``PlaybackSettingsStore``: changing a switch in another tab while the player
    /// is open is out of scope, because the segment the viewer is in would have to be re-evaluated mid-flight.
    private func prepareModel() async {
        guard model == nil else { return }
        let settings = await PlaybackSettingsStore().load()
        let created = PlayerModel(request: request, settings: settings)
        created.onNextEpisode = { [onNextEpisode] in
            onNextEpisode()
        }
        model = created
        created.start()
    }

    @ViewBuilder
    private func failureOverlay(for model: PlayerModel) -> some View {
        if let playbackError = model.playbackError {
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Palette.accent)
                Text("player.failed.title")
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.white)
                Text(verbatim: playbackError)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("player.close") { dismiss() }
                    .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 44)
            .frame(maxWidth: 860)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityElement(children: .contain)
        }
    }
}
