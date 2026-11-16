import SwiftUI

/// One row a filter picker can offer: a stable identifier sent to the API and the text shown.
struct FilterOption: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Modal single-choice picker behind a filter chip.
///
/// It is a modal for the same reason the quality chooser is: the focus engine belongs to whatever is
/// on screen, and a cover gets it to itself. Choosing an option applies it immediately and closes;
/// Menu closes without changing anything.
struct FilterPickerScreen: View {
    let title: LocalizedStringKey
    let options: [FilterOption]
    let selectedID: String?
    let onSelect: (String?) -> Void
    let onClose: () -> Void

    @FocusState private var focusedID: String?

    /// Sentinel for the "no constraint" row, so it can hold focus like any other option.
    private static let anyID = ""

    var body: some View {
        ZStack {
            AniTVBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.white)

                ScrollView(.vertical) {
                    VStack(spacing: 12) {
                        optionRow(id: Self.anyID, title: "catalog.filter.any") {
                            onSelect(nil)
                        }
                        ForEach(options) { option in
                            optionRow(id: option.id, title: LocalizedStringKey(option.title)) {
                                onSelect(option.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.vertical, 56)
            .frame(maxWidth: 900)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filterPicker.screen")
        .defaultFocus($focusedID, selectedID ?? Self.anyID, priority: .userInitiated)
        .onAppear { focusedID = selectedID ?? Self.anyID }
        .onExitCommand(perform: onClose)
    }

    private func optionRow(
        id: String,
        title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        let isSelected = (id == Self.anyID ? selectedID == nil : id == selectedID)
        return Button(action: action) {
            HStack(spacing: 14) {
                Text(title)
                    .font(DesignTokens.Typography.body)
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
        .focused($focusedID, equals: id)
        .accessibilityIdentifier("filterPicker.option.\(id.isEmpty ? "any" : id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
