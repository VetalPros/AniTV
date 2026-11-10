import AVKit
import SwiftUI

/// Thin SwiftUI wrapper around the system `AVPlayerViewController`.
///
/// The transport UI, scrubbing, info panel and remote handling stay first-party; the app only
/// supplies the player. Full-screen presentation is owned by the enclosing `fullScreenCover`, so no
/// delegate round-trip is needed.
struct PlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        guard controller.player !== player else { return }
        controller.player = player
    }
}
