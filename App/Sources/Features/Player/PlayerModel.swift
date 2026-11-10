import AniLibertyKit
import AVFoundation
import Foundation
import Observation
import os

/// Owns the `AVPlayer` for one playback session: skip-intro detection, failure surfacing and
/// teardown. Playback *resolution* already happened on the detail screen, so this type never talks
/// to the network and never builds URLs.
@MainActor
@Observable
final class PlayerModel {
    private static let logger = Logger(subsystem: "tv.anitv.client", category: "Player")

    /// Playhead polling cadence. Half a second is the coarsest interval that still hides an intro
    /// within a comfortable margin of its first frame.
    private static let playheadInterval = CMTime(seconds: 0.5, preferredTimescale: 600)

    let request: PlaybackRequest
    let player: AVPlayer

    /// The skip segment the playhead currently sits inside, or `nil` when no button should exist.
    private(set) var activeSkip: SkipTimecode?

    /// Localised player failure (technical cause kept separate from UI copy). `nil` while healthy.
    private(set) var playbackError: String?

    /// Every skippable range of the episode, resolved once because the episode never changes.
    @ObservationIgnored private let timecodes: [SkipTimecode]

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(request: PlaybackRequest) {
        self.request = request
        let item = AVPlayerItem(url: request.source.url)
        // tvOS carries the info-panel metadata on the item, not on the view controller.
        item.externalMetadata = PlayerMetadata.items(for: request)
        timecodes = TimecodeResolver.timecodes(for: request.episode)
        player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .pause
        observeStatus(of: item)
    }

    // MARK: Lifecycle

    func start() {
        addPlayheadObserver()
        player.play()
        Self.logger.info("Playback started at \(self.request.source.quality.rawValue, privacy: .public)p")
    }

    func stop() {
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        Self.logger.info("Playback stopped")
    }

    // MARK: Skip intro / outro

    /// Jumps to the end of the active segment and hides the button until the next segment.
    func skipActiveSegment() {
        guard let activeSkip else { return }
        player.seek(
            to: CMTime(seconds: activeSkip.end, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        self.activeSkip = nil
        Self.logger.info("Skipped \(String(describing: activeSkip.kind), privacy: .public) segment")
    }

    private func addPlayheadObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: Self.playheadInterval,
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self?.updateSkip(for: seconds)
            }
        }
    }

    private func updateSkip(for playhead: Double) {
        activeSkip = TimecodeResolver.activeSkip(for: timecodes, playhead: playhead)
    }

    // MARK: Failure handling

    /// `AVPlayerItem.status` changes on a framework thread, hence the hop back to the main actor.
    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let description = item.error?.localizedDescription
            Task { @MainActor in
                self?.surface(error: description)
            }
        }
    }

    private func surface(error description: String?) {
        guard playbackError == nil else { return }
        playbackError = description
        player.pause()
        Self.logger.error(
            "Playback failed: \(description ?? "unknown cause", privacy: .public)"
        )
    }
}
