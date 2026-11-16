import AniLibertyKit
import SwiftUI

/// Signed-out state of the «Профиль» tab: the code to confirm on the site or in the mobile app, its
/// countdown, and the way to ask for a fresh one.
struct PairingView: View {
    let model: ProfileViewModel
    @FocusState private var isRefreshFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "screen.profile.title", subtitle: "screen.profile.subtitle")
            HStack(alignment: .top, spacing: 56) {
                codePanel
                explanation
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, 24)
            Spacer(minLength: 0)
        }
    }

    // MARK: Code

    private var codePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("profile.pairing.codeLabel")
                .font(DesignTokens.Typography.cardTitle)
                .foregroundStyle(.secondary)
            // A placeholder that reads as "no code yet" instead of a solid bar: six em dashes at this
            // size touch each other and look like a broken label.
            Text(verbatim: model.challenge?.code ?? "· · · · · ·")
                .font(.system(size: 132, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("profile.pairingCode")
            status
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
        .frame(minWidth: 640, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        if let challenge = model.challenge, challenge.isExpired(at: .now) {
            Text("profile.pairing.expired")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(Palette.accent)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("profile.pairing.expires \(model.secondsRemaining)")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityIdentifier("profile.pairingCountdown")
            }
        }
    }

    // MARK: Explanation and action

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("profile.pairing.explanation")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .frame(maxWidth: 780, alignment: .leading)
            Text("profile.pairing.waiting")
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(.white.opacity(0.7))
            if let error = model.pairingError {
                Text(error.userMessageKey)
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(Palette.accent)
            }
            Button {
                Task { await model.requestNewCode() }
            } label: {
                Label("profile.pairing.refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .focused($isRefreshFocused)
            .accessibilityIdentifier("profile.refreshCode")
        }
        .padding(.top, 12)
    }
}
