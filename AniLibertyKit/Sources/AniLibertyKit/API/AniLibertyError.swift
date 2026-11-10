import Foundation

/// Errors surfaced by `AniLibertyKit`.
///
/// The cases are intentionally coarse: the app maps them onto localised messages, while
/// the associated values stay available for logs and diagnostics.
public enum AniLibertyError: Error, Sendable, Equatable, LocalizedError {
    /// The endpoint URL could not be built from the configured base URL.
    case invalidURL(String)
    /// The server answered with a non-2xx HTTP status.
    case httpStatus(Int)
    /// The payload could not be decoded into the expected model.
    case decoding(String)
    /// The request failed at the transport level.
    case network(String)
    /// The task was cancelled before or during the request.
    case cancelled

    /// Human-readable English description, suitable for logs.
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(path):
            "Could not build a valid URL for path '\(path)'."
        case let .httpStatus(status):
            "The server responded with HTTP status \(status)."
        case let .decoding(details):
            "Could not decode the server response: \(details)"
        case let .network(details):
            "The request failed: \(details)"
        case .cancelled:
            "The request was cancelled."
        }
    }
}

extension AniLibertyError {
    /// Maps any transport error onto the public error type.
    ///
    /// Cancellation keeps its own case so the UI can ignore it silently instead of
    /// showing a failure banner.
    static func transportFailure(_ error: any Error) -> AniLibertyError {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .network(urlError.localizedDescription)
        }
        return .network(String(describing: error))
    }
}
