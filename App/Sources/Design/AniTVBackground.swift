import SwiftUI

/// App-wide backdrop: a deep neutral gradient with a single accent bloom behind the header.
///
/// It exists so screens do not sit on a flat black rectangle while posters and glass controls
/// remain the brightest things on screen.
struct AniTVBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Palette.backdropTop, Palette.backdropBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            RadialGradient(
                colors: [Palette.accent.opacity(0.22), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 760
            )
            .frame(height: 760)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
