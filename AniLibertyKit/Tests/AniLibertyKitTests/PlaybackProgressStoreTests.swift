@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Playback progress store")
struct PlaybackProgressStoreTests {
    private static let firstAlias = "mezametara-saikyou-soubi"
    private static let secondAlias = "another-release"
    private static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A saved progress reads back unchanged")
    func roundTrip() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let progress = Self.progress(position: 320.5, duration: 1440)
        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        await store.save(progress)
        let restored = await store.progress(forReleaseAlias: Self.firstAlias)

        #expect(restored == progress)
        #expect(restored?.episodeID == progress.episodeID)
        #expect(restored?.position == 320.5)
        #expect(restored?.duration == 1440)

        // The value really lives in the injected domain, as JSON, under one derived key.
        let key = PlaybackProgressStore.storageKey(forReleaseAlias: Self.firstAlias)
        #expect(throwaway.defaults.data(forKey: key) != nil)
    }

    @Test("Two releases never overwrite each other")
    func perReleaseIsolation() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let first = Self.progress(alias: Self.firstAlias, position: 100, duration: 1440)
        let second = Self.progress(alias: Self.secondAlias, position: 900, duration: 1440)
        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        await store.save(first)
        await store.save(second)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == first)
        #expect(await store.progress(forReleaseAlias: Self.secondAlias) == second)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias)?.position == 100)
    }

    @Test("Two episodes of one release keep separate records")
    func perEpisodeRecords() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let firstEpisode = UUID()
        let secondEpisode = UUID()
        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        let first = Self.progress(
            episodeID: firstEpisode,
            position: 100,
            duration: 1440,
            updatedAt: Self.baseDate
        )
        let second = Self.progress(
            episodeID: secondEpisode,
            position: 640,
            duration: 1440,
            updatedAt: Self.baseDate.addingTimeInterval(60)
        )
        await store.save(first)
        await store.save(second)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: firstEpisode) == first)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: secondEpisode) == second)
        // The release-level lookup answers with the most recent episode.
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == second)
    }

    @Test("Saving the same episode again replaces its position")
    func saveReplaces() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let episode = UUID()
        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        let old = Self.progress(episodeID: episode, position: 100, duration: 1440)
        let new = Self.progress(
            episodeID: episode,
            position: 640,
            duration: 1440,
            updatedAt: Self.baseDate.addingTimeInterval(120)
        )

        await store.save(old)
        await store.save(new)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == new)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: episode) == new)

        let key = PlaybackProgressStore.storageKey(forReleaseAlias: Self.firstAlias)
        let stored = try JSONDecoder().decode(
            [PlaybackProgress].self,
            from: #require(throwaway.defaults.data(forKey: key))
        )
        #expect(stored.count == 1)
    }

    @Test("The most recent record wins even when it belongs to an earlier episode")
    func mostRecentWins() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let firstEpisode = UUID()
        let secondEpisode = UUID()
        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        await store.save(
            Self.progress(episodeID: firstEpisode, position: 900, duration: 1440, updatedAt: Self.baseDate)
        )
        await store.save(
            Self.progress(
                episodeID: secondEpisode,
                position: 100,
                duration: 1440,
                updatedAt: Self.baseDate.addingTimeInterval(60)
            )
        )
        // The viewer goes back to the first episode: its record becomes the newest one.
        await store.save(
            Self.progress(
                episodeID: firstEpisode,
                position: 950,
                duration: 1440,
                updatedAt: Self.baseDate.addingTimeInterval(120)
            )
        )

        #expect(await store.progress(forReleaseAlias: Self.firstAlias)?.episodeID == firstEpisode)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias)?.position == 950)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: secondEpisode)?.position == 100)
    }

    @Test("A legacy single-object payload is read and upgraded on the next save")
    func legacyPayloadMigration() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        // Exactly what the previous version of the store wrote: one object per release.
        let legacy = Self.progress(position: 480, duration: 1440)
        let key = PlaybackProgressStore.storageKey(forReleaseAlias: Self.firstAlias)
        try throwaway.defaults.set(JSONEncoder().encode(legacy), forKey: key)

        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == legacy)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: legacy.episodeID) == legacy)

        // A save for another episode must not drop the migrated record, and it rewrites the
        // key in the array shape.
        let newEpisode = UUID()
        let new = Self.progress(
            episodeID: newEpisode,
            position: 90,
            duration: 1440,
            updatedAt: Self.baseDate.addingTimeInterval(3600)
        )
        await store.save(new)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: legacy.episodeID) == legacy)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: newEpisode) == new)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == new)

        let data = try #require(throwaway.defaults.data(forKey: key))
        // A JSON array, not an object: the slot was upgraded in place.
        let object = try JSONSerialization.jsonObject(with: data)
        #expect(object is [[String: Any]])
    }

    @Test("Clearing one release keeps the other")
    func clearing() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let first = Self.progress(alias: Self.firstAlias, position: 100, duration: 1440)
        let second = Self.progress(alias: Self.secondAlias, position: 900, duration: 1440)
        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        await store.save(first)
        await store.save(second)
        await store.clearProgress(forReleaseAlias: Self.firstAlias)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)
        #expect(await store.progress(forReleaseAlias: Self.secondAlias) == second)
    }

    @Test("Clearing a release forgets every episode of it")
    func clearingAllEpisodes() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        let firstEpisode = UUID()
        let secondEpisode = UUID()
        await store.save(Self.progress(episodeID: firstEpisode, position: 100, duration: 1440))
        await store.save(Self.progress(episodeID: secondEpisode, position: 200, duration: 1440))

        await store.clearProgress(forReleaseAlias: Self.firstAlias)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: firstEpisode) == nil)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias, episodeID: secondEpisode) == nil)
    }

    @Test("A release without a stored value reads as nil")
    func missingValue() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        #expect(await store.progress(forReleaseAlias: "never-watched") == nil)
        #expect(await store.progress(forReleaseAlias: "never-watched", episodeID: UUID()) == nil)
        await store.clearProgress(forReleaseAlias: "never-watched")
        #expect(await store.progress(forReleaseAlias: "never-watched") == nil)
    }

    @Test("Corrupt JSON reads as nil instead of crashing")
    func corruptPayload() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let key = PlaybackProgressStore.storageKey(forReleaseAlias: Self.firstAlias)
        throwaway.defaults.set(Data("}{ this is not json".utf8), forKey: key)
        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)

        // A well-formed JSON object with the wrong shape is just as harmless.
        throwaway.defaults.set(Data(#"{"releaseAlias":"wrong"}"#.utf8), forKey: key)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)

        // A plain string, not even a JSON container, is ignored too.
        throwaway.defaults.set(Data(#""just a string""#.utf8), forKey: key)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)

        // An array of junk is not a payload either.
        throwaway.defaults.set(Data("[1,2,3]".utf8), forKey: key)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)

        // The corrupt slot does not poison later writes.
        let progress = Self.progress(position: 200, duration: 1440)
        await store.save(progress)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == progress)
    }

    @Test("Storage keys are derived from the release alias")
    func storageKeys() {
        let first = PlaybackProgressStore.storageKey(forReleaseAlias: Self.firstAlias)
        let second = PlaybackProgressStore.storageKey(forReleaseAlias: Self.secondAlias)

        #expect(first.hasPrefix(PlaybackProgressStore.keyPrefix))
        #expect(first.hasSuffix(Self.firstAlias))
        #expect(first != second)
    }

    @Test("A finished episode is stored but not offered for resuming")
    func finishedEpisode() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        let finished = Self.progress(position: 1430, duration: 1440)
        await store.save(finished)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == finished)
        #expect(await store.resumableProgress(forReleaseAlias: Self.firstAlias) == nil)
        #expect(
            await store.resumableProgress(forReleaseAlias: Self.firstAlias, episodeID: finished.episodeID)
                == nil
        )
    }

    @Test("A resumable episode is offered for resuming")
    func resumableEpisode() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        let progress = Self.progress(position: 320, duration: 1440)
        await store.save(progress)

        #expect(await store.resumableProgress(forReleaseAlias: Self.firstAlias) == progress)
        #expect(
            await store.resumableProgress(forReleaseAlias: Self.firstAlias, episodeID: progress.episodeID)
                == progress
        )
        // Another episode of the same release has no record.
        #expect(await store.resumableProgress(forReleaseAlias: Self.firstAlias, episodeID: UUID()) == nil)
    }

    private static func progress(
        alias: String = PlaybackProgressStoreTests.firstAlias,
        episodeID: UUID = UUID(),
        position: Double,
        duration: Double?,
        updatedAt: Date = PlaybackProgressStoreTests.baseDate
    ) -> PlaybackProgress {
        PlaybackProgress(
            releaseAlias: alias,
            episodeID: episodeID,
            position: position,
            duration: duration,
            updatedAt: updatedAt
        )
    }
}

/// A `UserDefaults` domain that lasts for one test and is deleted afterwards.
private struct ThrowawayDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        suiteName = "anilibertykit-tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
