import AniLibertyKit
import SwiftUI

/// Signed-in state of the «Профиль» tab: who is signed in, the favourites grid and sign-out.
struct SignedInProfileView: View {
    let model: ProfileViewModel
    let onSelectRelease: (Release) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
                header
                favoritesSection
            }
            .padding(.bottom, 88)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(title: "screen.profile.title", subtitle: "screen.profile.subtitle") {
                Button {
                    Task { await model.signOut() }
                } label: {
                    Label("profile.signOut", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 20, weight: .medium))
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("profile.signOut")
            }
            identity
                .padding(.horizontal, DesignTokens.screenInset)
        }
        // The freshness caption that used to close this block was debug information; only the UI-test
        // probe remains, and it draws nothing (see ``RefreshProbe``).
        .overlay(alignment: .bottomTrailing) {
            RefreshProbe.stamp(RefreshProbe.profileIdentifier, date: model.updatedAt)
        }
    }

    private var identity: some View {
        HStack(spacing: 26) {
            RemoteImage(url: model.profile?.avatarURL)
                .frame(width: 132, height: 132)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 2)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: model.profile?.displayName ?? "")
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("profile.displayName")
                if let login = model.profile?.login, !login.isEmpty {
                    Text(verbatim: "@\(login)")
                        .font(DesignTokens.Typography.cardMeta)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Favourites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("profile.favorites.title")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.screenInset)

            if let error = model.favoritesError {
                favoritesFailure(error)
            } else if model.favorites.isEmpty {
                Text("profile.favorites.empty")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.screenInset)
            } else {
                ReleasePosterGrid(releases: model.favorites, takesDefaultFocus: false, onSelect: onSelectRelease)
                if model.hasMoreFavorites {
                    loadMore
                }
            }
        }
    }

    private func favoritesFailure(_ error: AniLibertyError) -> some View {
        ErrorStateView(
            title: "profile.favorites.failed",
            message: error.userMessageKey,
            retry: { Task { await model.loadFavorites(reset: true) } }
        )
    }

    private var loadMore: some View {
        Button {
            Task { await model.loadMoreFavorites() }
        } label: {
            HStack(spacing: 10) {
                if model.isPagingFavorites {
                    ProgressView()
                }
                Text("profile.favorites.more")
            }
        }
        .buttonStyle(.glass)
        .disabled(model.isPagingFavorites)
        .accessibilityIdentifier("profile.favoritesMore")
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.screenInset)
    }
}
