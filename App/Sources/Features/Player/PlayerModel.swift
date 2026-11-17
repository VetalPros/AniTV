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

    /// How often the position is persisted while playback runs. Five seconds is short enough to
    /// survive a crash and long enough not to write on every poll.
    private static let progressSaveInterval: TimeInterval = 5

    let request: PlaybackRequest
    let player: AVPlayer

    /// Every quality the episode offers, best first. Switching replaces the item instead of
    /// starting a new session, so the playhead survives it.
    let sources: [PlaybackSource]

    /// Quality of the item currently in the player; starts as the one the detail screen resolved.
    private(set) var selectedQuality: StreamQuality

    /// The skip segment the playhead currently sits inside, or `nil` when no button should exist.
    private(set) var activeSkip: SkipTimecode?

    /// Segment the viewer already waved away with «Смотреть». It stays hidden for that segment only, so
    /// the next opening or ending of the same episode shows the hint again.
    private(set) var dismissedSkipKey: String?

    /// Whether the system playback controls are (believed to be) on screen.
    ///
    /// There is no public "transport bar is open" callback; see ``setPlaybackControlsOpen(_:)`` for what
    /// drives this.
    private(set) var isPlaybackControlsOpen = false

    /// The hint to show right now, or `nil` when it has to stay out of the way.
    var visibleSkip: SkipTimecode? {
        guard let activeSkip, !isPlaybackControlsOpen, Self.key(for: activeSkip) != dismissedSkipKey else {
            return nil
        }
        return activeSkip
    }

    /// Localised player failure (technical cause kept separate from UI copy). `nil` while healthy.
    private(set) var playbackError: String?

    /// Every skippable range of the episode, resolved once because the episode never changes.
    @ObservationIgnored private let timecodes: [SkipTimecode]

    /// Where the position is persisted; injected so tests and previews can use a fake.
    @ObservationIgnored private let progressStore: PlaybackProgressStoring

    /// When the position was written last, so the periodic observer writes at most every
    /// ``progressSaveInterval`` seconds.
    @ObservationIgnored private var lastSavedAt = Date.distantPast

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    init(request: PlaybackRequest, progressStore: PlaybackProgressStoring = PlaybackProgressStore()) {
        self.request = request
        self.progressStore = progressStore
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
        if let startAt = startPosition, startAt > 0 {
            player.seek(
                to: CMTime(seconds: startAt, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            activeSkip = TimecodeResolver.activeSkip(for: timecodes, playhead: startAt)
            Self.logger.info("Resuming at \(startAt, privacy: .public)s")
        }
        player.play()
        Self.logger.info("Playback started at \(self.selectedQuality.rawValue, privacy: .public)p")
    }

    func stop() {
        // Persist before tearing the player down: the last periodic save can be seconds behind, and a
        // viewer who leaves right after rewinding would otherwise lose the position.
        saveProgress(at: player.currentTime().seconds)
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        Self.logger.info("Playback stopped")
    }

    /// Position the player should start at: the UI-test override when present, otherwise the request's.
    ///
    /// The opening/ending overrides resolve against this episode's own timecodes, so a test can watch a
    /// segment that starts twenty minutes into the episode without scrubbing there.
    private var startPosition: TimeInterval? {
        if let seconds = PlayerTestOverrides.startAt() {
            return seconds
        }
        if PlayerTestOverrides.startsAtOpening() {
            return timecodes.first { $0.kind == .opening }.map { $0.start + 2 } ?? request.startAt
        }
        if PlayerTestOverrides.startsAtEnding() {
            return timecodes.first { $0.kind == .ending }.map { $0.start + 2 } ?? request.startAt
        }
        return request.startAt
    }

    // MARK: Progress

    /// Writes the current position when the last write is older than ``progressSaveInterval``.
    private func saveProgressIfDue(at playhead: Double) {
        guard Date().timeIntervalSince(lastSavedAt) >= Self.progressSaveInterval else { return }
        lastSavedAt = .now
        saveProgress(at: playhead)
    }

    /// Persists `playhead` together with the item duration when it is known.
    ///
    /// The position is stored as it is, even when the Kit's ``PlaybackProgress/isResumable`` would
    /// refuse it: the detail screen decides whether to offer «Продолжить», and an unfinished episode
    /// keeps an honest record of where it stopped.
    private func saveProgress(at playhead: Double) {
        guard playhead.isFinite, playhead > 0 else { return }
        let progress = PlaybackProgress(
            releaseAlias: request.releaseAlias,
            episodeID: request.episode.id,
            position: playhead,
            duration: itemDuration()
        )
        let store = progressStore
        Task {
            await store.save(progress)
        }
        Self.logger.debug("Saved progress at \(playhead, privacy: .public)s")
    }

    /// Length of the current item, or `nil` while it is still indefinite.
    private func itemDuration() -> Double? {
        guard let duration = player.currentItem?.duration, duration.isNumeric else { return nil }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }

    // MARK: Skip intro / outro

    /// Jumps past the active segment and keeps playing.
    ///
    /// Skipping an ending therefore lands on the last second of the episode: choosing what plays next is
    /// the detail screen's job, not the player's.
    func skipActiveSegment() {
        guard let activeSkip else { return }
        player.seek(
            to: CMTime(seconds: activeSkip.end, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        self.activeSkip = nil
        player.play()
        Self.logger.info("Skipped \(String(describing: activeSkip.kind), privacy: .public) segment")
    }

    /// Hides the hint for the current segment without touching the playhead.
    func dismissSkipHint() {
        guard let activeSkip else { return }
        dismissedSkipKey = Self.key(for: activeSkip)
        Self.logger.info("Skip hint dismissed for \(String(describing: activeSkip.kind), privacy: .public)")
    }

    /// Records whether the system playback controls are on screen.
    ///
    /// AVKit exposes no callback for the transport bar, so the app derives it from the presses the player
    /// itself consumes: Select toggles that bar, and a press that reaches the player is by definition one
    /// our overlay did not swallow. The hint is hidden while the flag is set.
    ///
    /// - Parameter open: `true` when the bar is believed to be visible.
    func setPlaybackControlsOpen(_ open: Bool) {
        guard isPlaybackControlsOpen != open else { return }
        isPlaybackControlsOpen = open
        Self.logger.info("Playback controls \(open ? "opened" : "closed", privacy: .public)")
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
                self?.saveProgressIfDue(at: seconds)
            }
        }
    }

    private func updateSkip(for playhead: Double) {
        let skip = TimecodeResolver.activeSkip(for: timecodes, playhead: playhead)
        if let skip, let dismissedSkipKey, Self.key(for: skip) != dismissedSkipKey {
            // A different segment: the viewer's earlier "не сейчас" does not carry over.
            self.dismissedSkipKey = nil
        }
        activeSkip = skip
    }

    /// Stable identity of a segment, used to remember that its hint was dismissed.
    private static func key(for skip: SkipTimecode) -> String {
        switch skip.kind {
        case .opening: "opening-\(skip.start)-\(skip.end)"
        case .ending: "ending-\(skip.start)-\(skip.end)"
        }
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
