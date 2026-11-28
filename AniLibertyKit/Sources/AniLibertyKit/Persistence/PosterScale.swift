import Foundation

/// How big a poster on «Главная» is drawn, as a percentage of the rail the app shipped before ADR 0036.
///
/// The viewer picks one of six steps in «Настройки». Two edges are **pinned** and everything between them is
/// linear: 100 % is exactly the rail before ADR 0036 (244 pt wide, caption 17/15, star 11, flags ×0.85,
/// 12/4 gaps) and 150 % is exactly the rail ADR 0036 introduced (366 pt, 24/20, 17, ×1.275, 16/6). The
/// numbers live in the Kit next to the setting rather than in the app's design tokens, because they are the
/// contract of what a stored value means and can be unit-tested without a simulator; the app only turns
/// ``PosterMetrics`` into `Font`s and spacing.
public enum PosterScale: Int, CaseIterable, Sendable, Identifiable {
    /// The compact edge: the rail before ADR 0036.
    case percent100 = 100
    /// One step above the compact edge.
    case percent110 = 110
    /// Two steps above the compact edge.
    case percent120 = 120
    /// Three steps above the compact edge.
    case percent130 = 130
    /// Four steps above the compact edge.
    case percent140 = 140
    /// The large edge: the rail ADR 0036 ships, and what a fresh install starts with.
    case percent150 = 150

    /// What a fresh install shows: the 1.5× rail the owner picked in ADR 0036.
    public static let `default` = PosterScale.percent150

    public var id: Int {
        rawValue
    }

    /// Position of this step between the two edges, `0` at 100 % and `5` at 150 %.
    public var step: Int {
        (rawValue - PosterScale.percent100.rawValue) / 10
    }

    /// Geometry of one rail poster at this scale.
    public var metrics: PosterMetrics {
        PosterMetrics(scale: self)
    }
}

/// Geometry of one «Главная» rail poster: everything that has to follow the tile when the viewer changes
/// the size in «Настройки».
///
/// Lengths are whole points (`rounded()`), which reproduces the owner's table
/// 244/268/293/317/342/366 exactly. Rounding to the nearest point instead of down moves a step by at most
/// 0.5 pt, and the caption keeps the same ratio to the tile at every step, so two title lines still fit.
public struct PosterMetrics: Sendable, Equatable {
    /// Width of the tile; the artwork is 2:3, so it is also 1.5× this tall.
    public let width: CGFloat
    /// Point size of the release title under the artwork.
    public let titleSize: CGFloat
    /// Point size of the rating / subtitle line under the title.
    public let metaSize: CGFloat
    /// Point size of the rating star.
    public let starSize: CGFloat
    /// Scale factor of the access flags drawn over the artwork.
    public let badgeScale: CGFloat
    /// Inset of the flags from the artwork's corner.
    public let badgeInset: CGFloat
    /// Gap between the artwork and the caption block.
    public let captionSpacing: CGFloat
    /// Gap between the title and the metadata line.
    public let detailsSpacing: CGFloat

    /// Interpolates the geometry between the two pinned edges.
    ///
    /// - Parameter scale: Step the viewer picked.
    public init(scale: PosterScale) {
        let steps = CGFloat(PosterScale.allCases.count - 1)
        let progress = CGFloat(scale.step) / steps

        // Weights the two edges and rounds the result to a whole point. Written as `a * (1 - t) + b * t` so
        // that the endpoints are exactly the literals and never a floating-point near miss.
        func between(_ compact: CGFloat, _ large: CGFloat) -> CGFloat {
            (compact * (1 - progress) + large * progress).rounded()
        }

        width = between(244, 366)
        titleSize = between(17, 24)
        metaSize = between(15, 20)
        starSize = between(11, 17)
        badgeInset = between(10, 15)
        captionSpacing = between(12, 16)
        detailsSpacing = between(4, 6)
        // A scale factor, not a length: rounding it would make a badge jump by a pixel for no reason.
        badgeScale = 0.85 * (1 - progress) + 1.275 * progress
    }
}

/// Storage seam for ``PosterScale`` so the app can inject a throwaway domain in tests.
public protocol PosterScaleStoring: Sendable {
    /// Reads the stored scale.
    ///
    /// - Returns: The stored value, or ``PosterScale/default`` when nothing usable is stored.
    func load() async -> PosterScale
    /// Writes the scale, replacing what was there.
    ///
    /// - Parameter scale: Value to persist.
    func save(_ scale: PosterScale) async
}

/// `UserDefaults`-backed ``PosterScaleStoring``.
///
/// These are preferences, not secrets. A stored number that is not one of the six steps — a value nobody
/// chose, or a leftover from a future build — reads as ``PosterScale/default``, so a broken domain can never
/// leave the app at a size the viewer did not pick.
public final class PosterScaleStore: PosterScaleStoring {
    /// Keys the store writes.
    public enum Key {
        /// Poster scale on «Главная», in percent.
        public static let scale = "tv.anitv.home.posterScale"
    }

    private let defaults: DefaultsBox

    /// Creates a store.
    ///
    /// - Parameter defaults: Domain to persist into — `.standard` in the app, a throwaway suite in tests.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = DefaultsBox(defaults)
    }

    /// Reads the stored scale.
    ///
    /// - Returns: The stored step, or ``PosterScale/default`` when the key was never written.
    public func load() async -> PosterScale {
        // A missing key reads as 0, and 0 is not a step, so one lookup covers "never written" and "written
        // by something that does not use this type" alike.
        PosterScale(rawValue: defaults.value.integer(forKey: Key.scale)) ?? .default
    }

    /// Stores the scale.
    ///
    /// - Parameter scale: Value to persist.
    public func save(_ scale: PosterScale) async {
        defaults.value.set(scale.rawValue, forKey: Key.scale)
    }
}
