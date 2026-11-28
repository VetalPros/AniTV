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
    /// the top-left corner (ADR 0028): the system already reserves 120 pt above the content (window safe
    /// area plus the `TabView`'s pill reserve) and the pill's body ends at about 109 pt, so this is our own
    /// last lever. Forty is the floor — 0 would leave 11 pt of clearance (ADR 0035).
    static let screenTopInset: CGFloat = 40
    /// Vertical rhythm between major blocks on a screen.
    static let sectionSpacing: CGFloat = 40
    /// Poster columns for the latest-releases grid (six posters fit a 1080p canvas comfortably).
    static let posterColumns = 6
    static let gridSpacing: CGFloat = 28
    static let gridRowSpacing: CGFloat = 44
    /// 2:3 is the poster aspect ratio used by the upstream catalogue.
    static let posterAspectRatio: CGFloat = 2.0 / 3.0
    /// Width of one poster on the «Главная» rails: half again the 244 pt the rail used to draw, so the
    /// artwork fills the vertical space the owner actually watches. The six-column grid keeps its own
    /// width (a flexible column of about 273 pt on a 1920 pt canvas) and is deliberately not affected —
    /// see ``PosterCardStyle`` for the caption that grows with this tile.
    static let railCardWidth: CGFloat = 366
    static let cardCornerRadius: CGFloat = 18
    static let heroPosterWidth: CGFloat = 300

    // MARK: Typography

    enum Typography {
        static let screenTitle = Font.system(size: 46, weight: .bold, design: .rounded)
        static let screenSubtitle = Font.system(size: 21, weight: .medium)
        /// Header of a top-level screen: the same pair as ``screenTitle``/``screenSubtitle``, compressed so
        /// the block does not eat a fifth of the canvas. Kept separate because the detail and picker screens
        /// use the larger pair on purpose.
        static let screenTitleCompact = Font.system(size: 38, weight: .bold, design: .rounded)
        static let screenSubtitleCompact = Font.system(size: 18, weight: .medium)
        static let sectionTitle = Font.system(size: 27, weight: .semibold)
        /// Title of a home rail. One line above the posters, so it reads as a label rather than a screen
        /// header — but at the tvOS body size, because the owner reads it from the sofa (ADR 0035).
        static let railTitle = Font.system(size: 29, weight: .semibold)
        static let detailTitle = Font.system(size: 54, weight: .bold, design: .rounded)
        static let detailOriginalTitle = Font.system(size: 22, weight: .medium)
        static let body = Font.system(size: 20, weight: .regular)
        static let callout = Font.system(size: 17, weight: .medium)
        static let cardTitle = Font.system(size: 17, weight: .semibold)
        static let cardMeta = Font.system(size: 15, weight: .regular)
        /// Caption of a rail poster. The grid pair above stays as it is; the rail's tiles are 1.5× wider, so
        /// their title and metadata step up by the same factor and keep the proportion the owner reads from
        /// the sofa (17 → 25.5 ≈ 24, 15 → 22.5 ≈ 20; rounded down so two title lines still fit under 549 pt
        /// of artwork).
        static let railCardTitle = Font.system(size: 24, weight: .semibold)
        static let railCardMeta = Font.system(size: 20, weight: .regular)
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
