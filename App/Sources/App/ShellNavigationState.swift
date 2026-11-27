import AniLibertyKit
import Observation

/// Navigation paths of the sidebar sections, owned by the shell and not by the sections themselves
/// (ADR 0028 §7).
///
/// `TabView` is free to destroy the content of a tab that is not selected, and a `@State` path inside that
/// content dies with it: that is how an open release used to disappear the moment the viewer looked at
/// «Настройки» and came back. Holding the paths above the tabs makes a section survive its own view being
/// recreated, which is the behavioural difference the routing tests of `NavigationStateUITests` measure.
///
/// «Медиатека» gets a fourth path when its screen exists.
@MainActor
@Observable
final class ShellNavigationState {
    var home: [ReleaseRoute] = []
    var search: [ReleaseRoute] = []
    var profile: [ReleaseRoute] = []

}
