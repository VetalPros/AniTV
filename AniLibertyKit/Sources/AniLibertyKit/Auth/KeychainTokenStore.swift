import Foundation
import Security

/// Failure of a `SecItem*` call.
///
/// The error carries the raw `OSStatus` and nothing else: no token, no attributes, so it
/// is safe to log and to show in diagnostics.
public struct KeychainError: Error, Sendable, Equatable, LocalizedError {
    /// Status returned by the Security framework.
    public let status: OSStatus

    /// Creates an error around a Security status.
    ///
    /// - Parameter status: Status returned by the Security framework.
    public init(status: OSStatus) {
        self.status = status
    }

    /// Human-readable description, deliberately free of secrets.
    public var errorDescription: String? {
        "The Keychain rejected the operation (OSStatus \(status))."
    }
}

/// Keychain-backed ``AuthTokenStoring`` implementation.
///
/// The token lives in a single generic-password item identified by a service/account
/// pair, as `kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlock`. That
/// accessibility level is deliberate: the value must survive a reboot without the user
/// unlocking the device first (the TV is often started by somebody else), while still
/// being unreadable from a locked device after a cold boot.
///
/// `UserDefaults` is never involved: it stores the token in a plist that other processes
/// and backups can read.
public struct KeychainTokenStore: AuthTokenStoring, Sendable {
    /// Service attribute used by the app's token item.
    public static let defaultService = "tv.anitv.client"

    /// Account attribute used by the app's token item.
    public static let defaultAccount = "sessionToken"

    private let service: String
    private let account: String

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - service: `kSecAttrService` of the item; tests use a throwaway value.
    ///   - account: `kSecAttrAccount` of the item.
    public init(
        service: String = KeychainTokenStore.defaultService,
        account: String = KeychainTokenStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    /// Reads the stored token.
    ///
    /// - Returns: The token, or `nil` when no item exists.
    /// - Throws: ``KeychainError`` for any status other than success or "not found".
    public func load() async throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainError(status: errSecDecode)
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Stores a token, replacing any previous one.
    ///
    /// - Parameter token: Session token issued by the service.
    /// - Throws: ``KeychainError`` when the item cannot be written.
    public func save(_ token: String) async throws {
        try await delete()

        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    /// Removes the stored token; a missing item counts as success.
    ///
    /// - Throws: ``KeychainError`` when the item exists but cannot be removed.
    public func delete() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    /// Query addressing the single token item of this store.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
