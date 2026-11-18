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
    let skipAction: PlayerModel.SkipAction?
    let onSkip: () -> Void
    let onNextEpisode: () -> Void
    let onDismissSkip: () -> Void
    /// Focus left the hint (the viewer is in the player's own controls) or came back.
    let onPlaybackControlsChange: (Bool) -> Void
    /// A press the player itself handled while the hint was not focused.
    let onPlayerInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> QualityPlayerViewController {
        let controller = QualityPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.backgroundColor = .black
        controller.onPlaybackControlsChange = onPlaybackControlsChange
        controller.onPlayerInteraction = onPlayerInteraction
        context.coordinator.installOverlay(on: controller, from: self)
        context.coordinator.updateMenu(on: controller, from: self)
        return controller
    }

    func updateUIViewController(_ controller: QualityPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.onPlaybackControlsChange = onPlaybackControlsChange
        controller.onPlayerInteraction = onPlayerInteraction
        context.coordinator.updateOverlay(on: controller, from: self)
        context.coordinator.updateMenu(on: controller, from: self)
    }

    @MainActor
    final class Coordinator {
        /// The skip hint, built in UIKit inside the player's content overlay.
        private var overlay: SkipHintOverlayView?
        /// Bottom/trailing inset of the hint, so it clears the scrubber even when both are visible.
        private static let overlayInset: CGFloat = 120

        func installOverlay(on controller: QualityPlayerViewController, from representable: PlayerViewController) {
            guard let contentOverlay = controller.contentOverlayView else { return }
            let overlay = SkipHintOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.onSkip = representable.onSkip
            overlay.onDismiss = representable.onDismissSkip
            contentOverlay.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.trailingAnchor.constraint(
                    equalTo: contentOverlay.trailingAnchor,
                    constant: -Self.overlayInset
                ),
                overlay.bottomAnchor.constraint(
                    equalTo: contentOverlay.bottomAnchor,
                    constant: -Self.overlayInset
                ),
                overlay.leadingAnchor.constraint(
                    greaterThanOrEqualTo: contentOverlay.leadingAnchor,
                    constant: Self.overlayInset
                ),
            ])
            controller.overlayView = overlay
            self.overlay = overlay
            updateOverlay(on: controller, from: representable)
        }

        func updateOverlay(on controller: QualityPlayerViewController, from representable: PlayerViewController) {
            guard let overlay else { return }
            overlay.onSkip = representable.onSkip
            overlay.onDismiss = representable.onDismissSkip

            guard let action = representable.skipAction else {
                overlay.isHidden = true
                controller.overlayIsVisible = false
                return
            }
            overlay.configure(
                primary: Self.primaryTitle(for: action),
                primaryIsProminent: action == .nextEpisode || Self.isOpening(action),
                dismiss: String(localized: "player.skip.dismiss")
            )
            overlay.isHidden = false
            if !controller.overlayIsVisible {
                controller.overlayIsVisible = true
                controller.resetOverlayFocusGrant()
                // Ask for focus once, then leave the focus engine alone: keeping the overlay as the preferred
                // environment would trap focus inside it and the transport bar could never open.
                controller.requestOverlayFocus()
            }
        }

        private static func isOpening(_ action: PlayerModel.SkipAction) -> Bool {
            action.skipTimecode?.kind == .opening
        }

        private static func primaryTitle(for action: PlayerModel.SkipAction) -> String {
            switch action {
            case let .skip(timecode):
                let key = timecode.kind == .opening ? "player.skip.opening" : "player.skip.ending"
                return String(localized: String.LocalizationValue(key))
            case .nextEpisode:
                return String(localized: "player.skip.nextEpisode")
            }
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

    /// Called when focus enters or leaves the custom overlay.
    var onPlaybackControlsChange: ((Bool) -> Void)?

    /// The skip hint, used to tell "our controls have focus" from "the player's own controls have it".
    weak var overlayView: SkipHintOverlayView?

    /// A press the player handled itself while the hint was not focused.
    var onPlayerInteraction: (() -> Void)?

    /// Whether the hint is currently shown.
    var overlayIsVisible = false

    /// Whether the hint has already been given the focus once for the current appearance.
    ///
    /// The overlay is the preferred focus target only until the engine has actually landed on it; after that
    /// it is released, otherwise focus could never leave and the transport bar would never open.
    private var overlayFocusGranted = false

    /// Whether focus currently sits inside the custom overlay.
    private var overlayHasFocus = false

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        // The focus engine is the only honest signal about where the viewer is: there is no public callback
        // for "the transport bar is open", but while focus is inside the system controls the hint has to be
        // out of the way, and it comes back as soon as focus returns to it.
        updateOverlayFocus(isInside: isFocusInsideOverlay)
    }

    private func updateOverlayFocus(isInside: Bool) {
        if isInside {
            overlayFocusGranted = true
        }
        guard overlayHasFocus != isInside else { return }
        overlayHasFocus = isInside
        onPlaybackControlsChange?(!isInside)
    }

    private var isFocusInsideOverlay: Bool {
        guard let overlayView,
              let focused = UIFocusSystem.focusSystem(for: self)?.focusedItem as? UIView
        else {
            return false
        }
        return focused.isDescendant(of: overlayView)
    }

    /// Preferred focus: the hint, until it has had its turn.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if overlayIsVisible, !overlayFocusGranted, let overlayView {
            return [overlayView]
        }
        return super.preferredFocusEnvironments
    }

    /// Routes a focus request to the hint.
    ///
    /// This happens once per appearance of the hint. The controller does **not** keep the overlay as its
    /// preferred focus environment: doing that traps focus inside the hint, the transport bar never opens and
    /// the focus engine has nothing to report.
    func requestOverlayFocus() {
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    /// Lets the next appearance of the hint ask for focus again.
    func resetOverlayFocusGrant() {
        overlayFocusGranted = false
    }

    /// Presses that reach the controller are the ones the hint did not consume: the viewer is in the player.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !presses.isEmpty, !isFocusInsideOverlay {
            onPlayerInteraction?()
        }
        super.pressesBegan(presses, with: event)
    }

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
