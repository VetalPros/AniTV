import AniLibertyKit
import SwiftUI

/// The catalogue screen, in one of two shapes (ADR 0030): «Поиск» finds a title by name, «Каталог»
/// browses it by filters. Both share the view model, the paging and the detail push.
///
/// The screen keeps its own navigation stack so a poster pushes the same detail screen the
/// «Новинки» section uses; the filter pickers are covers, not part of the stack.
struct CatalogView: View {
    /// Which shape the screen takes. Search shows the text field, browse shows the filter chips; a screen
    /// that showed both would have to explain why half of it is redundant.
    enum Mode: String {
        case search
        case browse

        var title: LocalizedStringKey {
            switch self {
            case .search: "screen.search.title"
            case .browse: "screen.catalog.title"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .search: "screen.search.subtitle"
            case .browse: "screen.catalog.subtitle"
            }
        }
    }

    /// Defaults to search so a preview or a test can build the screen with no arguments.
    var mode: Mode = .search

    @State private var model = CatalogViewModel()
    /// Owned by the shell, so the section survives its own view being recreated (ADR 0028 §7).
    @Binding var path: [ReleaseRoute]
    @State private var picker: FilterPicker?
    @FocusState private var isSearchFocused: Bool

    /// Which filter picker is open, if any.
    private enum FilterPicker: String, Identifiable {
        case genre
        case type
        case year
        case sorting

        var id: String {
            rawValue
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AniTVBackground()
                VStack(spacing: 0) {
                    ScreenHeader(title: mode.title, subtitle: mode.subtitle) {
                        resultCount
                    }
                    controls
                    results
                }
            }
            .navigationDestination(for: ReleaseRoute.self) { route in
                ReleaseDetailView(route: route)
            }
        }
        .task { await model.loadIfNeeded() }
        .fullScreenCover(item: $picker) { picker in
            pickerScreen(for: picker)
        }
    }

    // MARK: Header and controls

    @ViewBuilder
    private var resultCount: some View {
        if !isIdle {
            Text("catalog.found \(model.total)")
                .font(DesignTokens.Typography.screenSubtitle)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("catalog.resultCount")
        }
    }

    private var isIdle: Bool {
        if case .idle = model.state {
            return true
        }
        return false
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if mode == .search {
                searchField
            }
            if mode == .browse {
                filterChips
            }
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.bottom, 28)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("catalog.search.placeholder", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(DesignTokens.Typography.body)
                .frame(height: 44)
                .submitLabel(.search)
                .focused($isSearchFocused)
                .accessibilityIdentifier("catalog.searchField")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: 680, alignment: .leading)
        // The glass has to be a shape behind the field: applying it to the composite made the whole
        // row render as nothing on tvOS (the field drew nothing over the effect).
        .background {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .glassEffect(.regular, in: Capsule())
        }
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var filterChips: some View {
        HStack(spacing: 14) {
            chip("catalog.filter.genre", value: model.genreTitle, identifier: "catalog.genreChip") {
                picker = .genre
            }
            chip("catalog.filter.type", value: model.typeTitle, identifier: "catalog.typeChip") {
                picker = .type
            }
            chip("catalog.filter.year", value: model.yearTitle, identifier: "catalog.yearChip") {
                picker = .year
            }
            chip("catalog.filter.sorting", value: model.sortingTitle, identifier: "catalog.sortingChip") {
                picker = .sorting
            }
            if model.hasActiveFilter {
                Button("catalog.filter.reset") {
                    model.resetFilters()
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("catalog.resetButton")
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(
        _ title: LocalizedStringKey,
        value: String?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let value {
                    Text(verbatim: value)
                        .foregroundStyle(Palette.accent)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(Text(verbatim: value ?? ""))
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        switch model.state {
        case .idle, .loading:
            LoadingStateView(message: "catalog.loading")
        case .loaded:
            gridContent
        case .empty:
            failureLayout {
                EmptyStateView(title: "catalog.empty.title", message: "catalog.empty.message")
            }
        case let .failed(error):
            failureLayout {
                ErrorStateView(
                    title: "catalog.failed.title",
                    message: error.userMessageKey,
                    retry: { model.reload() }
                )
            }
        }
    }

    private var gridContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DesignTokens.sectionSpacing) {
                ReleasePosterGrid(releases: model.releases, takesDefaultFocus: false) { release in
                    path.append(ReleaseRoute(release: release))
                }
                if model.hasNextPage {
                    loadMoreButton
                }
            }
            .padding(.bottom, 88)
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task { await model.loadNextPage() }
        } label: {
            HStack(spacing: 10) {
                if model.isPaging {
                    ProgressView()
                }
                Text("catalog.pagination.more")
            }
        }
        .buttonStyle(.glass)
        .disabled(model.isPaging)
        .accessibilityIdentifier("catalog.loadMoreButton")
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DesignTokens.screenInset)
    }

    private func failureLayout(@ViewBuilder content: () -> some View) -> some View {
        VStack {
            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: Pickers

    @ViewBuilder
    private func pickerScreen(for picker: FilterPicker) -> some View {
        switch picker {
        case .genre:
            FilterPickerScreen(
                title: "catalog.filter.genre",
                options: model.genreOptions,
                selectedID: model.genreID.map(String.init),
                onSelect: { id in
                    model.selectGenre(id)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        case .type:
            FilterPickerScreen(
                title: "catalog.filter.type",
                options: model.typeOptions,
                selectedID: model.type,
                onSelect: { value in
                    model.selectType(value)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        case .year:
            FilterPickerScreen(
                title: "catalog.filter.year",
                options: model.yearOptions,
                selectedID: model.year.map(String.init),
                onSelect: { value in
                    model.selectYear(value)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        case .sorting:
            FilterPickerScreen(
                title: "catalog.filter.sorting",
                options: model.sortingOptionItems,
                selectedID: model.sorting,
                onSelect: { value in
                    model.selectSorting(value)
                    self.picker = nil
                },
                onClose: { self.picker = nil }
            )
        }
    }
}
