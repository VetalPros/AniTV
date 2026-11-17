@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Catalogue cache")
struct CatalogCacheTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Client integration

    @Test("A second identical request is served from the cache")
    func cacheHit() async throws {
        let transport = try StubTransport.serving(Fixtures.catalogPage())
        let client = Self.client(transport: transport)

        let first = try await client.catalog(page: 1, limit: 3)
        let second = try await client.catalog(page: 1, limit: 3)

        #expect(first == second)
        #expect(await transport.requestCount() == 1)
    }

    @Test("Refresh bypasses the cache and replaces its entry")
    func refresh() async throws {
        let transport = try StubTransport.serving(Fixtures.catalogPage())
        let client = Self.client(transport: transport)

        _ = try await client.catalog(page: 1, limit: 3)
        _ = try await client.catalog(page: 1, limit: 3)
        #expect(await transport.requestCount() == 1)

        _ = try await client.catalog(page: 1, limit: 3, refresh: true)
        #expect(await transport.requestCount() == 2)

        // The refreshed page is now the cached one, so the next plain call stays offline.
        _ = try await client.catalog(page: 1, limit: 3)
        #expect(await transport.requestCount() == 2)
    }

    @Test("Different filters and pages are different entries")
    func distinctQueries() async throws {
        let transport = try StubTransport.serving(Fixtures.catalogPage())
        let client = Self.client(transport: transport)

        _ = try await client.catalog(page: 1, limit: 3)
        _ = try await client.catalog(page: 1, limit: 3, filter: CatalogFilter(search: "маска"))
        _ = try await client.catalog(page: 2, limit: 3)
        #expect(await transport.requestCount() == 3)

        // Repeating each of them changes nothing.
        _ = try await client.catalog(page: 1, limit: 3)
        _ = try await client.catalog(page: 1, limit: 3, filter: CatalogFilter(search: "маска"))
        _ = try await client.catalog(page: 2, limit: 3)
        #expect(await transport.requestCount() == 3)
    }

    @Test("A page expires after its time to live")
    func expiry() async throws {
        let clock = TestClock(Self.start)
        let cache = CatalogCache(timeToLive: 300, now: { clock.date })
        let transport = try StubTransport.serving(Fixtures.catalogPage())
        let client = AniLibertyClient(transport: transport, accountTransport: transport, catalogCache: cache)

        _ = try await client.catalog(page: 1, limit: 3)
        clock.advance(by: 299)
        _ = try await client.catalog(page: 1, limit: 3)
        #expect(await transport.requestCount() == 1)

        clock.advance(by: 2)
        _ = try await client.catalog(page: 1, limit: 3)
        #expect(await transport.requestCount() == 2)
    }

    // MARK: - Cache behaviour

    @Test("The cache is bounded and drops the oldest insertion")
    func boundedCapacity() async {
        let cache = CatalogCache(capacity: 2)
        let queries = (1 ... 3).map { CatalogQuery(page: $0, limit: 3, filter: .empty) }

        for (offset, query) in queries.enumerated() {
            await cache.store(Self.page(number: offset + 1), for: query)
        }

        #expect(await cache.count == 2)
        #expect(await cache.page(for: queries[0]) == nil)
        #expect(await cache.page(for: queries[1]) == Self.page(number: 2))
        #expect(await cache.page(for: queries[2]) == Self.page(number: 3))
    }

    @Test("An expired entry is dropped on read")
    func expiredEntryIsRemoved() async {
        let clock = TestClock(Self.start)
        let cache = CatalogCache(timeToLive: 60, now: { clock.date })
        let query = CatalogQuery(page: 1, limit: 3, filter: .empty)

        await cache.store(Self.page(number: 1), for: query)
        #expect(await cache.count == 1)

        clock.advance(by: 61)
        #expect(await cache.page(for: query) == nil)
        #expect(await cache.isEmpty)
    }

    @Test("Removing everything empties the cache")
    func removeAll() async {
        let cache = CatalogCache()
        let query = CatalogQuery(page: 1, limit: 3, filter: .empty)

        await cache.store(Self.page(number: 1), for: query)
        await cache.removeAll()

        #expect(await cache.page(for: query) == nil)
        #expect(await cache.isEmpty)
    }

    @Test("Filters that encode to the same request share a key")
    func filterFingerprints() {
        let ordered = CatalogFilter(search: "маска", genreIDs: [25, 24], types: ["TV", "MOVIE"])
        let reordered = CatalogFilter(search: "  маска  ", genreIDs: [24, 25], types: ["MOVIE", "TV"])

        #expect(
            CatalogQuery(page: 1, limit: 15, filter: ordered)
                == CatalogQuery(page: 1, limit: 15, filter: reordered)
        )
        #expect(CatalogQuery(page: 1, limit: 15, filter: .empty).filterFingerprint.isEmpty)
        // A different page or limit is a different key.
        #expect(
            CatalogQuery(page: 2, limit: 15, filter: ordered)
                != CatalogQuery(page: 1, limit: 15, filter: ordered)
        )
        #expect(
            CatalogQuery(page: 1, limit: 30, filter: ordered)
                != CatalogQuery(page: 1, limit: 15, filter: ordered)
        )
    }

    // MARK: - Helpers

    private static func client(transport: StubTransport) -> AniLibertyClient {
        AniLibertyClient(transport: transport, accountTransport: transport, catalogCache: CatalogCache())
    }

    private static func page(number: Int) -> CatalogPage {
        CatalogPage(
            releases: [],
            total: number,
            currentPage: number,
            totalPages: 10,
            perPage: 1
        )
    }
}

/// Controllable clock for the cache tests.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date

    init(_ date: Date) {
        stored = date
    }

    var date: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}
