import AniLibertyKit
import SwiftUI

/// Full-screen playback: system player, skip-intro control, failure surface and the exit path back
/// to the detail screen.
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerModel
    /// The player screen hands focus to its own control when it opens: the system transport bar only
    /// appears after a press, so an unreachable control would otherwise stay unreachable for good.
    @FocusState private var qualityFocus: QualityFocus?
    /// The quality chooser is a modal: the system player steals focus on the first arrow press, so a
    /// row drawn over it can be focused once and never navigated (ADR 0014).
    @State private var isQualityPickerPresented = false

    /// Focus target of the quality row: the pill of one stream.
    private enum QualityFocus: Hashable {
        case quality(StreamQuality)
    }

    init(request: PlaybackRequest) {
        _model = State(initialValue: PlayerModel(request: request))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            PlayerViewController(player: model.player)
                .ignoresSafeArea()

            qualityOverlay
            skipOverlay
            failureOverlay
        }
        .onAppear {
            model.start()
            takeDefaultFocus()
        }
        .onDisappear { model.stop() }
        .onExitCommand { dismiss() }
        .fullScreenCover(isPresented: $isQualityPickerPresented) {
            QualityPickerScreen(
                sources: model.sources,
                selectedQuality: model.selectedQuality,
                onSelect: { quality in
                    model.selectQuality(quality)
                    isQualityPickerPresented = false
                },
                onClose: { isQualityPickerPresented = false }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.screen")
        // Announced by VoiceOver and asserted by the UI tests: the stream the player is running.
        .accessibilityValue(Text(verbatim: "\(model.selectedQuality.rawValue)p"))
    }

    /// Hands focus to the pill of the running stream. Requested twice, because the cover transition
    /// swallows the first request (ADR 0012).
    private func takeDefaultFocus() {
        let control = QualityFocus.quality(model.selectedQuality)
        Task {
            // The player opens with the system transport bar up, and every arrow press goes to it
            // until it hides itself a few seconds later.
            try? await Task.sleep(for: .milliseconds(6000))
            qualityFocus = control
            try? await Task.sleep(for: .milliseconds(600))
            qualityFocus = control
        }
    }

    /// Quality control, bottom-trailing: one glass pill per stream of the episode.
    ///
    /// The system transport bar owns every direction the remote has while it is up, and the items the
    /// sanctioned `transportBarCustomMenuItems` hook draws there are not reachable by the focus engine
    /// on tvOS 27.2 (ADR 0014): they render, but no press ever focuses them. The pills are therefore
    /// ordinary focus targets of the screen, and the one that matches the running stream holds focus
    /// when the player opens, so the control is reachable without hunting for it.
    @ViewBuilder
    private var qualityOverlay: some View {
        if model.sources.count > 1 {
            VStack {
                HStack {
                    Spacer(minLength: 0)
                    qualityRow
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 72)
            .padding(.top, 44)
        }
    }

    private var qualityRow: some View {
        Button {
            isQualityPickerPresented = true
        } label: {
            Label {
                Text(verbatim: "\(model.selectedQuality.rawValue)p")
            } icon: {
                Image(systemName: "rectangle.stack")
            }
            .font(DesignTokens.Typography.callout)
        }
        .buttonStyle(.glass)
        .focused($qualityFocus, equals: .quality(model.selectedQuality))
        .defaultFocus($qualityFocus, .quality(model.selectedQuality), priority: .userInitiated)
        .accessibilityIdentifier("player.qualityButton")
        .accessibilityHint(Text("player.quality.hint"))
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
