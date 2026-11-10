import SwiftUI

/// Shared skeleton for destinations that exist in the navigation but carry no functionality yet.
///
/// It keeps the shell honest: the tab appears, says what it will be, and never pretends to offer a
/// feature that is not built.
struct PlaceholderScreen: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        ZStack {
            AniTVBackground()
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: title, subtitle: subtitle)
                Spacer(minLength: 0)
                VStack(spacing: 18) {
                    Image(systemName: systemImage)
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(message)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 760)
                }
                .padding(.horizontal, 56)
                .padding(.vertical, 44)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DesignTokens.screenInset)
                Spacer(minLength: 0)
                Spacer(minLength: 0)
            }
        }
    }
}

/// "Каталог" tab: reserved for browsing and filtering, not implemented in this slice.
struct CatalogPlaceholderView: View {
    var body: some View {
        PlaceholderScreen(
            title: "screen.catalog.title",
            subtitle: "screen.catalog.subtitle",
            message: "placeholder.catalog.message",
            systemImage: "square.grid.2x2"
        )
    }
}

/// "Профиль" tab: authorization is explicitly out of scope, so there is no sign-in affordance.
struct ProfilePlaceholderView: View {
    var body: some View {
        PlaceholderScreen(
            title: "screen.profile.title",
            subtitle: "screen.profile.subtitle",
            message: "placeholder.profile.message",
            systemImage: "person.crop.circle"
        )
    }
}
