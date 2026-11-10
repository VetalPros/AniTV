@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Image cache")
struct ImageCacheTests {
    private static let imageURL = URL(string: "https://aniliberty.top/storage/releases/posters/10308/poster.webp")
    private static let payload = Data("fake-webp-bytes".utf8)

    @Test("A memory hit avoids the second request")
    func memoryHit() async throws {
        let transport = StubTransport.serving(Self.payload)
        let cache = ImageCache(memoryLimit: 1 << 20, diskDirectory: nil, transport: transport)
        let url = try #require(Self.imageURL)

        let first = try await cache.data(for: url)
        let second = try await cache.data(for: url)

        #expect(first == Self.payload)
        #expect(second == Self.payload)
        #expect(await transport.requestCount() == 1)

        let recorded = await transport.recorded
        let request = try #require(recorded.first)
        #expect(request.method == "GET")
        #expect(request.userAgent == AniLibertyConfiguration.default.userAgent)
        #expect(request.timeout == 30)
    }

    @Test("The disk tier survives a new cache instance")
    func diskPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anilibertykit-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try #require(Self.imageURL)

        let writer = StubTransport.serving(Self.payload)
        let first = ImageCache(memoryLimit: 1 << 20, diskDirectory: directory, transport: writer)
        let written = try await first.data(for: url)
        #expect(written == Self.payload)
        #expect(await writer.requestCount() == 1)

        // The second cache starts with an empty memory, so a hit can only come from disk.
        let reader = StubTransport.failing(with: URLError(.notConnectedToInternet))
        let second = ImageCache(memoryLimit: 1 << 20, diskDirectory: directory, transport: reader)
        let cached = try await second.data(for: url)

        #expect(cached == Self.payload)
        #expect(await reader.requestCount() == 0)
    }

    @Test("Clearing both tiers forces a new request")
    func removeAll() async throws {
        let transport = StubTransport.serving(Self.payload)
        let cache = ImageCache(memoryLimit: 1 << 20, diskDirectory: nil, transport: transport)
        let url = try #require(Self.imageURL)

        _ = try await cache.data(for: url)
        await cache.removeAll()
        _ = try await cache.data(for: url)

        #expect(await transport.requestCount() == 2)
    }

    @Test("A non-2xx status is surfaced")
    func statusError() async throws {
        let transport = StubTransport.serving(Data(), status: 404)
        let cache = ImageCache(memoryLimit: 1 << 20, diskDirectory: nil, transport: transport)
        let url = try #require(Self.imageURL)

        await #expect(throws: AniLibertyError.httpStatus(404)) {
            _ = try await cache.data(for: url)
        }
    }

    @Test("A transport failure is surfaced")
    func transportError() async throws {
        let transport = StubTransport.failing(with: URLError(.timedOut))
        let cache = ImageCache(memoryLimit: 1 << 20, diskDirectory: nil, transport: transport)
        let url = try #require(Self.imageURL)

        do {
            _ = try await cache.data(for: url)
            Issue.record("Expected the transport failure to surface.")
        } catch let error as AniLibertyError {
            guard case .network = error else {
                Issue.record("Expected .network, got \(error).")
                return
            }
        }
    }
}
