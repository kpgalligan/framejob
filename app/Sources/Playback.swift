import AVFoundation
import AppKit

/// The preview transport: one `AVPlayer` over the composition the core's plan
/// describes, and the rebuild-versus-refresh decision that keeps property
/// edits instant (spec §7.6).
///
/// The decision is the whole design. After every edit `ProjectDocument` hands
/// the new project here; this publishes it to `RecipeSource` (which the
/// compositor reads on every frame) and then compares the new plan JSON to the
/// one the current item was built from — as STRINGS, never as decoded plans
/// (§11). Equal means nothing structural moved and the composition is still
/// correct: no rebuild, just one forced frame. Different means the timeline's
/// shape changed and only a new `AVPlayerItem` can express it.
///
/// AppKit-facing and main-thread only. The one GCD seam is the rebuild queue
/// (app/CLAUDE.md); the 80 ms live debounce is a run-loop `Timer`, not a
/// dispatch source, so it cancels deterministically.
final class Playback {

    /// How long a live gesture must be quiet before a structural rebuild is
    /// worth doing. Long enough that a drag across ten frames rebuilds once,
    /// short enough that the preview never feels detached (§7.6).
    static let liveRebuildDelay: TimeInterval = 0.08

    /// The layer `PreviewCanvasView` puts under its overlay (§11: an
    /// `AVPlayerLayer`, not a self-driven `MTKView`, so A/V sync and
    /// scrubbing come from the player).
    let playerLayer: AVPlayerLayer

    /// Playhead time, from the periodic observer — the timeline and the
    /// timecode field both follow this.
    var onTimeChanged: ((Ticks) -> Void)?
    /// Transport rate, including the rate AVFoundation sets itself when an
    /// item ends or stalls, which is why this is KVO and not a wrapper.
    var onRateChanged: ((Float) -> Void)?
    /// A rebuild that failed. Rare (a corrupt file mid-edit) and never fatal:
    /// the previous item keeps playing.
    var onError: ((any Error) -> Void)?

    /// The in/out range when one is set: playback wraps at its end (§4.4).
    var loopRange: (start: Ticks, duration: Ticks)?

    private let player = AVPlayer()
    /// This document's `RecipeSource` slot. Travels onto every instruction so
    /// the compositor reads this document's recipes and no other's.
    private let recipeKey: Int

    /// The documented rebuild seam: building a composition opens asset tracks,
    /// which touches the disk and must never block a gesture.
    private let rebuildQueue = DispatchQueue(
        label: "com.kgalligan.reelcut.rebuild", qos: .userInitiated)

    private var built: BuiltComposition?
    /// The plan the CURRENT item was built from; nil before the first build.
    private(set) var builtPlanJSON: String?
    /// The sample-level audio settings the CURRENT item's taps were built
    /// with. The second half of the rebuild test — see `update`.
    private var builtAudioDSP = AudioDSPParameters.empty
    private var pending: (
        plan: CompositionPlan, planJSON: String, urls: [UInt32: URL], audioDSP: AudioDSPParameters
    )?
    private var debounceTimer: Timer?
    /// Bumped per rebuild so a slow build that finishes after a newer one
    /// started is discarded instead of replacing a fresher item.
    private var generation = 0

    private var canvasSize = CGSize(width: 1920, height: 1080)
    private var isSeeking = false
    private var pendingSeek: Ticks?
    private var lastKnownTime: Ticks = 0
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?

    init(recipeKey: Int) {
        self.recipeKey = recipeKey
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        // The player must not resume at the end of an item: the playhead
        // stops there and the user decides what happens next.
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60), queue: .main
        ) { [weak self] time in
            self?.timeAdvanced(time)
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            let rate = player.rate
            self.onMain { self.onRateChanged?(rate) }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("Playback does not support NSCoder")
    }

    deinit {
        if let timeObserver = timeObserver { player.removeTimeObserver(timeObserver) }
        rateObservation?.invalidate()
        debounceTimer?.invalidate()
    }

    /// Stops everything and drops the item. `ProjectDocument` calls this when
    /// the window closes; releasing the `RecipeSource` key is the document's
    /// job, not this object's.
    func invalidate() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        pending = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        built = nil
        builtPlanJSON = nil
        builtAudioDSP = .empty
        // The audio-DSP mirror is this object's to release, unlike the
        // `RecipeSource` slot, which is the document's (it outlives the
        // window and an export may still be reading it).
        AudioDSPSource.shared.unpublish(recipeKey)
    }

    // MARK: - The update rule (§7.6)

    /// Takes the project after an edit and decides what the preview needs.
    ///
    /// 1. Publish the project to `RecipeSource` — the compositor reads it on
    ///    every frame, so this alone makes new property values render.
    /// 2. Same plan JSON: a PROPERTY-ONLY edit. No rebuild; if paused, force
    ///    one composed frame.
    /// 3. Different plan JSON: STRUCTURAL. Rebuild on the rebuild queue and
    ///    swap the item, keeping time and transport state. During a live
    ///    gesture (`isLive`) the rebuild is debounced by
    ///    `liveRebuildDelay`; the non-live update that ends the gesture
    ///    always rebuilds.
    ///
    /// **The audio DSP counts as structural too**, which is the one addition
    /// to that rule. Pan, the compressor and noise reduction are the only
    /// clip properties the compositor cannot express, so unlike every other
    /// property they are not picked up by re-reading `RecipeSource`: they are
    /// frozen into the composition's taps when it is built (`AudioTap.swift`).
    /// That is not a special case so much as the case volume is already in —
    /// volume reaches AVFoundation as the plan's ramps, so changing it has
    /// always rebuilt — and it costs one rebuild per parameter change,
    /// debounced during a drag like any other.
    ///
    /// Main thread only — it schedules a run-loop timer and touches AppKit's
    /// player.
    func update(project: ReelProject, urls: [UInt32: URL], isLive: Bool) {
        RecipeSource.shared.set(project, for: recipeKey)
        let audioDSP = AudioDSPParameters(snapshot: project.snapshot)
        AudioDSPSource.shared.publish(audioDSP, for: recipeKey)
        let planJSON = project.planJSON
        if planJSON == builtPlanJSON, audioDSP == builtAudioDSP {
            // Any rebuild still queued was for a plan this edit just undid.
            debounceTimer?.invalidate()
            debounceTimer = nil
            pending = nil
            if player.rate == 0 { refreshPausedFrame() }
            return
        }
        guard let plan = project.plan else { return }
        pending = (plan: plan, planJSON: planJSON, urls: urls, audioDSP: audioDSP)
        if isLive {
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(
                withTimeInterval: Playback.liveRebuildDelay, repeats: false
            ) { [weak self] _ in
                self?.debounceTimer = nil
                self?.startRebuild()
            }
        } else {
            debounceTimer?.invalidate()
            debounceTimer = nil
            startRebuild()
        }
    }

    /// Forces exactly one composed frame while paused: a zero-tolerance seek
    /// to the time the player is already at. That is the standard trick for
    /// redisplaying a paused `AVPlayer` — a seek flushes the composition
    /// pipeline (`cancelAllPendingVideoCompositionRequests`) and re-requests
    /// the frame, which now comes back drawn from the new recipe. Without it a
    /// property-only edit would not appear until the next play.
    func refreshPausedFrame() {
        guard player.rate == 0, player.currentItem != nil, !isSeeking else { return }
        seek(to: currentTime)
    }

    // MARK: - Rebuilding

    private func startRebuild() {
        guard let request = pending else { return }
        pending = nil
        canvasSize = request.plan.renderSizeCG

        // An empty timeline has no tracks to compose. An `AVPlayerItem` over a
        // composition with no tracks is not playable, so the item is dropped
        // instead — the preview shows the layer's background and the transport
        // refuses.
        guard !request.plan.videoTracks.isEmpty || !request.plan.audioTracks.isEmpty else {
            built = nil
            builtPlanJSON = request.planJSON
            builtAudioDSP = request.audioDSP
            player.replaceCurrentItem(with: nil)
            return
        }

        generation += 1
        let generation = self.generation
        let key = recipeKey
        let plan = request.plan
        let planJSON = request.planJSON
        let urls = request.urls
        let audioDSP = request.audioDSP
        rebuildQueue.async { [weak self] in
            let result = Result {
                try CompositionBuilder.build(
                    plan: plan, planJSON: planJSON, urls: urls, recipeKey: key)
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishRebuild(result, generation: generation, audioDSP: audioDSP)
            }
        }
    }

    private func finishRebuild(
        _ result: Result<BuiltComposition, any Error>, generation: Int,
        audioDSP: AudioDSPParameters
    ) {
        // A newer rebuild started while this one was on the queue: its result
        // is the current one, and this item would be a step backwards.
        guard generation == self.generation else { return }
        switch result {
        case .failure(let error):
            onError?(error)
        case .success(let composition):
            let time = currentTime
            let rate = player.rate
            let item = AVPlayerItem(asset: composition.composition)
            item.videoComposition = composition.videoComposition
            item.audioMix = composition.audioMix
            // Decoding above the canvas size is wasted work — the compositor
            // renders at the canvas size no matter what the source is (§7.6).
            item.preferredMaximumResolution = canvasSize
            // Makes a seek wait for the CUSTOM compositor's frame instead of
            // showing the nearest decoded one, which is what keeps scrubbing
            // WYSIWYG.
            item.seekingWaitsForVideoCompositionRendering = true
            built = composition
            builtPlanJSON = composition.planJSON
            builtAudioDSP = audioDSP
            isSeeking = false
            pendingSeek = nil
            player.replaceCurrentItem(with: item)
            // Land on the same frame with the same transport state: an edit
            // mid-playback must not jump the playhead.
            seek(to: time)
            if rate != 0 { player.rate = rate }
        }
    }

    // MARK: - Transport

    var isPlaying: Bool { player.rate != 0 }
    var rate: Float { player.rate }

    /// The playhead in ticks. While a seek is in flight the TARGET is
    /// returned, not the player's lagging time — otherwise a scrub would
    /// feed its own stale positions back into the next seek.
    var currentTime: Ticks {
        if isSeeking || player.currentItem == nil { return lastKnownTime }
        return max(0, CompositionBuilder.ticks(player.currentTime()))
    }

    func play() {
        guard player.currentItem != nil else {
            NSSound.beep()
            return
        }
        if let loop = loopRange, currentTime >= loop.start + loop.duration {
            seek(to: loop.start)
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func togglePlayPause() {
        if player.rate == 0 { play() } else { pause() }
    }

    /// JKL and the shuttle: negative rates play backwards, 0 pauses. A rate
    /// the item cannot serve is AVFoundation's business — it clamps and the
    /// KVO reports what actually happened.
    func setRate(_ rate: Float) {
        guard player.currentItem != nil else {
            NSSound.beep()
            return
        }
        player.rate = rate
    }

    /// One in-flight seek at a time, intermediates dropped (§7.6): a scrub
    /// generates far more positions than the decoder can serve, and queueing
    /// them all makes the preview lag seconds behind the pointer.
    func seek(to t: Ticks) {
        let clamped = max(0, t)
        lastKnownTime = clamped
        guard player.currentItem != nil else {
            onTimeChanged?(clamped)
            return
        }
        guard !isSeeking else {
            pendingSeek = clamped
            return
        }
        isSeeking = true
        player.seek(
            to: CompositionBuilder.time(clamped), toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self = self else { return }
            self.onMain { self.seekFinished() }
        }
    }

    /// One seek has landed: take the newest position that arrived while it
    /// was in flight, if any, and drop everything in between.
    private func seekFinished() {
        isSeeking = false
        guard let next = pendingSeek else { return }
        pendingSeek = nil
        seek(to: next)
    }

    /// Steps `n` frames (negative steps back) and pauses: stepping while
    /// playing means nothing, and the arrow keys are how a cut is placed
    /// exactly (§9).
    func stepFrames(_ n: Int, fps: Fps) {
        let step = fps.frameDuration
        guard step > 0, n != 0 else { return }
        pause()
        seek(to: max(0, currentTime + Ticks(n) * step))
    }

    // MARK: - Observers

    private func timeAdvanced(_ time: CMTime) {
        let ticks = max(0, CompositionBuilder.ticks(time))
        if !isSeeking { lastKnownTime = ticks }
        onTimeChanged?(ticks)
        guard let loop = loopRange, player.rate != 0, loop.duration > 0,
            ticks >= loop.start + loop.duration
        else { return }
        seek(to: loop.start)
    }

    /// AVFoundation calls KVO and seek completions on whichever thread it
    /// happens to be on. Everything here touches AppKit state, so hop when
    /// needed — `OperationQueue.main`, not a new dispatch seam.
    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            OperationQueue.main.addOperation(body)
        }
    }
}
