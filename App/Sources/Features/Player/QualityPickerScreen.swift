import AniLibertyKit
import SwiftUI

/// Full-screen quality chooser, presented over the player.
///
/// It is a separate modal on purpose: the system player view owns the focus engine while it is on
/// screen — any arrow press is consumed by its transport bar — so a row of buttons drawn *over* the
/// player can be focused once and then never navigated. A modal cover gets the focus engine to
/// itself, exactly like the player does when the detail screen presents it.
struct QualityPickerScreen: View {
    let sources: [PlaybackSource]
    let selectedQuality: StreamQuality
    let onSelect: (StreamQuality) -> Void
    let onClose: () -> Void

    @FocusState private var focusedQuality: StreamQuality?

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("player.quality.title")
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.white)

                VStack(spacing: 14) {
                    ForEach(sources, id: \.quality) { source in
                        Button {
                            onSelect(source.quality)
                        } label: {
                            HStack(spacing: 16) {
                                Text(verbatim: "\(source.quality.rawValue)p")
                                    .font(DesignTokens.Typography.cardTitle)
                                if source.quality == selectedQuality {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: 360)
                        }
                        .buttonStyle(.glass)
                        .focused($focusedQuality, equals: source.quality)
                        .accessibilityIdentifier("qualityPicker.\(source.quality.rawValue)")
                        .accessibilityAddTraits(source.quality == selectedQuality ? .isSelected : [])
                    }
                }
            }
            .padding(56)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qualityPicker.screen")
        .defaultFocus($focusedQuality, selectedQuality, priority: .userInitiated)
        .onAppear { focusedQuality = selectedQuality }
        .onExitCommand(perform: onClose)
    }
}
