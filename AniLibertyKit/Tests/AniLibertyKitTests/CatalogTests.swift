@testable import AniLibertyKit
import Foundation
import Testing

@Suite("Catalogue")
struct CatalogTests {
    // MARK: - Decoding

    @Test("A catalogue page decodes with its pagination")
    func pageDecoding() throws {
        let page = try JSONDecoder.aniLiberty.decode(CatalogPage.self, from: Fixtures.catalogPage())

        #expect(page.releases.count == 3)
        #expect(page.total == 1946)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 649)
        #expect(page.perPage == 3)
        #expect(page.hasNextPage)

        let first = try #require(page.releases.first)
        #expect(first.id == 10306)
        #expect(first.alias == "magicalexplorer")
        #expect(first.title == "Магический исследователь")
        #expect(first.year == 2026)
        #expect(first.episodes.isEmpty)
    }

    @Test("The search fixture keeps the filtered total")
    func searchFixture() throws {
        let page = try JSONDecoder.aniLiberty.decode(CatalogPage.self, from: Fixtures.catalogSearch())

        #expect(page.total == 6)
        #expect(page.totalPages == 3)
        #expect(page.perPage == 2)
        #expect(page.releases.map(\.alias) == ["hero-mask", "shuiro-no-kamen"])
    }

    @Test("A page without pagination metadata falls back to its item count")
    func paginationFallback() throws {
        let payload = Data(
            """
            {"data":[{"id":1,"alias":"solo","name":{"main":"Один"}}]}
            """.utf8
        )

        let page = try JSONDecoder.aniLiberty.decode(CatalogPage.self, from: payload)

        #expect(page.releases.count == 1)
        #expect(page.total == 1)
        #expect(page.currentPage == 1)
        #expect(page.totalPages == 1)
        #expect(page.perPage == 1)
        #expect(page.hasNextPage == false)
    }

    // MARK: - Filter encoding

    @Test("Every filter field is nested under f")
    func filterEncoding() throws {
        let filter = CatalogFilter(
            search: "маска",
            genreIDs: [25],
            types: ["TV", "MOVIE"],
            seasons: ["winter"],
            years: CatalogYearRange(from: 2010, to: 2012),
            sorting: "RATING_DESC"
        )

        let body = try Self.jsonObject(filter.body(page: 2, limit: 30))

        #expect(body["page"] as? Int == 2)
        #expect(body["limit"] as? Int == 30)
        // The service silently ignores filter keys placed at the top level.
        #expect(body["search"] == nil)
        #expect(body["genres"] == nil)
        #expect(body["sorting"] == nil)

        let nested = try #require(body["f"] as? [String: Any])
        #expect(Set(nested.keys) == ["search", "genres", "types", "seasons", "years", "sorting"])
        #expect(nested["search"] as? String == "маска")
        #expect(nested["genres"] as? [Int] == [25])
        #expect(nested["types"] as? [String] == ["TV", "MOVIE"])
        #expect(nested["seasons"] as? [String] == ["winter"])
        #expect(nested["sorting"] as? String == "RATING_DESC")

        let years = try #require(nested["years"] as? [String: Any])
        #expect(Set(years.keys) == ["from_year", "to_year"])
        #expect(years["from_year"] as? Int == 2010)
        #expect(years["to_year"] as? Int == 2012)
    }

    @Test("An empty filter encodes the plain list body")
    func emptyFilter() throws {
        let body = try Self.jsonObject(CatalogFilter.empty.body(page: 1, limit: 15))

        #expect(Set(body.keys) == ["page", "limit"])
        #expect(body["page"] as? Int == 1)
        #expect(body["limit"] as? Int == 15)
        #expect(body["f"] == nil)
    }

    @Test("Empty groups and blank text stay out of the body")
    func emptyGroups() throws {
        var filter = CatalogFilter()
        filter.search = "   "
        filter.genreIDs = []
        filter.types = []
        filter.seasons = []
        filter.years = CatalogYearRange()
        filter.sorting = ""

        #expect(filter.isEmpty)
        #expect(try Self.jsonObject(filter.body(page: 1, limit: 15))["f"] == nil)

        filter.genreIDs = [25]
        filter.years = CatalogYearRange(from: 2010)
        let body = try Self.jsonObject(filter.body(page: 1, limit: 15))
        let nested = try #require(body["f"] as? [String: Any])

        #expect(Set(nested.keys) == ["genres", "years"])
        #expect(nested["genres"] as? [Int] == [25])
        #expect(try #require(nested["years"] as? [String: Any])["from_year"] as? Int == 2010)
        #expect((nested["years"] as? [String: Any])?["to_year"] == nil)
    }

    @Test("Search text is trimmed before it is sent")
    func trimmedSearch() throws {
        let filter = CatalogFilter(search: "  маска  ")
        let body = try Self.jsonObject(filter.body(page: 1, limit: 15))
        let nested = try #require(body["f"] as? [String: Any])

        #expect(nested["search"] as? String == "маска")
    }

    // MARK: - Client

    @Test("The catalogue call is a polite POST with a JSON body")
    func catalogRequest() async throws {
        let transport = try StubTransport.serving(Fixtures.catalogPage())
        let client = AniLibertyClient(transport: transport)

        let page = try await client.catalog(page: 1, limit: 3, filter: CatalogFilter(search: "маска"))

        #expect(page.releases.count == 3)
        let request = try #require(await transport.recorded.first)
        #expect(request.url?.absoluteString == "https://aniliberty.top/api/v1/anime/catalog/releases")
        #expect(request.method == "POST")
        #expect(request.accept == "application/json")
        #expect(request.contentType == "application/json")
        #expect(request.userAgent == AniLibertyConfiguration.default.userAgent)
        #expect(request.timeout == 30)

        let body = try Self.jsonObject(#require(request.body))
        #expect(body["page"] as? Int == 1)
        #expect(body["limit"] as? Int == 3)
        #expect((body["f"] as? [String: Any])?["search"] as? String == "маска")
    }

    @Test("Paging values are clamped into the accepted range")
    func clampedPaging() async throws {
        let transport = try StubTransport.serving(Fixtures.catalogPage())
        let client = AniLibertyClient(transport: transport)

        _ = try await client.catalog(page: 0, limit: 500)

        let request = try #require(await transport.recorded.first)
        let body = try Self.jsonObject(#require(request.body))
        #expect(body["page"] as? Int == 1)
        #expect(body["limit"] as? Int == 50)
    }

    // MARK: - Reference data

    @Test("Reference endpoints decode into their models")
    func referenceDecoding() throws {
        let genres = try JSONDecoder.aniLiberty.decode([Genre].self, from: Fixtures.reference("genres"))
        #expect(genres.count == 35)
        #expect(genres.first?.id == 15)
        #expect(genres.first?.name == "Боевые искусства")

        let types = try JSONDecoder.aniLiberty.decode([CatalogReference].self, from: Fixtures.reference("types"))
        #expect(types.count == 8)
        #expect(types.first?.value == "TV")
        #expect(types.first?.description == "ТВ")
        #expect(types.first?.title == "ТВ")

        let seasons = try JSONDecoder.aniLiberty.decode([CatalogReference].self, from: Fixtures.reference("seasons"))
        #expect(seasons.map(\.value) == ["winter", "spring", "summer", "autumn"])

        let sorting = try JSONDecoder.aniLiberty.decode(
            [CatalogReference].self,
            from: Fixtures.reference("sorting")
        )
        #expect(sorting.count == 6)
        #expect(sorting.first?.value == "FRESH_AT_DESC")
        #expect(sorting.first?.label == "Обновлены недавно")
        #expect(sorting.first?.title == "Обновлены недавно")
        #expect(sorting.first?.description?.isEmpty == false)

        let years = try JSONDecoder.aniLiberty.decode([Int].self, from: Fixtures.reference("years"))
        #expect(years.count == 30)
        #expect(years.first == 1995)
        #expect(years.contains(2027))
    }

    @Test("Reference fetches use the documented paths")
    func referenceRequests() async throws {
        let transport = StubTransport { request in
            let name: String
            switch request.url?.lastPathComponent {
            case "genres", "types", "seasons", "sorting", "years":
                name = try #require(request.url?.lastPathComponent)
            default:
                throw URLError(.badURL)
            }
            return try (Fixtures.reference(name), StubTransport.response(for: request, status: 200))
        }
        let client = AniLibertyClient(transport: transport)

        #expect(try await client.referenceGenres().count == 35)
        #expect(try await client.referenceTypes().count == 8)
        #expect(try await client.referenceSeasons().count == 4)
        #expect(try await client.referenceSorting().count == 6)
        #expect(try await client.referenceYears().count == 30)

        let paths = await transport.recorded.compactMap { $0.url?.path(percentEncoded: false) }
        #expect(paths == [
            "/api/v1/anime/catalog/references/genres",
            "/api/v1/anime/catalog/references/types",
            "/api/v1/anime/catalog/references/seasons",
            "/api/v1/anime/catalog/references/sorting",
            "/api/v1/anime/catalog/references/years",
        ])
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
