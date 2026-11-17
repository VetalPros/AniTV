import AniLibertyKit
import SwiftUI

/// The skip hint that lives inside the player's own overlay, above the video but below the system
/// transport bar.
///
/// It is hosted by `AVPlayerViewController.contentOverlayView`, which is the view tvOS gives clients for
/// custom player chrome: it participates in the focus engine, so the remote can actually reach these
/// buttons — the reason the previous floating SwiftUI overlay never got focus.
struct SkipHintView: View {
    /// Segment to offer, `nil` when the hint has to stay out of the way (leaving an empty overlay).
    let skip: SkipTimecode?
    let onSkip: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        if let skip {
            hint(for: skip)
        }
    }

    private func hint(for skip: SkipTimecode) -> some View {
        HStack(spacing: 14) {
            Button(action: onSkip) {
                Label(title(for: skip), systemImage: "forward.end.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("player.skipButton")

            Button(action: onDismiss) {
                Text("player.skip.dismiss")
                    .font(.system(size: 19, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("player.skipDismissButton")
        }
        .padding(10)
        .accessibilityElement(children: .contain)
    }

    private func title(for skip: SkipTimecode) -> LocalizedStringKey {
        switch skip.kind {
        case .opening: "player.skip.opening"
        case .ending: "player.skip.ending"
        }
    }
}
