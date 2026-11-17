import AniLibertyKit
import Foundation
import Observation
import os

/// Drives the «Каталог» screen: the reference data behind the filters, the current filter, the
/// result pages and the search debounce.
///
/// Every reload replaces the list and goes back to page 1; paging appends. The two are separate on
/// purpose — a filter change that appended would mix results from two different queries.
@MainActor
@Observable
final class CatalogViewModel {
    /// What the screen can be in. `empty` is separate from `loaded` so the UI can blame the filter
    /// instead of showing an empty grid.
    enum State {
        case idle
        case loading
        case loaded
        case empty
        case failed(AniLibertyError)
    }

    private static let logger = Logger(subsystem: "tv.anitv.client", category: "Catalog")

    /// Pages are 30 wide: large enough to fill six columns five times, small enough that the first
    /// screen appears quickly. The server rejects anything above 50.
    static let pageSize = 30

    /// Typing pause before the search is sent. Long enough to survive a whole word, short enough
    /// that it does not feel like the app ignored the input.
    static let searchDebounce = Duration.milliseconds(400)

    private(set) var state: State = .idle

    // MARK: Reference data

    private(set) var genres: [Genre] = []
    private(set) var types: [CatalogReference] = []
    private(set) var years: [Int] = []
    private(set) var sortingOptions: [CatalogReference] = []
    private(set) var isReferenceLoaded = false

    // MARK: Current query

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            scheduleSearch()
        }
    }

    private(set) var genreID: Int?
    private(set) var type: String?
    private(set) var year: Int?
    private(set) var sorting: String?

    // MARK: Results

    private(set) var releases: [Release] = []
    private(set) var total = 0
    private(set) var currentPage = 0
    private(set) var hasNextPage = false
    private(set) var isPaging = false

    @ObservationIgnored private let client: AniLibertyClient
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(client: AniLibertyClient = AniLibertyClient()) {
        self.client = client
    }

    // MARK: Derived

    var filter: CatalogFilter {
        CatalogFilter(
            search: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : searchText,
            genreIDs: genreID.map { [$0] } ?? [],
            types: type.map { [$0] } ?? [],
            years: year.map { CatalogYearRange(from: $0, to: $0) },
            sorting: sorting
        )
    }

    var hasActiveFilter: Bool {
        genreID != nil || type != nil || year != nil || sorting != nil
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var genreTitle: String? {
        genreID.flatMap { id in genres.first { $0.id == id }?.name }
    }

    var typeTitle: String? {
        type.flatMap { value in types.first { $0.value == value }?.description }
    }

    var yearTitle: String? {
        year.map(String.init)
    }

    var sortingTitle: String? {
        sorting.flatMap { value in sortingOptions.first { $0.value == value }?.title }
    }

    /// Every reference row the pickers show, in the shape the generic picker understands.
    var genreOptions: [FilterOption] {
        genres.map { FilterOption(id: String($0.id), title: $0.name ?? "") }
    }

    var typeOptions: [FilterOption] {
        types.compactMap { reference in
            guard let value = reference.value else { return nil }
            return FilterOption(id: value, title: reference.description ?? value)
        }
    }

    var yearOptions: [FilterOption] {
        years.reversed().map { FilterOption(id: String($0), title: String($0)) }
    }

    var sortingOptionItems: [FilterOption] {
        sortingOptions.compactMap { reference in
            guard let value = reference.value else { return nil }
            return FilterOption(id: value, title: reference.title ?? value)
        }
    }

    // MARK: Selection

    func selectGenre(_ id: String?) {
        genreID = id.flatMap(Int.init)
        reload()
    }

    func selectType(_ value: String?) {
        type = value
        reload()
    }

    func selectYear(_ value: String?) {
        year = value.flatMap(Int.init)
        reload()
    }

    func selectSorting(_ value: String?) {
        sorting = value
        reload()
    }

    func resetFilters() {
        searchTask?.cancel()
        genreID = nil
        type = nil
        year = nil
        sorting = nil
        if !searchText.isEmpty {
            searchText = ""
        }
        reload()
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        await loadReferenceIfNeeded()
        // The first page may come from the Kit's cache: opening the tab is not a reason to bypass it.
        await load(resetPaging: true, refresh: false)
    }

    /// Reloads from page 1 with the current filter, bypassing the cached page. Cancels whatever was in
    /// flight.
    ///
    /// This is the path taken by filter changes, the search field and the retry button — everything the
    /// viewer does on purpose. Paging, by contrast, reads through the cache.
    func reload() {
        loadTask?.cancel()
        loadTask = Task { await load(resetPaging: true, refresh: true) }
    }

    func loadNextPage() async {
        guard hasNextPage, !isPaging else { return }
        isPaging = true
        defer { isPaging = false }
        await load(resetPaging: false, refresh: false)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDebounce)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func loadReferenceIfNeeded() async {
        guard !isReferenceLoaded else { return }
        do {
            async let genres = client.referenceGenres()
            async let types = client.referenceTypes()
            async let years = client.referenceYears()
            async let sorting = client.referenceSorting()
            self.genres = try await genres
            self.types = try await types
            self.years = try await years
            sortingOptions = try await sorting
            isReferenceLoaded = true
            Self.logger.info(
                "Loaded filters: \(self.genres.count, privacy: .public) genres, \(self.types.count, privacy: .public) types"
            )
        } catch {
            // Filters are an enhancement: without them the catalogue still works, so the screen keeps
            // the entries it has instead of failing.
            Self.logger.error("Filter reference failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load(resetPaging: Bool, refresh: Bool) async {
        if resetPaging {
            state = .loading
        }
        let page = resetPaging ? 1 : currentPage + 1
        do {
            let result = try await client.catalog(
                page: page,
                limit: Self.pageSize,
                filter: filter,
                refresh: refresh
            )
            guard !Task.isCancelled else { return }
            if resetPaging {
                releases = result.releases
            } else {
                let known = Set(releases.map(\.id))
                releases += result.releases.filter { !known.contains($0.id) }
            }
            total = result.total
            currentPage = result.currentPage
            hasNextPage = result.hasNextPage
            state = releases.isEmpty ? .empty : .loaded
            Self.logger
                .info(
                    "Catalogue page \(result.currentPage, privacy: .public) with \(result.releases.count, privacy: .public) releases, total \(result.total, privacy: .public)"
                )
        } catch {
            guard !Task.isCancelled else { return }
            let mapped = AniLibertyError.mapped(error)
            Self.logger.error("Catalogue failed: \(String(describing: mapped), privacy: .public)")
            state = .failed(mapped)
        }
    }
}
