import Foundation

/// Broadcast that the account's favourite releases changed.
///
/// The release screen can add or remove a title and the «Профиль» tab owns the list that shows them.
/// They are separate view models in separate tabs with no shared parent state, so the change travels as a
/// notification: the detail screen posts, the profile listens and re-reads the favourites immediately
/// instead of waiting for its timer. Without it a title favourited in the app was invisible in the app
/// until the next interval — the report that started this.
extension Notification.Name {
    /// Posted after the service confirmed a favourite was added or removed.
    static let anitvFavoritesChanged = Notification.Name("tv.anitv.favoritesChanged")
}
