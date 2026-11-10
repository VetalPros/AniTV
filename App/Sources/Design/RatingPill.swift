import SwiftUI

/// Compact "★ 8.0" glass pill shown on posters and in the detail metadata row.
struct RatingPill: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "star.fill")
                .font(.system(size: 11, weight: .bold))
            Text(verbatim: rating.formatted(.number.precision(.fractionLength(1))))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(Palette.accent.opacity(0.85)), in: Capsule())
    }
}
