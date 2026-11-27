import AniLibertyKit
import Observation

/// The «Обновления в избранном» rail: the viewer's favourites, newest change first.
///
/// The service reports no per-release "what changed" text, so recency is read from `fresh_at` — the field
/// the service moves when an episode lands (ADR 0031). Signed-out viewers get `.signedOut` and the rail is
/// not drawn at all: an empty favourite list and a missing account look the same to the viewer only if we
/// tell them apart ourselves.
@MainActor
@Observable
final class FavoritesUpdatesViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded([Release])
        case empty
        case signedOut
        case failed(AniLibertyError)
    }

    /// How many cards the rail keeps. More than fits on screen, because a rail is meant to be walked.
    private static let railLimit = 20

    private(set) var state: State = .idle

    private let client: AniLibertyClient
    private let tokenStore: AuthTokenStoring
    private let railLimit: Int

    init(
        client: AniLibertyClient = AniLibertyClient(),
        tokenStore: AuthTokenStoring = AuthTokenStoreFactory.make(),
        railLimit: Int = FavoritesUpdatesViewModel.railLimit
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.railLimit = railLimit
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await reload()
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

        state = .loading
        do {
            // One page is enough for a rail, and asking for more would be a request storm for nothing.
            let page = try await client.favorites(token: token, page: 1, limit: railLimit)
            let sorted = page.releases.sorted { lhs, rhs in
                (lhs.freshAt ?? lhs.updatedAt ?? .distantPast) > (rhs.freshAt ?? rhs.updatedAt ?? .distantPast)
            }
            state = sorted.isEmpty ? .empty : .loaded(Array(sorted.prefix(railLimit)))
        } catch let error as AniLibertyError {
            state = .failed(error)
        } catch {
            state = .failed(.network(String(describing: error)))
        }
    }
}
