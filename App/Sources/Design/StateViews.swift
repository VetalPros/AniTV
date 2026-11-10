import SwiftUI

/// Centred progress state for a screen that has nothing to show yet.
struct LoadingStateView: View {
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Glass card explaining a failure and offering exactly one recovery action.
struct ErrorStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var retryTitle: LocalizedStringKey = "common.retry"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(retryTitle, action: retry)
                .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 44)
        .frame(maxWidth: 820)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.screenInset)
    }
}

/// Glass card for a screen that is legitimately without content.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 40)
        .frame(maxWidth: 820)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.screenInset)
    }
}
