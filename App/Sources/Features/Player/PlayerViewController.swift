import AniLibertyKit
import AVKit
import os
import SwiftUI
import UIKit

/// Thin SwiftUI wrapper around the system `AVPlayerViewController`.
///
/// The transport UI, scrubbing, info panel and remote handling stay first-party; the app only
/// supplies the player and one extra entry — the quality menu — through the sanctioned
/// `transportBarCustomMenuItems` hook.
struct PlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    /// Every quality of the episode, best first.
    let qualities: [StreamQuality]
    let selectedQuality: StreamQuality
    let onSelectQuality: (StreamQuality) -> Void
    /// Skip hint to show, `nil` when it has to stay out of the way.
    let skip: SkipTimecode?
    let onSkip: () -> Void
    let onDismissSkip: () -> Void
    /// A Select press that the player itself consumed: the transport bar was toggled.
    let onPlayerSelect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> QualityPlayerViewController {
        let controller = QualityPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.backgroundColor = .black
        controller.onPlayerSelect = onPlayerSelect
        context.coordinator.installOverlay(on: controller, from: self)
        context.coordinator.updateMenu(on: controller, from: self)
        return controller
    }

    func updateUIViewController(_ controller: QualityPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.onPlayerSelect = onPlayerSelect
        context.coordinator.updateOverlay(on: controller, from: self)
        context.coordinator.updateMenu(on: controller, from: self)
    }

    @MainActor
    final class Coordinator {
        /// Hosts the skip hint inside the player's content overlay.
        private var hosting: UIHostingController<SkipHintView>?
        /// Bottom/trailing inset of the hint, so it clears the scrubber even when both are visible.
        private static let overlayInset: CGFloat = 120

        func installOverlay(on controller: QualityPlayerViewController, from representable: PlayerViewController) {
            guard let overlay = controller.contentOverlayView else { return }
            let hosting = UIHostingController(rootView: Self.hint(from: representable))
            hosting.view.backgroundColor = .clear
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            controller.addChild(hosting)
            overlay.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.trailingAnchor.constraint(
                    equalTo: overlay.trailingAnchor,
                    constant: -Self.overlayInset
                ),
                hosting.view.bottomAnchor.constraint(
                    equalTo: overlay.bottomAnchor,
                    constant: -Self.overlayInset
                ),
                hosting.view.leadingAnchor.constraint(
                    greaterThanOrEqualTo: overlay.leadingAnchor,
                    constant: Self.overlayInset
                ),
            ])
            hosting.didMove(toParent: controller)
            controller.overlayHostView = hosting.view
            self.hosting = hosting
            updateOverlay(on: controller, from: representable)
        }

        func updateOverlay(on _: QualityPlayerViewController, from representable: PlayerViewController) {
            hosting?.rootView = Self.hint(from: representable)
            // Hidden rather than removed: the hosting view keeps its place in the focus order, and an
            // invisible hint must not be focusable or draw over the transport bar.
            hosting?.view.isHidden = representable.skip == nil
        }

        private static func hint(from representable: PlayerViewController) -> SkipHintView {
            SkipHintView(
                skip: representable.skip,
                onSkip: representable.onSkip,
                onDismiss: representable.onDismissSkip
            )
        }

        func updateMenu(on controller: QualityPlayerViewController, from representable: PlayerViewController) {
            controller.menuProvider = { Self.payload(from: representable) }
            controller.applyMenuItems()
        }

        /// One `UIMenu` with an action per stream.
        ///
        /// Two shapes of the same data behave differently here, and only this one is usable: a list of
        /// flat `UIAction`s is drawn as unlabelled circles that the focus engine never reaches, while a
        /// single `UIMenu` becomes a real transport-bar button that opens the system popup
        /// (ADR 0016, superseding ADR 0014).
        private static func payload(
            from representable: PlayerViewController
        ) -> (menu: UIMenu, signature: String) {
            let actions = representable.qualities.map { quality in
                UIAction(
                    title: "\(quality.rawValue)p",
                    state: quality == representable.selectedQuality ? .on : .off
                ) { _ in
                    representable.onSelectQuality(quality)
                }
            }
            let menu = UIMenu(
                title: String(localized: "player.quality.menu"),
                image: badge(for: representable.selectedQuality),
                children: actions
            )
            let signature = representable.qualities.map(\.rawValue).joined(separator: ",")
                + "@\(representable.selectedQuality.rawValue)"
            return (menu, signature)
        }

        /// The transport bar draws its entry from the image alone — the title only reaches VoiceOver —
        /// so the image *is* the label: the running quality, written out ("1080p"). A generic glyph
        /// told the viewer nothing.
        private static func badge(for quality: StreamQuality) -> UIImage {
            let text = "\(quality.rawValue)p" as NSString
            let font = UIFont.systemFont(ofSize: 27, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
            ]
            let textSize = text.size(withAttributes: attributes)
            let size = CGSize(width: ceil(textSize.width) + 8, height: ceil(textSize.height))
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                text.draw(at: CGPoint(x: 4, y: 0), withAttributes: attributes)
            }
            return image.withRenderingMode(.alwaysOriginal)
        }
    }
}

/// `AVPlayerViewController` that keeps its custom transport-bar entry in place.
///
/// AVKit builds the transport bar lazily and drops items assigned before it exists, so the entry is
/// re-applied for the first seconds after the view appears.
final class QualityPlayerViewController: AVPlayerViewController {
    private static let logger = Logger(subsystem: "tv.anitv.client", category: "TransportBar")

    private static let settleTicks = 6

    var menuProvider: (() -> (menu: UIMenu, signature: String))?

    /// A Select press that reached the player instead of the custom overlay: the transport bar toggled.
    var onPlayerSelect: (() -> Void)?

    /// The hosted skip hint, used to tell "our controls have focus" from "the transport bar has focus".
    weak var overlayHostView: UIView?

    private var appliedSignature: String?

    private var remainingTicks = 0
    private var refreshTimer: Timer?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyMenuItems()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        remainingTicks = Self.settleTicks
        applyMenuItems()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyMenuItems()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// AVKit has no "transport bar is open" callback, so the toggle is observed where it happens: a Select
    /// press that reaches this controller and was *not* meant for the custom overlay flips the system
    /// playback controls. Presses consumed by the overlay's buttons never come this far.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .select }), !isFocusInsideOverlay() {
            onPlayerSelect?()
        }
        super.pressesBegan(presses, with: event)
    }

    private func isFocusInsideOverlay() -> Bool {
        guard let overlayHostView,
              let focused = UIFocusSystem.focusSystem(for: self)?.focusedItem as? UIView
        else {
            return false
        }
        return focused.isDescendant(of: overlayHostView)
    }

    func applyMenuItems() {
        guard let payload = menuProvider?() else { return }
        // While the bar is being built the entry is re-applied unconditionally; afterwards only when
        // what it shows changed, so the menu does not close under the viewer's finger.
        guard remainingTicks > 0 || payload.signature != appliedSignature else { return }
        transportBarCustomMenuItems = [payload.menu]
        appliedSignature = payload.signature
        if remainingTicks > 0 {
            remainingTicks -= 1
        }
        if remainingTicks == 0 {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        Self.logger.info("Transport bar quality menu applied (\(payload.signature, privacy: .public))")
    }
}
