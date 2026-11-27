import AniLibertyKit
import SwiftUI

/// One horizontal rail on «Главная»: a title, an optional freshness line, and a row of posters the remote
/// walks left to right (ADR 0031).
struct HomeRail: View {
    /// Width of one card. The grid on the other screens fits six columns; a rail shows about six and a
    /// half, so the next card is always peeking in and the rail reads as scrollable.
    private static let cardWidth: CGFloat = 244

    let title: LocalizedStringKey
    let releases: [Release]
    /// Accessibility identifier of a card, so a test can tell the rails apart.
    let cardIdentifier: String
    /// Accessibility identifier of the rail itself.
    let railIdentifier: String
    /// Optional freshness instant shown under the title.
    var captionDate: Date?
    var captionIdentifier: String?
    var takesDefaultFocus = false
    let onSelect: (Release) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: DesignTokens.gridSpacing) {
                    ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
                        PosterCard(
                            release: release,
                            takesDefaultFocus: takesDefaultFocus && index == 0,
                            identifier: cardIdentifier
                        ) {
                            onSelect(release)
                        }
                        .frame(width: Self.cardWidth)
                    }
                }
                .padding(.horizontal, DesignTokens.screenInset)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
            .accessibilityIdentifier(railIdentifier)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignTokens.Typography.railTitle)
                .foregroundStyle(.white)
            if let captionDate {
                // The catalogue's format key carries a `%@`, so the time goes in through the format
                // rather than through string concatenation. The accessibility value keeps seconds: the
                // auto-refresh test watches it to prove the rail reloaded.
                Text(
                    verbatim: String(
                        format: String(localized: "common.updatedAt %@"),
                        captionDate.formatted(date: .omitted, time: .shortened)
                    )
                )
                .font(DesignTokens.Typography.cardMeta)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(captionIdentifier ?? "home.rail.caption")
                .accessibilityValue(Text(verbatim: captionDate.formatted(date: .omitted, time: .standard)))
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
    }
}
