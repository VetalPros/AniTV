@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Playback progress rules")
struct PlaybackProgressTests {
    @Test("A position inside the opening seconds is not resumable")
    func belowThreshold() {
        for position in [0, 1, 5, 14.9] {
            #expect(Self.progress(position: position, duration: 1440).isResumable == false)
        }
    }

    @Test("The lower threshold itself is resumable")
    func thresholdIsInclusive() {
        let position = PlaybackProgress.minimumResumableOffset
        #expect(Self.progress(position: position, duration: 1440).isResumable)
    }

    @Test("The closing seconds are not resumable")
    func nearTheEnd() {
        let duration = 1440.0
        let boundary = duration - PlaybackProgress.minimumRemainingSeconds

        #expect(Self.progress(position: boundary, duration: duration).isResumable)
        #expect(Self.progress(position: boundary + 0.1, duration: duration).isResumable == false)
        #expect(Self.progress(position: duration, duration: duration).isResumable == false)
    }

    @Test("An unknown duration only applies the lower threshold")
    func unknownDuration() {
        #expect(Self.progress(position: 60, duration: nil).isResumable)
        #expect(Self.progress(position: 14.9, duration: nil).isResumable == false)
    }

    @Test("A position past the end is never resumable")
    func pastTheEnd() {
        let progress = Self.progress(position: 2000, duration: 1440)
        #expect(progress.isResumable == false)
        #expect(progress.remainingSeconds == 0)
    }

    @Test("A zero-length episode is never resumable")
    func zeroDuration() {
        #expect(Self.progress(position: 20, duration: 0).isResumable == false)
    }

    @Test("Remaining seconds need a known duration and never go negative")
    func remainingSeconds() {
        #expect(Self.progress(position: 120, duration: 1440).remainingSeconds == 1320)
        #expect(Self.progress(position: 120, duration: nil).remainingSeconds == nil)
        #expect(Self.progress(position: 10, duration: 1440).remainingSeconds == 1430)
    }

    @Test("Coding round trip preserves every field")
    func codableRoundTrip() throws {
        let original = Self.progress(position: 320.5, duration: 1440)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlaybackProgress.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.releaseAlias == original.releaseAlias)
        #expect(decoded.episodeID == original.episodeID)
        #expect(decoded.duration == original.duration)
    }

    private static func progress(position: Double, duration: Double?) -> PlaybackProgress {
        PlaybackProgress(
            releaseAlias: "mezametara-saikyou-soubi",
            episodeID: UUID(),
            position: position,
            duration: duration,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
