import Foundation

extension JSONDecoder {
    /// Decoder configured for AniLiberty payloads.
    ///
    /// * keys arrive in `snake_case`, so `.convertFromSnakeCase` is applied;
    /// * ISO-8601 dates are accepted with and without fractional seconds, plus the plain
    ///   `yyyy-MM-dd` form the service uses for publish dates.
    ///
    /// Models keep every date optional, so a future format change degrades one field
    /// instead of failing an entire payload.
    static var aniLiberty: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseAniLibertyDate(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported date format: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

/// Parses the date formats the API is known to send.
///
/// The formatters are created per call on purpose: `ISO8601DateFormatter` and
/// `DateFormatter` are not `Sendable`, so sharing them across actors would be a
/// data race. Payloads contain a handful of dates at most, so the cost is negligible.
private func parseAniLibertyDate(_ raw: String) -> Date? {
    let withFractionalSeconds = ISO8601DateFormatter()
    withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractionalSeconds.date(from: raw) {
        return date
    }

    let withoutFractionalSeconds = ISO8601DateFormatter()
    withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
    if let date = withoutFractionalSeconds.date(from: raw) {
        return date
    }

    let dayOnly = DateFormatter()
    dayOnly.locale = Locale(identifier: "en_US_POSIX")
    dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
    dayOnly.dateFormat = "yyyy-MM-dd"
    return dayOnly.date(from: raw)
}
