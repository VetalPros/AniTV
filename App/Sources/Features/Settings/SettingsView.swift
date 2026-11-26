import AniLibertyKit
import SwiftUI

/// «Настройки»: the two playback switches and nothing else.
///
/// Thin on purpose — no networking, no models beyond the store the Kit already provides. Every change is
/// written immediately, so leaving the tab by any path keeps it.
struct SettingsView: View {
    @State private var settings = PlaybackSettings.defaults
    @State private var isLoaded = false

    private let store: PlaybackSettingsStoring

    init(store: PlaybackSettingsStoring = PlaybackSettingsStore()) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 36) {
                header

                VStack(alignment: .leading, spacing: 28) {
                    Toggle("settings.openings", isOn: $settings.skipsOpenings)
                        .accessibilityIdentifier("settings.openings")
                    Toggle("settings.endings", isOn: $settings.skipsEndings)
                        .accessibilityIdentifier("settings.endings")
                }

                Text("settings.hint.caption")
                    .font(DesignTokens.Typography.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 900, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 80)
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.screen")
        .task { await load() }
        .onChange(of: settings) { _, value in
            guard isLoaded else { return }
            Task { await store.save(value) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("screen.settings.title")
                .font(DesignTokens.Typography.screenTitle)
            Text("screen.settings.subtitle")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        settings = await store.load()
        isLoaded = true
    }
}
