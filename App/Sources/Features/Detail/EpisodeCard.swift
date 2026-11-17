import AniLibertyKit
import SwiftUI

/// One episode of the grid: the preview fills the card, a scrim carries the text, the length sits in a
/// pill in the corner.
///
/// The card is deliberately not focus-generic: the detail screen lets every card own its focus, while
/// the picker needs to decide which card starts focused. Both cases are served by ``focus``, which the
/// picker passes and the detail screen leaves `nil`.
struct EpisodeCard: View {
    let episode: Episode
    let playableQuality: StreamQuality?
    /// Accessibility identifier; the detail grid and the picker publish different ones.
    var identifier = "detail.episodeCard"
    /// Watched fraction of this episode in `0...1`, or `nil` when it was never played.
    var progressFraction: Double?
    /// Whether this is the episode «Продолжить» would open.
    var isCurrent = false
    /// Focus owner when a parent screen decides where focus starts.
    var focus: FocusState<UUID?>.Binding?

    let action: () -> Void

    @FocusState private var innerFocused: Bool

    /// Whether the card is focused, whichever focus owner the screen uses.
    private var isFocused: Bool {
        if let focus {
            return focus.wrappedValue == episode.id
        }
        return innerFocused
    }

    /// Preview cards are wide: 16:9 matches the artwork the API ships.
    private static let aspectRatio: CGFloat = 16.0 / 9.0

    private var isPlayable: Bool {
        playableQuality != nil
    }

    var body: some View {
        if let focus {
            card.focused(focus, equals: episode.id)
        } else {
            card.focused($innerFocused)
        }
    }

    private var card: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: episode.previewURL)
                // The scrim keeps the text legible over bright frames, like the site's cards.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.15), .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                labels
                // Episodes without a stream stay visible but cannot be selected, hence the grey-out.
                if !isPlayable {
                    Color.black.opacity(0.55)
                }
            }
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { progressBar }
            .overlay(alignment: .bottomTrailing) { durationPill }
            .overlay {
                // The episode «Продолжить» would open is marked, so the grid keeps telling the viewer
                // where they actually are without a per-release position lie.
                RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(isCurrent ? 0.95 : 0), lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0), lineWidth: 3)
            }
        }
        .buttonStyle(PosterCardButtonStyle())
        .scaleEffect(isFocused ? 1.03 : 1)
        .animation(DesignTokens.Motion.focus, value: isFocused)
        .disabled(!isPlayable)
        .opacity(isPlayable ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityIdentifier(identifier)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: episode.displayTitle)
                .font(DesignTokens.Typography.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
            // "N эпизод" with the number emphasised, like the catalogue: the two parts are separate
            // texts so the label stays localisable without markdown in the catalog.
            HStack(spacing: 5) {
                Text(verbatim: "\(episode.ordinal)")
                    .fontWeight(.bold)
                Text("detail.episodeLabel")
            }
            .font(DesignTokens.Typography.cardMeta)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .padding(.trailing, 72)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Thin watched-progress bar pinned to the bottom edge of the artwork.
    @ViewBuilder
    private var progressBar: some View {
        if let progressFraction {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.25))
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(6, proxy.size.width * progressFraction))
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxHeight: .infinity, alignment: .bottom)
            // The card is one accessibility element, so the bar's state travels in its value.
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var durationPill: some View {
        if let duration = episode.localizedDuration {
            Text(verbatim: duration)
                .font(DesignTokens.Typography.cardMeta)
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.7), in: Capsule())
                .padding(14)
        }
    }

    /// VoiceOver hears the episode title, the ordinal and — when the episode cannot be played — why.
    private var accessibilityLabel: String {
        let base = "\(episode.displayTitle), \(episode.ordinal)"
        return isPlayable ? base : "\(base), \(String(localized: "episode.unavailable"))"
    }

    /// Watched percentage as the element's value, empty when the episode has no stored position.
    private var accessibilityValue: String {
        guard let progressFraction else { return "" }
        return "\(Int((progressFraction * 100).rounded()))%"
    }
}
