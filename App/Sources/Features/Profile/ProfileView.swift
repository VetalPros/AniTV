import AniLibertyKit
import SwiftUI

/// «Профиль» tab: pairs this TV through an OTP code, then shows the signed-in profile and favourites.
///
/// The tab owns its navigation stack so a favourite pushes the same detail screen the other tabs use.
struct ProfileView: View {
    @State private var model = ProfileViewModel()
    /// Owned by the shell, so the section survives its own view being recreated (ADR 0028 §7).
    @Binding var path: [ReleaseRoute]
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AniTVBackground()
                content
            }
            .navigationDestination(for: ReleaseRoute.self) { route in
                ReleaseDetailView(route: route)
            }
        }
        .task { await model.loadIfNeeded() }
        .onAppear { Task { await model.setVisible(scenePhase == .active) } }
        .onDisappear { Task { await model.setVisible(false) } }
        .onReceive(NotificationCenter.default.publisher(for: .anitvFavoritesChanged)) { _ in
            Task { await model.favoritesDidChangeElsewhere() }
        }
        .onChange(of: scenePhase) { _, phase in
            Task { await model.setVisible(phase == .active) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            LoadingStateView(message: "profile.loading")
        case .pairing:
            PairingView(model: model)
        case .signedIn:
            SignedInProfileView(model: model) { release in
                path.append(ReleaseRoute(release: release))
            }
        case let .failed(error):
            failure(error)
        case .expired:
            expired
        }
    }

    /// The stored token no longer opens the account. Nothing is deleted until the viewer says so, so a
    /// network hiccup on the service side cannot sign the TV out on its own.
    private var expired: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "screen.profile.title", subtitle: "screen.profile.subtitle")
            VStack(alignment: .leading, spacing: 22) {
                Text("profile.expired.message")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 900, alignment: .leading)
                Button {
                    Task { await model.reconnect() }
                } label: {
                    Label("profile.expired.reconnect", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("profile.reconnect")
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, 40)
            Spacer(minLength: 0)
        }
    }

    private func failure(_ error: AniLibertyError) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "screen.profile.title", subtitle: "screen.profile.subtitle")
            ErrorStateView(
                title: "profile.failed.title",
                message: error.userMessageKey,
                retry: { Task { await model.refresh() } }
            )
            .frame(maxHeight: .infinity)
        }
    }
}
