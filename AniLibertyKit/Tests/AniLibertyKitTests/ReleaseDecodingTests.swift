@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Release decoding")
struct ReleaseDecodingTests {
    @Test("The feed decodes into releases without episodes")
    func feedDecoding() throws {
        let releases = try JSONDecoder.aniLiberty.decode([Release].self, from: Fixtures.latestReleases())

        #expect(releases.count == 3)
        let first = try #require(releases.first)
        #expect(first.id == 10308)
        #expect(first.alias.hasPrefix("mezametara-saikyou-soubi"))
        #expect(first.year == 2026)
        #expect(first.isOngoing == true)
        #expect(first.name.english?.hasPrefix("Mezametara") == true)
        #expect(first.episodes.isEmpty)
        #expect(first.isPlayable == false)
        #expect(first.isBlockedByGeo == false)
        #expect(first.isBlockedByCopyrights == false)
        #expect(first.genres.isEmpty == false)
        #expect(first.averageRating == 8)
        #expect(first.ratingVotes == 1)
    }

    @Test("Posters resolve against the site root and prefer the optimised variant")
    func posterResolution() throws {
        let releases = try JSONDecoder.aniLiberty.decode([Release].self, from: Fixtures.latestReleases())
        let first = try #require(releases.first)

        let poster = try #require(first.posterURL)
        let thumbnail = try #require(first.posterThumbnailURL)
        #expect(poster.host() == "aniliberty.top")
        #expect(poster.path().hasPrefix("/storage/releases/posters/10308/"))
        #expect(poster.pathExtension == "webp")
        #expect(thumbnail.pathExtension == "webp")
        #expect(poster != thumbnail)
    }

    @Test("The subtitle joins year, localised type and age rating")
    func subtitleComposition() throws {
        let releases = try JSONDecoder.aniLiberty.decode([Release].self, from: Fixtures.latestReleases())
        let first = try #require(releases.first)

        #expect(first.subtitle == "2026 · ТВ · 16+")
        #expect(first.type?.description == "ТВ")
        #expect(first.season?.description == "Осень")
        #expect(first.ageRating == "16+")
    }

    @Test("The detail endpoint fills the episode list and sorts it")
    func detailDecoding() throws {
        let release = try JSONDecoder.aniLiberty.decode(Release.self, from: Fixtures.releaseDetail())

        #expect(release.id == 10308)
        #expect(release.episodes.isEmpty == false)
        #expect(release.isPlayable)

        let ordinals = release.episodes.map(\.ordinal)
        #expect(ordinals == ordinals.sorted())
        #expect(Set(ordinals).count == ordinals.count)

        let first = try #require(release.episodes.first)
        #expect(first.ordinal == 1)
        #expect(first.displayTitle == "Серия 1")
        #expect(first.opening?.start == 65)
        #expect(first.opening?.stop == 155)
        #expect(first.ending?.start == 1326)
        #expect(first.ending?.stop == 1415)
        #expect(first.hls1080 != nil)
        #expect(first.previewURL?.host() == "aniliberty.top")
    }

    @Test("Blocked releases are never playable")
    func blockedReleases() throws {
        let payload = """
        {
          "id": 1,
          "alias": "blocked",
          "name": { "main": "Заблокировано" },
          "is_blocked_by_geo": true,
          "is_blocked_by_copyrights": false,
          "episodes": [
            {
              "id": "0b4a5d5e-8f66-4f0f-9c2e-3a4b5c6d7e8f",
              "ordinal": 1,
              "hls_1080": "https://cache.libria.fun/videos/media/ts/1/1/1080/hash.m3u8"
            }
          ]
        }
        """

        let release = try JSONDecoder.aniLiberty.decode(Release.self, from: Data(payload.utf8))
        #expect(release.isBlockedByGeo)
        #expect(release.episodes.count == 1)
        #expect(release.isPlayable == false)
    }

    @Test("A payload with only the identity fields still decodes")
    func minimalPayload() throws {
        let payload = """
        { "id": 42, "alias": "minimal", "name": { "main": "Минимальный" } }
        """

        let release = try JSONDecoder.aniLiberty.decode(Release.self, from: Data(payload.utf8))
        #expect(release.id == 42)
        #expect(release.year == nil)
        #expect(release.type == nil)
        #expect(release.posterURL == nil)
        #expect(release.genres.isEmpty)
        #expect(release.episodes.isEmpty)
        #expect(release.isPlayable == false)
    }

    @Test("Missing required fields fail with a decoding error")
    func missingIdentity() throws {
        let payload = """
        { "alias": "no-identifier", "name": { "main": "Без идентификатора" } }
        """

        #expect(throws: (any Error).self) {
            try JSONDecoder.aniLiberty.decode(Release.self, from: Data(payload.utf8))
        }
    }
}
