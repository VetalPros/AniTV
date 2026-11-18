@testable import AniLibertyKit
import Foundation
import Testing

/// The two switches behind «Автоматически пропускать опенинги/эндинги». Off by default is the promise that
/// matters: nobody should lose a piece of an episode to a setting they never touched.
@Suite("Playback settings")
struct PlaybackSettingsTests {
    private func store() throws -> PlaybackSettingsStore {
        let suite = try #require(UserDefaults(suiteName: "tv.anitv.tests.settings.\(UUID().uuidString)"))
        return PlaybackSettingsStore(defaults: suite)
    }

    @Test("A fresh install skips nothing")
    func defaults() async throws {
        #expect(try await store().load() == .defaults)
        #expect(PlaybackSettings.defaults.skipsOpenings == false)
        #expect(PlaybackSettings.defaults.skipsEndings == false)
    }

    @Test("Switches survive a round trip")
    func roundTrip() async throws {
        let store = try store()
        await store.save(PlaybackSettings(skipsOpenings: true, skipsEndings: false))
        #expect(await store.load() == PlaybackSettings(skipsOpenings: true, skipsEndings: false))

        await store.save(PlaybackSettings(skipsOpenings: false, skipsEndings: true))
        #expect(await store.load() == PlaybackSettings(skipsOpenings: false, skipsEndings: true))
    }

    @Test("The two switches are independent")
    func independence() async throws {
        let store = try store()
        await store.save(PlaybackSettings(skipsOpenings: true, skipsEndings: false))
        #expect(await store.load().skipsOpenings)
        #expect(await store.load().skipsEndings == false)
    }

    @Test("A different domain starts from the defaults")
    func separateDomains() async throws {
        let first = try store()
        await first.save(PlaybackSettings(skipsOpenings: true, skipsEndings: true))
        #expect(try await store().load() == .defaults)
    }
}
