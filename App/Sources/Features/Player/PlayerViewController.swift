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
    /// Hint to show, `nil` when it has to stay out of the way.
    let hint: PlayerModel.SkipAction?
    /// Acts on the hint: seek past the segment, or hand over to the next episode.
    let onHintAction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> QualityPlayerViewController {
        let controller = QualityPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.backgroundColor = .black
        context.coordinator.installOverlay(on: controller, from: self)
        context.coordinator.updateMenu(on: controller, from: self)
        return controller
    }

    func updateUIViewController(_ controller: QualityPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.updateOverlay(on: controller, from: self)
        context.coordinator.updateMenu(on: controller, from: self)
    }

    @MainActor
    final class Coordinator {
        /// The skip hint, built in UIKit inside the player's content overlay.
        private var overlay: SkipHintOverlayView?
        /// Trailing inset of the hint.
        private static let overlayInset: CGFloat = 120
        /// How far the hint sits above the bottom edge.
        ///
        /// The transport bar is drawn over the bottom ~200 pt of the screen (scrubber, elapsed time, the
        /// quality and audio chips), so the hint lives above that band instead of hiding whenever the bar is
        /// open: there is no public callback for the bar, and hiding on focus made the control disappear while
        /// the viewer was moving to it.
        private static let overlayBottomInset: CGFloat = 300

        func installOverlay(on controller: QualityPlayerViewController, from representable: PlayerViewController) {
            guard let contentOverlay = controller.contentOverlayView else { return }
            let overlay = SkipHintOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.onSkip = representable.onHintAction
            contentOverlay.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.trailingAnchor.constraint(
                    equalTo: contentOverlay.trailingAnchor,
                    constant: -Self.overlayInset
                ),
                overlay.bottomAnchor.constraint(
                    equalTo: contentOverlay.bottomAnchor,
                    constant: -Self.overlayBottomInset
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
            overlay.onSkip = representable.onHintAction

            guard let action = representable.hint else {
                overlay.isHidden = true
                controller.overlayIsVisible = false
                return
            }
            overlay.configure(title: Self.title(for: action), isProminent: action == .nextEpisode)
            overlay.isHidden = false
            if !controller.overlayIsVisible {
                controller.overlayIsVisible = true
                // Ask for focus once, then leave the focus engine alone: keeping the overlay as the preferred
                // environment would trap focus inside it and the transport bar could never open.
                controller.requestOverlayFocus()
            }
        }

        private static func title(for action: PlayerModel.SkipAction) -> String {
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

    // Called when focus enters or leaves the custom overlay.

    /// The skip hint, used to tell "our controls have focus" from "the player's own controls have it".
    weak var overlayView: SkipHintOverlayView?

    /// Whether the hint is currently shown.
    var overlayIsVisible = false

    /// Preferred focus: the hint, while it is on screen.
    ///
    /// There is one control now, so keeping the hint focused is what makes Select press it — the owner's
    /// report that Right only scrubbed was exactly this: the hint never held focus. Nothing else lives in the
    /// overlay, so there is no second control to reach and no reason to hand focus back.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if overlayIsVisible, let overlayView {
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
