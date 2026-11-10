import SwiftUI

/// Small Liquid Glass capsule used for flags on posters and the detail screen.
struct GlassBadge: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var tint: Color?

    var body: some View {
        if let tint {
            chip.glassEffect(.regular.tint(tint), in: Capsule())
        } else {
            chip.glassEffect(.regular, in: Capsule())
        }
    }

    private var chip: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(DesignTokens.Typography.badge)
            }
            Text(title)
                .font(DesignTokens.Typography.badge)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
