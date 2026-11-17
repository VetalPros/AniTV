import AniLibertyKit
import SwiftUI

/// Full-screen playback: system player, skip-intro control, failure surface and the exit path back
/// to the detail screen.
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerModel

    init(request: PlaybackRequest) {
        _model = State(initialValue: PlayerModel(request: request))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            PlayerViewController(
                player: model.player,
                qualities: model.sources.map(\.quality),
                selectedQuality: model.selectedQuality,
                onSelectQuality: model.selectQuality,
                skip: model.visibleSkip,
                onSkip: model.skipActiveSegment,
                onDismissSkip: model.dismissSkipHint,
                onPlayerSelect: { model.setPlaybackControlsOpen(!model.isPlaybackControlsOpen) }
            )
            .ignoresSafeArea()

            failureOverlay
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onExitCommand { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.screen")
        // Announced by VoiceOver and asserted by the UI tests: the stream the player is running.
        .accessibilityValue(Text(verbatim: "\(model.selectedQuality.rawValue)p"))
    }

    @ViewBuilder
    private var failureOverlay: some View {
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
