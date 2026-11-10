import AniLibertyKit
import Foundation

extension AniLibertyError {
    /// Normalises anything thrown by the Kit into the Kit's own error type, so every feature has a
    /// single value to present instead of duplicating the mapping.
    ///
    /// Lives on the Kit type rather than on individual view models: the extension is nonisolated by
    /// default, which keeps the mapping callable from any actor context without opting out of the
    /// main actor.
    static func mapped(_ error: Error) -> AniLibertyError {
        if let error = error as? AniLibertyError {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network(nsError.localizedDescription)
        }
        return .network(error.localizedDescription)
    }
}
