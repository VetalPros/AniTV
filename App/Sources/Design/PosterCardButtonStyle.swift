import SwiftUI

/// Press feedback for poster and episode cards.
///
/// Focus chrome is drawn by the cards themselves (they know their own artwork), so this style only
/// owns the deliberate, small press state.
struct PosterCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
