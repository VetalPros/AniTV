import AniLibertyKit
import SwiftUI

/// Focusable poster tile: artwork, flag badges, title and metadata line.
struct PosterCard: View {
    let release: Release
    var takesDefaultFocus: Bool = false
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                artwork
                details
            }
        }
        .buttonStyle(PosterCardButtonStyle())
        .focused($isFocused)
        .defaultFocus($isFocused, takesDefaultFocus)
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(DesignTokens.Motion.focus, value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(release.title). \(release.subtitle)"))
        .accessibilityIdentifier("latest.posterCard")
    }

    private var artwork: some View {
        RemoteImage(url: release.posterURL)
            .aspectRatio(DesignTokens.posterAspectRatio, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                badges.padding(10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isFocused ? 0.9 : 0.12),
                        lineWidth: isFocused ? 3 : 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: isFocused ? 26 : 12, y: 12)
    }

    private var badges: some View {
        HStack(spacing: 6) {
            if release.isOngoing == true {
                GlassBadge(title: "badge.ongoing", tint: Palette.accent.opacity(0.9))
            }
            if release.isBlockedByGeo {
                GlassBadge(title: "badge.geo", systemImage: "globe")
            } else if release.isBlockedByCopyrights {
                GlassBadge(title: "badge.copyright", systemImage: "lock")
            }
        }
        .scaleEffect(0.85, anchor: .topLeading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: release.title)
                .font(DesignTokens.Typography.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                if let rating = release.averageRating {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Text(verbatim: rating.formatted(.number.precision(.fractionLength(1))))
                        .font(DesignTokens.Typography.cardMeta)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(verbatim: release.subtitle)
                        .font(DesignTokens.Typography.cardMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
