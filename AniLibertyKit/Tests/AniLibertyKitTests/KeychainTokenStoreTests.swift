@testable import AniLibertyKit
import Security
import XCTest

/// Round-trip against the **real** Keychain.
///
/// A host without Keychain access (unsigned test binaries, CI without a keychain, a
/// sandbox that forbids `SecItemAdd`) cannot run this, so the test skips itself instead
/// of pretending it passed. Only statuses that mean «the host cannot do this» are
/// tolerated; any other failure is a real failure of `KeychainTokenStore`.
///
/// The store is pointed at a throwaway service name, so the developer's real session
/// token is never touched.
final class KeychainTokenStoreTests: XCTestCase {
    /// Statuses that mean the test host refuses Keychain access, not that the store is
    /// broken.
    private static let unavailableStatuses: Set<OSStatus> = [
        errSecMissingEntitlement,
        errSecInteractionNotAllowed,
        errSecNotAvailable,
    ]

    func testRealKeychainRoundTrip() async throws {
        let store = KeychainTokenStore(
            service: "tv.anitv.tests.\(UUID().uuidString)",
            account: "sessionToken"
        )
        let token = "test-token-\(UUID().uuidString)"

        do {
            try await store.save(token)
        } catch let error as KeychainError {
            try XCTSkipIf(
                Self.unavailableStatuses.contains(error.status),
                "Keychain is not available to this test host during save (OSStatus \(error.status))."
            )
            throw error
        }

        let firstRead = try await store.load()
        XCTAssertEqual(firstRead, token)

        // Saving again replaces the item instead of failing with errSecDuplicateItem.
        let replacement = "test-token-\(UUID().uuidString)"
        try await store.save(replacement)
        let secondRead = try await store.load()
        XCTAssertEqual(secondRead, replacement)

        try await store.delete()
        let afterDelete = try await store.load()
        XCTAssertNil(afterDelete)

        // Deleting a missing item is not an error.
        try await store.delete()
    }

    func testKeychainErrorDoesNotLeakTheToken() {
        let error = KeychainError(status: errSecMissingEntitlement)

        XCTAssertEqual(error.errorDescription, "The Keychain rejected the operation (OSStatus -34018).")
        XCTAssertFalse(error.errorDescription?.contains("token") ?? true)
    }
}
