import Foundation

/// Two-level image cache: memory, then disk, then the network.
///
/// Posters and previews are the bulk of the traffic the app generates, so they are cached
/// twice: a bounded `NSCache` absorbs the repeats while scrolling, and an optional disk
/// directory keeps them across launches. Disk access is best effort — a broken directory
/// never turns into a visible failure.
public actor ImageCache {
    /// Process-wide cache used by the app; tests build their own instances.
    public static let shared = ImageCache()

    private let memory: NSCache<NSURL, NSData>
    private let diskDirectory: URL?
    private let transport: any HTTPTransport

    /// Creates a cache.
    ///
    /// - Parameters:
    ///   - memoryLimit: Memory budget in bytes, applied as the `NSCache` total cost limit.
    ///   - diskDirectory: Directory for the disk tier; `nil` disables it.
    public init(memoryLimit: Int = 64 << 20, diskDirectory: URL? = nil) {
        self.init(memoryLimit: memoryLimit, diskDirectory: diskDirectory, transport: URLSessionTransport())
    }

    /// Creates a cache with an injected transport; used by the tests.
    ///
    /// - Parameters:
    ///   - memoryLimit: Memory budget in bytes.
    ///   - diskDirectory: Directory for the disk tier; `nil` disables it.
    ///   - transport: HTTP seam used on a memory and disk miss.
    init(memoryLimit: Int, diskDirectory: URL?, transport: any HTTPTransport) {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = memoryLimit
        cache.countLimit = 256
        memory = cache
        self.diskDirectory = diskDirectory
        self.transport = transport
    }

    /// Returns the bytes of the image at `url`.
    ///
    /// The lookup order is memory, disk, network; a network response is written back to
    /// both tiers.
    ///
    /// - Parameter url: Absolute image URL.
    /// - Returns: The image bytes exactly as served by the service.
    /// - Throws: `AniLibertyError` when the transport, the HTTP status or the URL fails.
    public func data(for url: URL) async throws -> Data {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) {
            return cached as Data
        }

        if let diskDirectory, let onDisk = readFromDisk(url: url, directory: diskDirectory) {
            memory.setObject(onDisk as NSData, forKey: key, cost: onDisk.count)
            return onDisk
        }

        let request = Self.makeRequest(for: url)
        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await transport.data(for: request)
        } catch {
            throw AniLibertyError.transportFailure(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AniLibertyError.network("The server returned a non-HTTP response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw AniLibertyError.httpStatus(http.statusCode)
        }

        memory.setObject(payload as NSData, forKey: key, cost: payload.count)
        if let diskDirectory {
            writeToDisk(payload, url: url, directory: diskDirectory)
        }
        return payload
    }

    /// Drops both tiers. Used by tests and by a future "clear cache" settings action.
    public func removeAll() {
        memory.removeAllObjects()
        guard let diskDirectory else {
            return
        }
        try? FileManager.default.removeItem(at: diskDirectory)
    }

    private static func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(AniLibertyConfiguration.default.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func readFromDisk(url: URL, directory: URL) -> Data? {
        let location = Self.diskLocation(for: url, in: directory)
        guard FileManager.default.fileExists(atPath: location.path) else {
            return nil
        }
        return try? Data(contentsOf: location)
    }

    private func writeToDisk(_ data: Data, url: URL, directory: URL) {
        let location = Self.diskLocation(for: url, in: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: location, options: .atomic)
        } catch {
            // The disk tier is optional: losing a write only costs one extra request later.
        }
    }

    private static func diskLocation(for url: URL, in directory: URL) -> URL {
        let name = String(fnv1a(url.absoluteString), radix: 16)
        return directory.appending(path: name + fileExtension(for: url))
    }

    private static func fileExtension(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension.isEmpty ? ".img" : ".\(pathExtension)"
    }

    /// 64-bit FNV-1a hash; stable across launches, unlike `String.hashValue`.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
