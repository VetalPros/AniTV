import AniLibertyKit
import SwiftUI

/// One row of the flat episode list: preview frame, title, length and a play affordance.
struct EpisodeCard: View {
    let episode: Episode
    let playableQuality: StreamQuality?
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private var isPlayable: Bool {
        playableQuality != nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                RemoteImage(url: episode.previewURL)
                    .frame(width: 176, height: 99)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: episode.displayTitle)
                        .font(DesignTokens.Typography.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let duration = episode.localizedDuration {
                        Text(verbatim: duration)
                            .font(DesignTokens.Typography.cardMeta)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let qualityLabel {
                        Text(verbatim: qualityLabel)
                            .font(DesignTokens.Typography.cardMeta)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("episode.unavailable")
                            .font(DesignTokens.Typography.cardMeta)
                            .foregroundStyle(Palette.accent.opacity(0.9))
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isPlayable ? "play.circle.fill" : "slash.circle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.white.opacity(isFocused && isPlayable ? 1 : 0.55))
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.85 : 0), lineWidth: 2.5)
            }
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.015 : 1)
        .animation(DesignTokens.Motion.focus, value: isFocused)
        .disabled(!isPlayable)
        .opacity(isPlayable ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: episode.displayTitle))
    }

    /// Short technical label ("480p" / "720p" / "1080p"); `nil` means the episode cannot be played.
    private var qualityLabel: String? {
        switch playableQuality {
        case .sd480: "480p"
        case .hd720: "720p"
        case .uhd1080: "1080p"
        case nil: nil
        }
    }
}
