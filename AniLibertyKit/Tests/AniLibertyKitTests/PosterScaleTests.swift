@testable import AniLibertyKit
import Foundation
import Testing

/// The six poster sizes behind «Размер постеров на главной».
///
/// Two things are promised here: the shipped default stays the 1.5× rail the owner approved (ADR 0036), and
/// the two pinned edges never drift — 100 % is the pre-ADR-0036 rail, 150 % is today's, and the steps between
/// them are linear.
@Suite("Poster scale")
struct PosterScaleTests {
    private func store() throws -> PosterScaleStore {
        let suite = try #require(UserDefaults(suiteName: "tv.anitv.tests.posters.\(UUID().uuidString)"))
        return PosterScaleStore(defaults: suite)
    }

    @Test("The steps are 100…150 in tens, and 150 % is the default")
    func steps() {
        #expect(PosterScale.allCases.map(\.rawValue) == [100, 110, 120, 130, 140, 150])
        #expect(PosterScale.default == .percent150)
        #expect(PosterScale.percent100.step == 0)
        #expect(PosterScale.percent130.step == 3)
        #expect(PosterScale.percent150.step == 5)
    }

    @Test("A fresh install shows 150 %")
    func defaults() async throws {
        #expect(try await store().load() == .percent150)
    }

    @Test("Every step survives a round trip")
    func roundTrip() async throws {
        let store = try store()
        for scale in PosterScale.allCases {
            await store.save(scale)
            #expect(await store.load() == scale)
        }
    }

    @Test("A value that is not a step falls back to the default", arguments: [0, 90, 105, 137, 200, Int.max])
    func invalidValuesFallBackToDefault(rawValue: Int) async throws {
        let suite = try #require(UserDefaults(suiteName: "tv.anitv.tests.posters.\(UUID().uuidString)"))
        suite.set(rawValue, forKey: PosterScaleStore.Key.scale)
        #expect(await PosterScaleStore(defaults: suite).load() == .percent150)
    }

    @Test("A different domain starts from the default")
    func separateDomains() async throws {
        let first = try store()
        await first.save(.percent110)
        #expect(try await store().load() == .percent150)
    }

    @Test("100 % is exactly the rail before ADR 0036")
    func compactEdge() {
        let metrics = PosterScale.percent100.metrics
        #expect(metrics.width == 244)
        #expect(metrics.titleSize == 17)
        #expect(metrics.metaSize == 15)
        #expect(metrics.starSize == 11)
        #expect(metrics.badgeScale == 0.85)
        #expect(metrics.badgeInset == 10)
        #expect(metrics.captionSpacing == 12)
        #expect(metrics.detailsSpacing == 4)
    }

    @Test("150 % is exactly the rail ADR 0036 ships")
    func largeEdge() {
        let metrics = PosterScale.percent150.metrics
        #expect(metrics.width == 366)
        #expect(metrics.titleSize == 24)
        #expect(metrics.metaSize == 20)
        #expect(metrics.starSize == 17)
        #expect(metrics.badgeScale == 1.275)
        #expect(metrics.badgeInset == 15)
        #expect(metrics.captionSpacing == 16)
        #expect(metrics.detailsSpacing == 6)
    }

    @Test("The steps between the edges are linear and rounded to whole points")
    func interpolation() {
        let steps = PosterScale.allCases.map(\.metrics)
        #expect(steps.map(\.width) == [244, 268, 293, 317, 342, 366])
        #expect(steps.map(\.titleSize) == [17, 18, 20, 21, 23, 24])
        #expect(steps.map(\.metaSize) == [15, 16, 17, 18, 19, 20])
        #expect(steps.map(\.starSize) == [11, 12, 13, 15, 16, 17])
        #expect(steps.map(\.badgeInset) == [10, 11, 12, 13, 14, 15])
        #expect(steps.map(\.captionSpacing) == [12, 13, 14, 14, 15, 16])
        #expect(steps.map(\.detailsSpacing) == [4, 4, 5, 5, 6, 6])
        // The flag scale is a factor, not a length: it is compared with a tolerance, not rounded.
        for (actual, expected) in zip(steps.map(\.badgeScale), [0.85, 0.935, 1.02, 1.105, 1.19, 1.275]) {
            #expect(abs(actual - expected) < 0.0005)
        }
    }
}
