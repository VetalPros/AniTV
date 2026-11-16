import Foundation

/// A one-time pairing code waiting for the user's confirmation on another device.
///
/// The tvOS client shows ``code`` on screen, the user enters it in an already signed-in
/// client or on the site, and the TV then polls
/// ``AniLibertyClient/loginWithOTP(code:deviceID:)`` until the service starts answering
/// with a token. The service documents the lifetime as roughly five minutes.
///
/// The code is a string on purpose: the API sends it as a string of digits (and may pad
/// it with a leading zero), while only the login request expects an integer.
public struct OTPChallenge: Sendable, Equatable {
    /// Code to display, exactly as the service sent it.
    public let code: String
    /// Moment the code stops being accepted.
    public let expiresAt: Date
    /// Seconds the service said were left when the challenge was issued.
    ///
    /// Use ``secondsRemaining(at:)`` for a live countdown; this snapshot is kept because
    /// the UI shows the server's own estimate right after the request.
    public let remainingSeconds: Double

    /// Creates a challenge; the client always decodes it from the response.
    ///
    /// - Parameters:
    ///   - code: Code to display.
    ///   - expiresAt: Moment the code stops being accepted.
    ///   - remainingSeconds: Lifetime reported by the service, in seconds.
    public init(code: String, expiresAt: Date, remainingSeconds: Double) {
        self.code = code
        self.expiresAt = expiresAt
        self.remainingSeconds = remainingSeconds
    }

    /// Whether the code has expired at `date`.
    ///
    /// - Parameter date: Moment to check; defaults to now.
    /// - Returns: `true` once `date` has reached ``expiresAt``.
    public func isExpired(at date: Date = .now) -> Bool {
        date >= expiresAt
    }

    /// Seconds left at `date`, clamped at zero.
    ///
    /// - Parameter date: Moment to measure from; defaults to now.
    /// - Returns: Remaining lifetime in seconds, never negative.
    public func secondsRemaining(at date: Date = .now) -> Double {
        max(0, expiresAt.timeIntervalSince(date))
    }
}

extension OTPChallenge: Decodable {
    private enum CodingKeys: String, CodingKey {
        case otp
        case remainingTime
    }

    /// The `otp` object of the response.
    private struct Payload: Decodable {
        let code: String
        let expiredAt: Date
    }

    /// Decodes the `{ "otp": { … }, "remaining_time": … }` envelope.
    ///
    /// `remaining_time` is a float in reality while the schema claims an integer, so it
    /// is decoded as `Double`; when it is missing, the lifetime is derived from
    /// ``expiresAt``.
    ///
    /// - Parameter decoder: Decoder positioned on the response body.
    /// - Throws: `DecodingError` when the code or the expiry is missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decode(Payload.self, forKey: .otp)

        code = payload.code
        expiresAt = payload.expiredAt
        let reported = try container.decodeIfPresent(Double.self, forKey: .remainingTime)
        remainingSeconds = max(0, reported ?? payload.expiredAt.timeIntervalSinceNow)
    }
}
