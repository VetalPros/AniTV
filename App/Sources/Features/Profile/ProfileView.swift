import AniLibertyKit
import SwiftUI

/// «Профиль» tab: pairs this TV through an OTP code, then shows the signed-in profile and favourites.
///
/// The tab owns its navigation stack so a favourite pushes the same detail screen the other tabs use.
struct ProfileView: View {
    @State private var model = ProfileViewModel()
    @State private var path: [ReleaseRoute] = []

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
