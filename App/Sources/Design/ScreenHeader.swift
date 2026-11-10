import SwiftUI

/// Title + subtitle block shared by every top-level screen, with an optional trailing action.
struct ScreenHeader<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey
    private let trailing: Trailing

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(DesignTokens.Typography.screenSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            trailing
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, 56)
        .padding(.bottom, 30)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
