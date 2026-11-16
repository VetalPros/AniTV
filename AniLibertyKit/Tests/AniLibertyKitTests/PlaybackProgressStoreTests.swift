@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Playback progress store")
struct PlaybackProgressStoreTests {
    private static let firstAlias = "mezametara-saikyou-soubi"
    private static let secondAlias = "another-release"

    @Test("A saved progress reads back unchanged")
    func roundTrip() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let progress = Self.progress(alias: Self.firstAlias, position: 320.5, duration: 1440)
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

    @Test("Saving again replaces the older position")
    func saveReplaces() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        let old = Self.progress(alias: Self.firstAlias, position: 100, duration: 1440)
        let new = Self.progress(alias: Self.firstAlias, position: 640, duration: 1440)

        await store.save(old)
        await store.save(new)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == new)
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

    @Test("A release without a stored value reads as nil")
    func missingValue() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)

        #expect(await store.progress(forReleaseAlias: "never-watched") == nil)
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

        // And a plain string, not even a JSON container, is ignored too.
        throwaway.defaults.set(Data(#""just a string""#.utf8), forKey: key)
        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == nil)

        // The corrupt slot does not poison later writes.
        let progress = Self.progress(alias: Self.firstAlias, position: 200, duration: 1440)
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
        let finished = Self.progress(alias: Self.firstAlias, position: 1430, duration: 1440)
        await store.save(finished)

        #expect(await store.progress(forReleaseAlias: Self.firstAlias) == finished)
        #expect(await store.resumableProgress(forReleaseAlias: Self.firstAlias) == nil)
    }

    @Test("A resumable episode is offered for resuming")
    func resumableEpisode() async throws {
        let throwaway = try ThrowawayDefaults()
        defer { throwaway.cleanUp() }

        let store = PlaybackProgressStore(defaults: throwaway.defaults)
        let progress = Self.progress(alias: Self.firstAlias, position: 320, duration: 1440)
        await store.save(progress)

        #expect(await store.resumableProgress(forReleaseAlias: Self.firstAlias) == progress)
    }

    private static func progress(alias: String, position: Double, duration: Double?) -> PlaybackProgress {
        PlaybackProgress(
            releaseAlias: alias,
            episodeID: UUID(),
            position: position,
            duration: duration,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
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
