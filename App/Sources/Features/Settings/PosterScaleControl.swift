import AniLibertyKit
import SwiftUI

/// The six poster sizes «Главная» can draw, as chips: «100 %» … «150 %».
///
/// A row of chips, not a `Picker`: on tvOS a picker opens a menu on top of the screen, and this choice is
/// six numbers a viewer wants to compare side by side. The current size keeps the accent colour and an
/// accent outline whether or not it holds focus, so the setting reads without moving the remote.
struct PosterScaleControl: View {
    /// Size currently stored; the chip for it is drawn as selected.
    let selection: PosterScale
    /// Called with the chip the viewer selected.
    let onSelect: (PosterScale) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(PosterScale.allCases) { scale in
                chip(for: scale)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.posterScale")
    }

    private func chip(for scale: PosterScale) -> some View {
        let isSelected = scale == selection
        return Button {
            onSelect(scale)
        } label: {
            Text(title(for: scale))
                .font(DesignTokens.Typography.body)
                .foregroundStyle(isSelected ? Palette.accent : .white)
                .monospacedDigit()
        }
        .buttonStyle(.glass)
        .overlay {
            if isSelected {
                Capsule()
                    .strokeBorder(Palette.accent, lineWidth: 2)
            }
        }
        .accessibilityIdentifier("settings.posterScale.\(scale.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func title(for scale: PosterScale) -> LocalizedStringKey {
        switch scale {
        case .percent100: "settings.posterScale.100"
        case .percent110: "settings.posterScale.110"
        case .percent120: "settings.posterScale.120"
        case .percent130: "settings.posterScale.130"
        case .percent140: "settings.posterScale.140"
        case .percent150: "settings.posterScale.150"
        }
    }
}
