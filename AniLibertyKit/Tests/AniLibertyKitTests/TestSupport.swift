@testable import AniLibertyKit
import Foundation

/// Loads the captured API payloads that live in `Fixtures/`.
///
/// The fixtures are the only source of realistic JSON in the test suite: everything else is
/// hand-written for edge cases. They are read through the test bundle so the tests can run
/// from any working directory.
enum Fixtures {
    /// Failure modes of the fixture loader.
    enum FixturesError: Error {
        /// The requested fixture is not part of the test bundle.
        case missing(String)
    }

    /// Reads one fixture from the bundle.
    ///
    /// - Parameter name: File name without the `.json` extension.
    /// - Returns: Raw bytes of the fixture.
    /// - Throws: `FixturesError.missing` when the bundle does not contain the file.
    static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            throw FixturesError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    /// The latest-releases feed: a bare array of three releases without episodes.
    static func latestReleases() throws -> Data {
        try data(named: "releases_latest")
    }

    /// One release with its episode list and timecodes.
    static func releaseDetail() throws -> Data {
        try data(named: "release_detail")
    }

    /// One page of the unfiltered catalogue, three releases with their pagination.
    static func catalogPage() throws -> Data {
        try data(named: "catalog_page")
    }

    /// One page of the catalogue filtered by `f.search = "маска"`.
    static func catalogSearch() throws -> Data {
        try data(named: "catalog_search")
    }

    /// Reference payload of the catalogue endpoint, called `genres`, `types`, `seasons`,
    /// `sorting` or `years`.
    static func reference(_ name: String) throws -> Data {
        try data(named: "reference_\(name)")
    }
}

/// Transport double that records every request and answers with a fixed handler.
///
/// Being an `actor` keeps the recordings safe under the parallel test runner, and the
/// `HTTPTransport` conformance keeps the production injection seam honest.
actor StubTransport: HTTPTransport {
    /// The parts of a request the tests care about.
    struct RecordedRequest: Sendable {
        /// Absolute URL of the request.
        let url: URL?
        /// HTTP method, usually `GET`.
        let method: String?
        /// `Accept` header value.
        let accept: String?
        /// `User-Agent` header value.
        let userAgent: String?
        /// `Content-Type` header value, set on requests that carry a body.
        let contentType: String?
        /// Raw body of the request, when it has one.
        let body: Data?
        /// Per-request timeout in seconds.
        let timeout: TimeInterval
    }

    /// Failure modes of the stub itself, never of the code under test.
    enum StubError: Error {
        /// The request had no URL to answer for.
        case missingURL
        /// `HTTPURLResponse` could not be built for the request.
        case responseCreationFailed
    }

    /// Requests that reached the stub, in arrival order.
    private(set) var recorded: [RecordedRequest] = []
    private let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

    /// Creates a stub with a custom handler.
    ///
    /// - Parameter handler: Produces the response for a request, or throws to simulate a
    ///   transport-level failure.
    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    /// Creates a stub that always answers with the same payload and status.
    ///
    /// - Parameters:
    ///   - data: Body to return.
    ///   - status: HTTP status code, `200` by default.
    /// - Returns: A ready-to-inject transport.
    static func serving(_ data: Data, status: Int = 200) -> StubTransport {
        StubTransport { request in
            try (data, Self.response(for: request, status: status))
        }
    }

    /// Creates a stub that always fails at the transport level.
    ///
    /// - Parameter error: The error to throw for every request.
    /// - Returns: A ready-to-inject transport.
    static func failing(with error: any Error) -> StubTransport {
        StubTransport { _ in throw error }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        recorded.append(
            RecordedRequest(
                url: request.url,
                method: request.httpMethod,
                accept: request.value(forHTTPHeaderField: "Accept"),
                userAgent: request.value(forHTTPHeaderField: "User-Agent"),
                contentType: request.value(forHTTPHeaderField: "Content-Type"),
                body: request.httpBody,
                timeout: request.timeoutInterval
            )
        )
        return try handler(request)
    }

    /// Number of requests the stub has seen.
    func requestCount() -> Int {
        recorded.count
    }

    /// Builds an `HTTPURLResponse` for a request.
    ///
    /// - Parameters:
    ///   - request: Request being answered.
    ///   - status: HTTP status code to report.
    /// - Returns: A response carrying the request URL.
    /// - Throws: `StubError` when the request has no URL or the response cannot be built.
    static func response(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
        guard let url = request.url else {
            throw StubError.missingURL
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw StubError.responseCreationFailed
        }
        return response
    }
}
