import AniLibertyKit
import SwiftUI

extension AniLibertyError {
    /// Localised, user-facing explanation of a failed request.
    ///
    /// The Kit's `localizedDescription` stays technical for logs; this mapping is the only place
    /// that decides what a viewer reads.
    var userMessageKey: LocalizedStringKey {
        switch self {
        case .invalidURL:
            "error.invalidURL"
        case let .httpStatus(status) where status == 404:
            "error.notFound"
        case let .httpStatus(status) where status == 429:
            "error.rateLimited"
        case let .httpStatus(status) where status >= 500:
            "error.server"
        case .httpStatus:
            "error.http"
        case .decoding:
            "error.decoding"
        case .network:
            "error.network"
        case .cancelled:
            "error.cancelled"
        }
    }
}
