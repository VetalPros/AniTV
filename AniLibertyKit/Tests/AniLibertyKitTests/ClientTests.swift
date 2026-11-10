@testable import AniLibertyKit
import Foundation
import Testing

@Suite("AniLibertyClient")
struct ClientTests {
    @Test("The latest-releases feed is requested politely")
    func latestReleasesRequest() async throws {
        let transport = try StubTransport.serving(Fixtures.latestReleases())
        let client = AniLibertyClient(transport: transport)

        let releases = try await client.latestReleases()

        #expect(releases.count == 3)
        #expect(await transport.requestCount() == 1)

        let recorded = await transport.recorded
        let request = try #require(recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/anime/releases/latest")
        #expect(request.method == "GET")
        #expect(request.accept == "application/json")
        #expect(request.userAgent == AniLibertyConfiguration.default.userAgent)
        #expect(request.timeout == 30)
    }

    @Test("A release is requested by its identifier or slug")
    func releaseDetailRequest() async throws {
        let transport = try StubTransport.serving(Fixtures.releaseDetail())
        let client = AniLibertyClient(transport: transport)

        let release = try await client.release(idOrAlias: "10308")

        #expect(release.id == 10308)
        #expect(release.episodes.isEmpty == false)

        let recorded = await transport.recorded
        let request = try #require(recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/anime/releases/10308")
    }

    @Test("A custom base URL is honoured")
    func customBaseURL() async throws {
        let configuration = try AniLibertyConfiguration(
            baseURL: #require(URL(string: "https://mirror.example.com")),
            userAgent: "AniTV/Tests"
        )
        let transport = try StubTransport.serving(Fixtures.latestReleases())
        let client = AniLibertyClient(configuration: configuration, transport: transport)

        _ = try await client.latestReleases()

        let recorded = await transport.recorded
        let request = try #require(recorded.first)
        #expect(request.url?.absoluteString == "https://mirror.example.com/api/v1/anime/releases/latest")
    }

    @Test("A non-2xx status becomes httpStatus")
    func statusErrorMapping() async throws {
        let transport = StubTransport.serving(Data(), status: 503)
        let client = AniLibertyClient(transport: transport)

        await #expect(throws: AniLibertyError.httpStatus(503)) {
            _ = try await client.latestReleases()
        }
    }

    @Test("A malformed payload becomes a decoding error")
    func decodingErrorMapping() async throws {
        let transport = StubTransport.serving(Data("not json at all".utf8))
        let client = AniLibertyClient(transport: transport)

        do {
            _ = try await client.latestReleases()
            Issue.record("Expected the malformed payload to fail decoding.")
        } catch let error as AniLibertyError {
            guard case let .decoding(details) = error else {
                Issue.record("Expected .decoding, got \(error).")
                return
            }
            #expect(details.isEmpty == false)
        }
    }

    @Test("A transport failure becomes a network error")
    func transportErrorMapping() async throws {
        let transport = StubTransport.failing(with: URLError(.notConnectedToInternet))
        let client = AniLibertyClient(transport: transport)

        do {
            _ = try await client.latestReleases()
            Issue.record("Expected the transport failure to surface as an error.")
        } catch let error as AniLibertyError {
            guard case .network = error else {
                Issue.record("Expected .network, got \(error).")
                return
            }
        }
    }
}
