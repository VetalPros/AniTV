import AniLibertyKit
import SwiftUI

/// Presentation of a poster tile.
///
/// The six-column grid («Каталог», «Поиск») draws the compact pair of metrics; a «Главная» rail draws the
/// size the viewer picked in «Настройки», 244…366 pt wide (``PosterScale``), and every other number — the
/// caption, the rating star, the flags, the gaps — follows it in proportion. Everything else about the tile
/// — corner radius, focus chrome, shadow — stays shared, so a rail poster still reads as the same card.
enum PosterCardStyle {
    case grid
    case rail(PosterScale)

    /// Tile geometry. The grid is pinned to the compact edge, which is exactly the 17/15 pair the six-column
    /// layout has always drawn; a rail interpolates between the two edges owned by the Kit.
    var metrics: PosterMetrics {
        switch self {
        case .grid: PosterScale.percent100.metrics
        case let .rail(scale): scale.metrics
        }
    }

    var titleFont: Font {
        .system(size: metrics.titleSize, weight: .semibold)
    }

    var metaFont: Font {
        .system(size: metrics.metaSize)
    }

    var starSize: CGFloat {
        metrics.starSize
    }

    /// Flags are drawn below their nominal size so they do not fight the artwork; the rail keeps the same
    /// ratio against its tile instead of letting a 14 pt capsule shrink against 366 pt of art.
    var badgeScale: CGFloat {
        metrics.badgeScale
    }

    var badgeInset: CGFloat {
        metrics.badgeInset
    }

    /// Gap between the artwork and the caption block.
    var captionSpacing: CGFloat {
        metrics.captionSpacing
    }

    /// Gap between the title and the metadata line.
    var detailsSpacing: CGFloat {
        metrics.detailsSpacing
    }
}

/// Focusable poster tile: artwork, flag badges, title and metadata line.
struct PosterCard: View {
    let release: Release
    var style: PosterCardStyle = .grid
    var takesDefaultFocus: Bool = false
    /// Accessibility identifier this card publishes; a rail passes its own so tests can tell rails apart.
    var identifier = "latest.posterCard"
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: style.captionSpacing) {
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
        .accessibilityIdentifier(identifier)
    }

    private var artwork: some View {
        RemoteImage(url: release.posterURL)
            .aspectRatio(DesignTokens.posterAspectRatio, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                badges.padding(style.badgeInset)
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

    /// Access flags only. «Онгоинг» is deliberately absent here: the owner reads it on the release screen,
    /// where the hero still carries the badge; on a poster it only covered artwork.
    private var badges: some View {
        HStack(spacing: 6) {
            if release.isBlockedByGeo {
                GlassBadge(title: "badge.geo", systemImage: "globe")
            } else if release.isBlockedByCopyrights {
                GlassBadge(title: "badge.copyright", systemImage: "lock")
            }
        }
        .scaleEffect(style.badgeScale, anchor: .topLeading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: style.detailsSpacing) {
            Text(verbatim: release.title)
                .font(style.titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                if let rating = release.averageRating {
                    Image(systemName: "star.fill")
                        .font(.system(size: style.starSize, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Text(verbatim: rating.formatted(.number.precision(.fractionLength(1))))
                        .font(style.metaFont)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(verbatim: release.subtitle)
                        .font(style.metaFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
