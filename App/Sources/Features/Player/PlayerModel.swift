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

    /// How long the skip hint stays on screen without a press. The owner chose thirty seconds: long enough to
    /// read the offer and decide, short enough not to sit on the picture for a whole episode.
    static let productionHintLifetime: Duration = .seconds(30)

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

    /// What the hint offers for a segment.
    enum SkipAction: Equatable {
        /// Seek past the segment and keep playing what follows.
        case skip(SkipTimecode)
        /// The ending runs into the end of the file: play the next episode instead.
        case nextEpisode
    }

    /// The hint on screen right now, or `nil` when no button should exist.
    ///
    /// One hint at a time: it appears when the playhead enters a segment and stays for ``hintLifetime`` unless
    /// the viewer presses it. Nothing brings it back for the same segment — not a seek, not a re-poll.
    private(set) var hint: SkipAction?

    /// Settings read once when playback starts.
    ///
    /// Changing them in another tab while the player is open is deliberately out of scope: the player would
    /// have to re-evaluate a segment it has already passed.
    @ObservationIgnored private let settings: PlaybackSettings

    /// How long a hint lives before it disappears on its own.
    @ObservationIgnored private let hintLifetime: Duration

    /// Segment whose hint already had its turn (pressed, expired, or auto-skipped).
    @ObservationIgnored private var handledSegmentKey: String?

    /// Task that hides the current hint when its lifetime runs out.
    @ObservationIgnored private var hintExpiryTask: Task<Void, Never>?

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

    init(
        request: PlaybackRequest,
        progressStore: PlaybackProgressStoring = PlaybackProgressStore(),
        settings: PlaybackSettings? = nil
    ) {
        self.request = request
        self.progressStore = progressStore
        // The settings are read once, when the session is created; the caller passes what it loaded.
        self.settings = settings ?? PlaybackSettings.defaults
        hintLifetime = PlayerTestOverrides.hintLifetime() ?? Self.productionHintLifetime
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
        updateSkip(for: playhead.seconds)
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
            updateSkip(for: startAt)
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
        hintExpiryTask?.cancel()
        hintExpiryTask = nil
        hint = nil
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

    /// Acts on the hint: seeks past the segment, or hands over to the next episode.
    func performHintAction() {
        guard let hint else { return }
        handledSegmentKey = activeSkip.map(Self.key(for:))
        switch hint {
        case let .skip(skip):
            seekPast(skip)
            activeSkip = nil
            Self.logger.info("Skipped \(String(describing: skip.kind), privacy: .public) segment")
        case .nextEpisode:
            Self.logger.info("Next episode requested from the hint")
            onNextEpisode?()
        }
        hideHint()
    }

    /// Seeks to the end of `segment` and keeps playing.
    private func seekPast(_ segment: SkipTimecode) {
        player.seek(
            to: CMTime(seconds: segment.end, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player.play()
    }

    /// Called by the screen when the hint's action is "next episode".
    @ObservationIgnored var onNextEpisode: (@MainActor () -> Void)?

    // The hint is never hidden by focus or by presses.
    //
    // An earlier build hid it while the viewer was in the system controls, using focus as the signal. It
    // looked reasonable and behaved terribly: the moment the viewer pressed Right to reach «Смотреть», focus
    // left the overlay for a frame, the hint disappeared and the button they were aiming at vanished. A
    // control that hides while you reach for it is worse than one that overlaps. The hint now stays for as
    // long as the playhead is inside the segment, and the layout keeps it clear of the transport bar.

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

    /// Applies the behaviour table to whatever segment the playhead is inside.
    ///
    /// The table lives here, once: an opening with the setting on is skipped silently; otherwise the hint
    /// appears for ``hintLifetime``; an ending with the setting on is skipped and *then* offers the next
    /// episode; without the setting the Kit's `EndingOfferResolver` decides which action to offer.
    private func updateSkip(for playhead: Double) {
        let skip = TimecodeResolver.activeSkip(for: timecodes, playhead: playhead)
        activeSkip = skip
        guard let skip else {
            hideHint()
            return
        }
        let key = Self.key(for: skip)
        guard key != handledSegmentKey else {
            hideHint()
            return
        }
        switch skip.kind {
        case .opening:
            if settings.skipsOpenings {
                handledSegmentKey = key
                seekPast(skip)
                activeSkip = nil
                hideHint()
                Self.logger.info("Auto-skipped the opening")
                return
            }
            show(.skip(skip))
        case .ending:
            let offer = EndingOfferResolver.offer(
                ending: skip,
                duration: request.episode.duration,
                hasNextEpisode: request.nextEpisode != nil
            )
            if settings.skipsEndings {
                handledSegmentKey = key
                seekPast(skip)
                activeSkip = nil
                if request.nextEpisode != nil {
                    // The credits stop the picture; what the viewer wants next is the following episode.
                    show(.nextEpisode)
                    Self.logger.info("Auto-skipped the ending, offering the next episode")
                } else {
                    hideHint()
                    Self.logger.info("Auto-skipped the ending without a next episode")
                }
                return
            }
            show(offer == .nextEpisode ? .nextEpisode : .skip(skip))
        }
    }

    /// Shows a hint and starts its lifetime.
    ///
    /// Idempotent: the playhead is polled twice a second, and re-arming on every poll would keep the hint
    /// alive for as long as the segment lasts.
    private func show(_ action: SkipAction) {
        if hint == action, hintExpiryTask != nil {
            return
        }
        hint = action
        hintExpiryTask?.cancel()
        let lifetime = hintLifetime
        let key = activeSkip.map(Self.key(for:))
        hintExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self, hint != nil else { return }
            // Expired without a press: the offer does not come back for this segment.
            handledSegmentKey = key
            hideHint()
            Self.logger.info("Hint expired without a press")
        }
    }

    private func hideHint() {
        hintExpiryTask?.cancel()
        hintExpiryTask = nil
        hint = nil
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
