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
                onSelectQuality: model.selectQuality
            )
            .ignoresSafeArea()

            skipOverlay
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
    private var skipOverlay: some View {
        if let skip = model.activeSkip {
            VStack {
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    Button(skipTitle(for: skip)) {
                        model.skipActiveSegment()
                    }
                    .buttonStyle(.glassProminent)
                    .padding(.trailing, 72)
                    .padding(.bottom, 140)
                }
            }
        }
    }

    private func skipTitle(for skip: SkipTimecode) -> LocalizedStringKey {
        switch skip.kind {
        case .opening: "player.skip.opening"
        case .ending: "player.skip.ending"
        }
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
