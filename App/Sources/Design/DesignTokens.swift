import SwiftUI

/// Single source of truth for layout, typography and motion used across the tvOS UI.
///
/// tvOS is a fixed-geometry, ten-foot platform: spacing is deliberately generous and type is
/// larger than its iOS counterpart so that it survives the focus halo and viewing distance.
enum DesignTokens {
    // MARK: Layout

    /// Horizontal breathing room between screen content and the display edges.
    static let screenInset: CGFloat = 72
    /// Space between the top of a section and its title. Clears the collapsed sidebar pill, which sits in
    /// the top-left corner (ADR 0028) — every section title starts below it.
    static let screenTopInset: CGFloat = 56
    /// Vertical rhythm between major blocks on a screen.
    static let sectionSpacing: CGFloat = 40
    /// Poster columns for the latest-releases grid (six posters fit a 1080p canvas comfortably).
    static let posterColumns = 6
    static let gridSpacing: CGFloat = 28
    static let gridRowSpacing: CGFloat = 44
    /// 2:3 is the poster aspect ratio used by the upstream catalogue.
    static let posterAspectRatio: CGFloat = 2.0 / 3.0
    static let cardCornerRadius: CGFloat = 18
    static let heroPosterWidth: CGFloat = 300

    // MARK: Typography

    enum Typography {
        static let screenTitle = Font.system(size: 46, weight: .bold, design: .rounded)
        static let screenSubtitle = Font.system(size: 21, weight: .medium)
        static let sectionTitle = Font.system(size: 27, weight: .semibold)
        /// Title of a home rail: reads as a section, but louder than one inside a card list.
        static let railTitle = Font.system(size: 32, weight: .semibold)
        static let detailTitle = Font.system(size: 54, weight: .bold, design: .rounded)
        static let detailOriginalTitle = Font.system(size: 22, weight: .medium)
        static let body = Font.system(size: 20, weight: .regular)
        static let callout = Font.system(size: 17, weight: .medium)
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        static let cardMeta = Font.system(size: 15, weight: .regular)
        static let badge = Font.system(size: 14, weight: .semibold)
    }

    enum Motion {
        /// Focus changes and small layout reveals share one curve so the UI feels of one piece.
        static let focus = Animation.smooth(duration: 0.2)
        static let reveal = Animation.smooth(duration: 0.25)
    }
}

/// Brand palette. The accent value is duplicated in `Assets.xcassets/AccentColor` so that system
/// chrome (focus tint, progress indicators) and custom views agree.
enum Palette {
    static let accent = Color(red: 1.0, green: 0.34, blue: 0.30)
    static let backdropTop = Color(white: 0.12)
    static let backdropBottom = Color.black
    static let posterPlaceholder = Color(white: 0.17)
}
