import Foundation

/// Identifies one catalogue request: the page, the page size and the filter.
///
/// Two filters that encode to the same request share a fingerprint (the order of genre,
/// type and season values does not matter), so they also share a cache entry.
public struct CatalogQuery: Sendable, Hashable {
    /// One-based page number.
    public let page: Int
    /// Page size.
    public let limit: Int
    /// Fingerprint of ``CatalogFilter``; empty for the unfiltered list.
    public let filterFingerprint: String

    /// Creates a query key.
    ///
    /// - Parameters:
    ///   - page: One-based page number.
    ///   - limit: Page size.
    ///   - filter: Filter the page was requested with.
    public init(page: Int, limit: Int, filter: CatalogFilter) {
        self.page = page
        self.limit = limit
        filterFingerprint = filter.fingerprint
    }
}

/// In-memory cache of decoded catalogue pages, keyed by the request that produced them.
///
/// The catalogue endpoint offers nothing a conditional request could use. Measured on
/// 2026-11-17, `POST /api/v1/anime/catalog/releases` answers
/// `cache-control: no-cache, private` with **no** `etag` header, and a request that sends
/// `If-None-Match` still receives `200` and the whole body. HTTP caching therefore cannot
/// save the request, so the kit keeps its own query-keyed cache of already-decoded pages
/// and the screen pays for a page once per ``timeToLive``.
///
/// The store is bounded: once it holds ``capacity`` pages, storing another one drops the
/// oldest insertion. Housekeeping happens on read and write, so an unused cache leaks
/// nothing but its own fixed-size dictionary.
public actor CatalogCache {
    /// Default number of pages kept in memory.
    public static let defaultCapacity = 64

    /// Default lifetime of one entry: five minutes.
    ///
    /// Long enough to make paging back and forth free, short enough that a catalogue edited
    /// by the service is picked up without a restart.
    public static let defaultTimeToLive: TimeInterval = 300

    /// Maximum number of pages the cache holds.
    public let capacity: Int

    /// Lifetime of one page, in seconds.
    public let timeToLive: TimeInterval

    private let now: @Sendable () -> Date
    private var entries: [CatalogQuery: Entry] = [:]
    private var order: [CatalogQuery] = []

    /// Creates a cache.
    ///
    /// - Parameters:
    ///   - capacity: Maximum number of pages; values below 1 become 1.
    ///   - timeToLive: Lifetime of one page in seconds.
    ///   - now: Clock used for expiry; tests inject a controllable one.
    public init(
        capacity: Int = CatalogCache.defaultCapacity,
        timeToLive: TimeInterval = CatalogCache.defaultTimeToLive,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.capacity = max(1, capacity)
        self.timeToLive = timeToLive
        self.now = now
    }

    /// Cached page for a request, when it is still fresh.
    ///
    /// An expired entry is removed on the way out, so a long-running cache does not keep
    /// dead pages around.
    ///
    /// - Parameter query: Request the page was produced by.
    /// - Returns: The cached page, or `nil` when there is none or it has expired.
    public func page(for query: CatalogQuery) -> CatalogPage? {
        guard let entry = entries[query] else {
            return nil
        }
        guard now().timeIntervalSince(entry.storedAt) < timeToLive else {
            remove(query)
            return nil
        }
        return entry.page
    }

    /// Stores a page, replacing any previous entry for the same request.
    ///
    /// - Parameters:
    ///   - page: Decoded page to keep.
    ///   - query: Request the page was produced by.
    public func store(_ page: CatalogPage, for query: CatalogQuery) {
        if entries[query] == nil {
            order.append(query)
        }
        entries[query] = Entry(page: page, storedAt: now())

        while order.count > capacity, let oldest = order.first {
            remove(oldest)
        }
    }

    /// Drops every cached page.
    public func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    /// Number of pages currently held; used by tests and diagnostics.
    var count: Int {
        entries.count
    }

    /// Whether the cache holds nothing; used by tests and diagnostics.
    var isEmpty: Bool {
        entries.isEmpty
    }

    private func remove(_ query: CatalogQuery) {
        entries[query] = nil
        order.removeAll { $0 == query }
    }

    private struct Entry {
        let page: CatalogPage
        let storedAt: Date
    }
}
