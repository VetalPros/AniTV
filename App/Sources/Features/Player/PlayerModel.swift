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

    /// Every quality the episode offers, best first. Switching replaces the item instead of
    /// starting a new session, so the playhead survives it.
    let sources: [PlaybackSource]

    /// Quality of the item currently in the player; starts as the one the detail screen resolved.
    private(set) var selectedQuality: StreamQuality

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
        sources = StreamResolver.sources(for: request.episode)
        selectedQuality = request.source.quality
        let item = AVPlayerItem(url: request.source.url)
        // tvOS carries the info-panel metadata on the item, not on the view controller.
        item.externalMetadata = PlayerMetadata.items(for: request, quality: request.source.quality)
        timecodes = TimecodeResolver.timecodes(for: request.episode)
        player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .pause
        observeStatus(of: item)
    }

    // MARK: Quality

    /// Replaces the stream with the same episode rendered at `quality`, keeping the playhead and
    /// re-deriving the skip-intro state from it.
    func selectQuality(_ quality: StreamQuality) {
        guard quality != selectedQuality,
              let source = sources.first(where: { $0.quality == quality })
        else {
            return
        }
        let playhead = player.currentTime()
        let item = AVPlayerItem(url: source.url)
        item.externalMetadata = PlayerMetadata.items(for: request, quality: quality)
        statusObservation?.invalidate()
        observeStatus(of: item)
        player.replaceCurrentItem(with: item)
        player.seek(to: playhead, toleranceBefore: .zero, toleranceAfter: .zero)
        selectedQuality = quality
        // The periodic observer re-derives this half a second later anyway; doing it here keeps the
        // skip button from showing the state of the previous item in between.
        activeSkip = TimecodeResolver.activeSkip(for: timecodes, playhead: playhead.seconds)
        player.play()
        Self.logger.info("Switched to \(quality.rawValue, privacy: .public)p at \(playhead.seconds, privacy: .public)s")
    }

    // MARK: Lifecycle

    func start() {
        addPlayheadObserver()
        player.play()
        Self.logger.info("Playback started at \(self.selectedQuality.rawValue, privacy: .public)p")
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
