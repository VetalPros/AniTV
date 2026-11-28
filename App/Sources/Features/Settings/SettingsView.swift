import AniLibertyKit
import SwiftUI

/// «Настройки»: the two playback switches, their explanation, and the size of the posters on «Главная».
///
/// Thin on purpose — no networking, no models beyond the stores the Kit already provides. Every change is
/// written immediately, so leaving the tab by any path keeps it.
struct SettingsView: View {
    @State private var settings = PlaybackSettings.defaults
    @State private var posterScale = PosterScale.default
    @State private var isLoaded = false

    private let store: PlaybackSettingsStoring
    private let posterScaleStore: PosterScaleStoring

    init(
        store: PlaybackSettingsStoring = PlaybackSettingsStore(),
        posterScaleStore: PosterScaleStoring = PosterScaleStore()
    ) {
        self.store = store
        self.posterScaleStore = posterScaleStore
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                // The shared header, so «Настройки» starts exactly where every other section does — the
                // shell has no top bar of its own to compensate for (ADR 0028).
                ScreenHeader(title: "screen.settings.title", subtitle: "screen.settings.subtitle")

                VStack(alignment: .leading, spacing: 28) {
                    Toggle("settings.openings", isOn: $settings.skipsOpenings)
                        .accessibilityIdentifier("settings.openings")
                    Toggle("settings.endings", isOn: $settings.skipsEndings)
                        .accessibilityIdentifier("settings.endings")
                }
                .padding(.horizontal, DesignTokens.screenInset)

                Text("settings.hint.caption")
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(.horizontal, DesignTokens.screenInset)

                posterSize

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.screen")
        .task { await load() }
        .onChange(of: settings) { _, value in
            guard isLoaded else { return }
            Task { await store.save(value) }
        }
        .onChange(of: posterScale) { _, value in
            guard isLoaded else { return }
            Task { await posterScaleStore.save(value) }
        }
    }

    /// «Размер постеров на главной»: a heading and the six chips, in their own block so the two playback
    /// switches keep reading as one group.
    private var posterSize: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("settings.posterScale.title")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.white)
            PosterScaleControl(selection: posterScale) { posterScale = $0 }
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, 12)
    }

    private func load() async {
        settings = await store.load()
        posterScale = await posterScaleStore.load()
        isLoaded = true
    }
}
