import AniLibertyKit
import SwiftUI

/// One horizontal rail on «Главная»: a single-line title and a row of posters the remote walks left to
/// right (ADR 0031).
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
    /// Invisible freshness marker, present only when a UI test asked for one (see ``RefreshProbe``).
    var refreshProbe: RefreshProbeStamp?
    var takesDefaultFocus = false
    let onSelect: (Release) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
            .accessibilityIdentifier(railIdentifier)
        }
        // The probe sits in the header's corner rather than in the stack: it must not add a single point
        // of height to a header whose whole purpose is to be compact.
        .overlay(alignment: .topLeading) {
            refreshProbe
        }
    }

    private var header: some View {
        Text(title)
            .font(DesignTokens.Typography.railTitle)
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.screenInset)
    }
}
