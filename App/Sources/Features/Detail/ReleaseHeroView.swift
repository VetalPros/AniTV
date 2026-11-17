import AniLibertyKit
import SwiftUI

/// Every focusable control of the detail screen's hero block.
///
/// The screen opens on `.resume`/`.play` (ADR 0012) — `.favorite` and `.synopsisToggle` are only ever
/// reached with the remote, never by the default focus.
enum DetailHeroAction: Hashable {
    case resume
    case play
    case favorite
    case synopsisToggle
}

/// Hero block of the release detail screen: poster, title, metadata, the action row with «Продолжить»,
/// «Смотреть» and the favourite heart, plus the one-line feedback the actions can produce.
///
/// It is a focus section of its own, so Down/Up move between blocks instead of hunting for a neighbour.
struct ReleaseHeroView: View {
    let release: Release
    let model: ReleaseDetailViewModel
    var focus: FocusState<DetailHeroAction?>.Binding
    let onResume: () -> Void
    let onPlay: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 52) {
            RemoteImage(url: model.posterURL)
                // `RemoteImage` fills whatever frame it is given, so both dimensions have to come from
                // the 2:3 poster ratio — a width-only frame leaves the height unbounded and slices the
                // artwork.
                .frame(
                    width: DesignTokens.heroPosterWidth,
                    height: DesignTokens.heroPosterWidth / DesignTokens.posterAspectRatio
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 16)

            VStack(alignment: .leading, spacing: 20) {
                titles
                metadataRow
                blockingNotice
                actionRow
            }
            .frame(maxWidth: 1000, alignment: .leading)
        }
        // Sections make the vertical chain predictable: the engine moves between blocks, so Down from
        // the hero lands on the synopsis control instead of jumping over it into the grid.
        .focusSection()
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: release.title)
                .font(DesignTokens.Typography.detailTitle)
                .foregroundStyle(.white)
            if let originalTitle = release.originalTitle {
                Text(verbatim: originalTitle)
                    .font(DesignTokens.Typography.detailOriginalTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 10) {
            if let year = release.year {
                GlassBadge(title: LocalizedStringKey(String(year)), systemImage: "calendar")
            }
            if let type = release.type?.description {
                GlassBadge(title: LocalizedStringKey(type))
            }
            if let ageRating = release.ageRating {
                GlassBadge(title: LocalizedStringKey(ageRating))
            }
            if let rating = release.averageRating {
                RatingPill(rating: rating)
            }
            if let total = release.episodesTotal {
                GlassBadge(title: "detail.episodesTotal \(total)", systemImage: "rectangle.stack")
            }
            if release.isOngoing == true {
                GlassBadge(title: "badge.ongoing", tint: Palette.accent.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var blockingNotice: some View {
        if release.isBlockedByGeo {
            noticeRow(systemImage: "globe", text: "detail.blocked.geo", tint: Palette.accent)
        } else if release.isBlockedByCopyrights {
            noticeRow(systemImage: "lock", text: "detail.blocked.copyrights", tint: Palette.accent)
        }
    }

    private func noticeRow(systemImage: String, text: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(text)
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Primary and secondary actions share one row: «Продолжить», «Смотреть» and the favourite heart.
    ///
    /// The heart is last on purpose: Left/Right walks resume → play → heart, and the vertical chain out of
    /// the hero is untouched. It never takes the default focus.
    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if model.resumeRequest != nil {
                    resumeButton
                }
                playButton
                favoriteButton
            }
            favoriteFeedback
        }
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Label("detail.resume", systemImage: "play.circle")
                .font(.system(size: 22, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .focused(focus, equals: .resume)
        .accessibilityIdentifier("detail.resumeButton")
    }

    private var playButton: some View {
        Button(action: onPlay) {
            Label("detail.watch", systemImage: "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .disabled(!model.isPlayable)
        .opacity(model.isPlayable ? 1 : 0.5)
        .accessibilityHint(Text(model.playableEpisode?.displayTitle ?? ""))
        .focused(focus, equals: .play)
        .accessibilityIdentifier("detail.playButton")
    }

    private var favoriteButton: some View {
        Button(action: onFavorite) {
            Image(systemName: model.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(model.isFavorite ? Palette.accent : Color.white)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .focused(focus, equals: .favorite)
        .accessibilityIdentifier("detail.favoriteButton")
        .accessibilityLabel(model.isFavorite ? Text("detail.favorite.remove") : Text("detail.favorite.add"))
    }

    /// One line under the actions: how to pair this TV, or why the favourite was not saved.
    @ViewBuilder
    private var favoriteFeedback: some View {
        if let message = model.favoriteMessage {
            Group {
                switch message {
                case .signedOut:
                    Text("detail.favorite.signedOut")
                        .foregroundStyle(.secondary)
                case let .failed(error):
                    Text(error.userMessageKey)
                        .foregroundStyle(Palette.accent)
                }
            }
            .font(DesignTokens.Typography.callout)
            .accessibilityIdentifier("detail.favoriteMessage")
        }
    }
}
