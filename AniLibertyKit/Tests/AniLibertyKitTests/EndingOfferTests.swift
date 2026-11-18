@testable import AniLibertyKit
import Foundation
import Testing

/// The ending rule: skip past the credits when something follows them, offer the next episode when they run
/// into the end of the file. Both cases exist in the live catalogue, so the boundary is asserted explicitly.
@Suite("Ending offer")
struct EndingOfferTests {
    private static func ending(start: Double, end: Double) -> SkipTimecode {
        SkipTimecode(kind: .ending, start: start, end: end, releaseEpisodeID: UUID())
    }

    @Test("Credits that run into the end of the file offer the next episode")
    func shortTail() {
        let ending = Self.ending(start: 1300, end: 1409)
        // 9 s of tail, the shape measured on the first episode of a fresh release.
        #expect(EndingOfferResolver.offer(ending: ending, duration: 1418, hasNextEpisode: true) == .nextEpisode)
    }

    @Test("A tail worth watching keeps the viewer in the episode")
    func longTail() {
        let ending = Self.ending(start: 1306, end: 1395)
        // 26 s after the credits, the shape measured on episodes that carry an insert there.
        #expect(EndingOfferResolver.offer(ending: ending, duration: 1421, hasNextEpisode: true) == .skip)
    }

    @Test("The threshold is the boundary, not an approximation")
    func boundary() {
        let ending = Self.ending(start: 100, end: 200)
        #expect(EndingOfferResolver.offer(ending: ending, duration: 215, hasNextEpisode: true) == .nextEpisode)
        #expect(EndingOfferResolver.offer(ending: ending, duration: 216, hasNextEpisode: true) == .skip)
    }

    @Test("No next episode means no offer to start one")
    func lastEpisode() {
        let ending = Self.ending(start: 1300, end: 1409)
        #expect(EndingOfferResolver.offer(ending: ending, duration: 1418, hasNextEpisode: false) == .skip)
    }

    @Test("An unknown duration keeps the viewer in the episode")
    func unknownDuration() {
        let ending = Self.ending(start: 1300, end: 1409)
        #expect(EndingOfferResolver.offer(ending: ending, duration: nil, hasNextEpisode: true) == .skip)
        #expect(EndingOfferResolver.offer(ending: ending, duration: 0, hasNextEpisode: true) == .skip)
    }
}
