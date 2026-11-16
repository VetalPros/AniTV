import Foundation

/// Stable per-install identifier used by the OTP pairing handshake.
///
/// The service needs the same device id when the code is requested and when it is polled, so the value
/// has to outlive a launch. It is **not** a secret — it carries no rights on its own — which is why it
/// may live in `UserDefaults`; the session token never does.
enum DeviceIdentity {
    private static let storageKey = "tv.anitv.deviceIdentifier"

    /// Device id for this install, generated on first use.
    ///
    /// - Parameter defaults: Domain to persist into; injectable for tests.
    /// - Returns: The existing identifier or a freshly generated one.
    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: storageKey)
        return generated
    }

    /// Replaces the stored identifier and returns the new one.
    ///
    /// The service answers a repeated request for the *same* device id with the pending code and its
    /// unchanged expiry — verified against the live API — so «Обновить код» can only produce a fresh code
    /// by asking on behalf of a new device id. The new value is persisted straight away, so the app keeps
    /// polling the code it actually shows and stays consistent across launches.
    ///
    /// - Parameter defaults: Domain to persist into; injectable for tests.
    /// - Returns: The new identifier.
    static func rotate(defaults: UserDefaults = .standard) -> String {
        let generated = UUID().uuidString
        defaults.set(generated, forKey: storageKey)
        return generated
    }
}
