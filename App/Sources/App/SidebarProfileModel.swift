import AniLibertyKit
import Foundation
import Observation

/// Who is watching, for the sidebar header — the place the system TV app puts the account too (ADR 0032).
///
/// The shell cannot ask the profile *screen* for the name: that screen is a cover and may never have been
/// opened. So the header keeps its own small read of `GET profile`, refreshed when the cover closes
/// because that is the only way the account can change.
@MainActor
@Observable
final class SidebarProfileModel {
    enum State: Equatable {
        case loading
        case signedOut
        /// Display name and the avatar to show; `avatar` is nil when the account has none.
        case signedIn(name: String, avatar: URL?)
        /// The account exists but the profile could not be read; the header still offers the profile.
        case failed
    }

    private(set) var state: State = .loading

    private let client: AniLibertyClient
    private let tokenStore: AuthTokenStoring

    init(
        client: AniLibertyClient = AniLibertyClient(),
        tokenStore: AuthTokenStoring = AuthTokenStoreFactory.make()
    ) {
        self.client = client
        self.tokenStore = tokenStore
    }

    func reload() async {
        let token: String?
        do {
            token = try await tokenStore.load()
        } catch {
            state = .signedOut
            return
        }
        guard let token else {
            state = .signedOut
            return
        }

        do {
            let profile = try await client.profile(token: token)
            let name = profile.nickname ?? profile.login ?? ""
            state = name.isEmpty
                ? .failed
                : .signedIn(name: name, avatar: profile.avatarThumbnailURL ?? profile.avatarURL)
        } catch {
            state = .failed
        }
    }
}
