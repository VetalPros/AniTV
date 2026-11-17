import AniLibertyKit
import Foundation

/// Chooses the session store for the process.
///
/// UI tests run on a simulator whose Keychain may hold a real session, and a test that asserts the
/// signed-out surface must not depend on that. A launch argument therefore swaps in an empty store; no
/// production launch passes it, so the Keychain stays the only store that can ever hold a token.
enum AuthTokenStoreFactory {
    /// Launch argument that makes the app behave as if this TV were never paired.
    static let signedOutArgument = "-uiTestingSignedOut"

    /// Store to use for this process.
    ///
    /// - Parameter arguments: Process arguments; injectable for tests.
    /// - Returns: An empty store when the signed-out argument is present, the Keychain store otherwise.
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AuthTokenStoring {
        arguments.contains(signedOutArgument) ? EmptyTokenStore() : KeychainTokenStore()
    }
}

/// Session store that never holds a token.
///
/// Only reachable through ``AuthTokenStoreFactory`` when a UI test asks for a signed-out app: it saves
/// nothing, so a pairing run cannot leave a token behind in a test process.
struct EmptyTokenStore: AuthTokenStoring {
    func load() async throws -> String? {
        nil
    }

    func save(_: String) async throws {}

    func delete() async throws {}
}
