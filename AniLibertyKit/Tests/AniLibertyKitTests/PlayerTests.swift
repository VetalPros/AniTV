@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Stream and timecode resolution")
struct PlayerTests {
    @Test("Sources are ordered from the best quality down")
    func sourceOrdering() throws {
        let episode = try Self.decodeEpisode(
            """
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "ordinal": 3,
              "hls_480": "https://cache.libria.fun/videos/media/ts/1/3/480/a.m3u8",
              "hls_720": "https://cache.libria.fun/videos/media/ts/1/3/720/b.m3u8",
              "hls_1080": "https://cache.libria.fun/videos/media/ts/1/3/1080/c.m3u8"
            }
            """
        )

        let sources = StreamResolver.sources(for: episode)
        #expect(sources.map(\.quality) == [.uhd1080, .hd720, .sd480])
        #expect(sources.map(\.url.lastPathComponent) == ["c.m3u8", "b.m3u8", "a.m3u8"])
        #expect(StreamResolver.preferredSource(for: episode) == sources.first)
    }

    @Test("Playback falls back when 1080p is missing")
    func qualityFallback() throws {
        let episode = try Self.decodeEpisode(
            """
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "ordinal": 1,
              "hls_480": "https://cache.libria.fun/videos/media/ts/1/1/480/a.m3u8",
              "hls_720": "https://cache.libria.fun/videos/media/ts/1/1/720/b.m3u8"
            }
            """
        )

        let sources = StreamResolver.sources(for: episode)
        #expect(sources.map(\.quality) == [.hd720, .sd480])
        #expect(StreamResolver.preferredSource(for: episode)?.quality == .hd720)
    }

    @Test("An episode without playlists has no source at all")
    func noSources() throws {
        let episode = try Self.decodeEpisode(
            """
            { "id": "33333333-3333-3333-3333-333333333333", "ordinal": 2 }
            """
        )

        #expect(StreamResolver.sources(for: episode).isEmpty)
        #expect(StreamResolver.preferredSource(for: episode) == nil)
    }

    @Test("Quality comparison follows the advertised ladder")
    func qualityOrdering() {
        #expect(StreamQuality.sd480 < .hd720)
        #expect(StreamQuality.hd720 < .uhd1080)
        #expect(StreamQuality.allCases == [.sd480, .hd720, .uhd1080])
        #expect(StreamQuality.uhd1080.rawValue == "1080")
    }

    @Test("Fixture episodes expose opening and ending ranges")
    func timecodesFromFixture() throws {
        let release = try JSONDecoder.aniLiberty.decode(Release.self, from: Fixtures.releaseDetail())
        let episode = try #require(release.episodes.first)

        let timecodes = TimecodeResolver.timecodes(for: episode)
        #expect(timecodes.count == 2)

        let opening = try #require(timecodes.first)
        #expect(timecodes[0].kind == .opening)
        #expect(timecodes[1].kind == .ending)
        #expect(episode.opening?.start == opening.start)
        #expect(episode.opening?.stop == opening.end)
        #expect(opening.releaseEpisodeID == episode.id)
        #expect(Set(timecodes.map(\.releaseEpisodeID)) == [episode.id])
    }

    @Test("The active skip uses a half-open range")
    func activeSkip() throws {
        let episode = try Self.decodeEpisode(
            """
            {
              "id": "44444444-4444-4444-4444-444444444444",
              "ordinal": 1,
              "opening": { "start": 65, "stop": 155 },
              "ending": { "start": 1326, "stop": 1415 }
            }
            """
        )
        let timecodes = TimecodeResolver.timecodes(for: episode)

        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 0) == nil)
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 64.9) == nil)
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 65)?.kind == .opening)
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 154.9)?.kind == .opening)
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 155) == nil)
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 1326)?.kind == .ending)
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 1415) == nil)
    }

    @Test("Partial and zero-length ranges are discarded")
    func invalidRanges() throws {
        let partial = try Self.decodeEpisode(
            """
            {
              "id": "55555555-5555-5555-5555-555555555555",
              "ordinal": 1,
              "opening": { "start": 65 },
              "ending": { "stop": 1415 }
            }
            """
        )
        #expect(TimecodeResolver.timecodes(for: partial).isEmpty)

        let zeroLength = try Self.decodeEpisode(
            """
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "ordinal": 2,
              "opening": { "start": 100, "stop": 100 },
              "ending": { "start": 200, "stop": 150 }
            }
            """
        )
        #expect(TimecodeResolver.timecodes(for: zeroLength).isEmpty)

        let onlyEnding = try Self.decodeEpisode(
            """
            {
              "id": "77777777-7777-7777-7777-777777777777",
              "ordinal": 3,
              "ending": { "start": 1300, "stop": 1420 }
            }
            """
        )
        let timecodes = TimecodeResolver.timecodes(for: onlyEnding)
        #expect(timecodes.map(\.kind) == [.ending])
        #expect(TimecodeResolver.activeSkip(for: timecodes, playhead: 1400)?.kind == .ending)
    }

    private static func decodeEpisode(_ json: String) throws -> Episode {
        try JSONDecoder.aniLiberty.decode(Episode.self, from: Data(json.utf8))
    }
}
