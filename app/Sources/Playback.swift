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
/// It also drives the level meter, because it is the object that owns the
/// player, the rate KVO and both teardown doors: a metering composition build
/// (the only one in the app) hangs a `LevelMeterSink` on every audio track's
/// tap, and a 30 Hz run-loop timer — armed and disarmed by the rate KVO —
/// reads them, multiplies by the plan's envelope and publishes one reading to
/// `LevelMeter.shared`. See `LevelMeter.swift` for why the meter is computed
/// from the DSP tap rather than observed from a second one.
/// The meter's read and its two switches live in `Playback+Meter.swift`.
/// `previewComposition` lives in `Playback+PreviewQuality.swift`, `stepFrames` and the main
/// hop `onMain` in `+Step`, `seekAfterRebuild` in `+Scope`.
///
/// Road map 2's phase 8 hung two more things off the player, and both are here
/// because both are about the PLAYER rather than about the document: View ▸
/// Preview Quality, which scales the render size of the player's composition
/// alone (a copy of the builder's configuration, so the shared builder and
/// therefore the export path are untouched), and `makePreviewLayer()`, the one
/// door through which a second `AVPlayerLayer` is made — which is what lets
/// `player` stay private.
///
/// AppKit-facing and main-thread only. The one GCD seam is the rebuild queue
/// (app/CLAUDE.md); the 80 ms live debounce and the meter's read are run-loop
/// `Timer`s, not dispatch sources, so they cancel deterministically.
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
    /// timecode field both follow this. It carries a seek someone ASKED for
    /// (`seek(to:)`; a scope change's `seekAfterRebuild(to:)`, heard once where
    /// it lands) and time while PLAYING, and never the jumps of this
    /// object's own RESTORE seeks — a rebuild's item swap and re-land, the
    /// paused refresh's round trip — which the observer reports too: a
    /// restore is silent while it runs and is heard once, when it lands, only
    /// if it rests somewhere other than the tick last carried (parked at the
    /// end, a timeline shortened under the playhead). While PAUSED it carries
    /// only the tick the player is at or seeking to, never one it carried
    /// last: a late callback for a superseded seek or a swapped-out item is
    /// dropped, and every seek's landing is heard once if it rests off the
    /// last report (#204, #209). `report(_:)` is its one caller.
    var onTimeChanged: ((Ticks) -> Void)?
    /// Transport rate, including the rate AVFoundation sets itself when an
    /// item ends or stalls, which is why this is KVO and not a wrapper.
    var onRateChanged: ((Float) -> Void)?
    /// A rebuild that failed. Rare (a corrupt file mid-edit) and never fatal:
    /// the previous item keeps playing, except under a held scope change,
    /// whose item is dropped (#185).
    var onError: ((any Error) -> Void)?
    /// The probe's seam (`scope_playhead_probe.py`), nil in the app: handed the block a rebuild
    /// would give `DispatchQueue.main.async`, its holder runs it on main, once — with `nil` for
    /// the build's own result, or an error `finishRebuild` receives as the build's failure.
    var rebuildHop: ((@escaping ((any Error)?) -> Void) -> Void)?

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

    private(set) var built: BuiltComposition?
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
    /// The level meter's 30 Hz read. Nil whenever the transport is stopped —
    /// the rate KVO arms and disarms it — so an idle editor pays nothing for
    /// having a meter, exactly as it pays nothing for the periodic time
    /// observer AVFoundation stops delivering.
    var meterTimer: Timer?

    private var canvasSize = CGSize(width: 1920, height: 1080)
    /// View ▸ Preview Quality (road map 2's phase 8a). Persisted, so it is read
    /// here rather than pushed in by the editor: this object owns the player,
    /// and the setting is a fact about the player and not about the document.
    /// `EditorViewController+PreviewQuality.swift` holds the enum, the aspect
    /// rule and the menu.
    private(set) var previewQuality = PreviewQuality.stored()
    /// The seek state is internal only so `Playback+Scope.swift` can write it; nothing else does.
    var isSeeking = false
    var pendingSeek: Ticks?
    /// A paused refresh asked for mid-seek: run when the seek lands, not dropped.
    private var refreshWanted = false
    /// True from a restore's first line until its last seek lands.
    var restoring = false
    /// True from `startRebuild`'s dispatch until that generation lands or is discarded.
    var rebuilding = false
    /// True from `seekAfterRebuild` until the rebuild it waits for lands, fails or is discarded.
    var holding = false
    /// The last tick `onTimeChanged` carried.
    private var reported: Ticks?
    /// Bumped by every `player.seek`; a completion for an older serial is
    /// ignored, so one the item swap cancelled cannot end a newer seek.
    var seekSerial = 0
    var lastKnownTime: Ticks = 0
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
            self.onMain {
                // The meter is gated HERE and not on the periodic time
                // observer, which fires only while time is moving: a meter
                // driven by that would freeze at its last lit value the moment
                // playback stopped instead of falling to silence. The rate KVO
                // is the only thing that reliably learns the transport
                // stopped, including when AVFoundation stops it itself at the
                // end of an item or on a stall.
                if rate == 0 { self.stopMetering() } else { self.startMetering() }
                self.onRateChanged?(rate)
            }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("Playback does not support NSCoder")
    }

    deinit {
        if let timeObserver = timeObserver { player.removeTimeObserver(timeObserver) }
        rateObservation?.invalidate()
        debounceTimer?.invalidate()
        // Both teardown doors have to close the meter, or a window that went
        // away leaves the shared model lit at whatever it last read.
        // `ObjectIdentifier(self)` rather than `self`: nothing may retain — or
        // resurrect — an object that is already deinitialising.
        meterTimer?.invalidate()
        LevelMeter.shared.publish(.silent, from: ObjectIdentifier(self))
    }

    /// Stops everything and drops the item. `ProjectDocument` calls this when
    /// the window closes; releasing the `RecipeSource` key is the document's
    /// job, not this object's.
    func invalidate() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        pending = nil
        refreshWanted = false
        restoring = false
        rebuilding = false
        holding = false
        stopMetering()
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
    /// to that rule. Pan, the mono fold, the compressor and noise reduction
    /// are the only clip properties the compositor cannot express, so unlike
    /// every other property they are not picked up by re-reading
    /// `RecipeSource`: they are frozen into the composition's taps when it is
    /// built (`AudioTap.swift`).
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
            generation += 1  // …and one in flight is discarded (#130).
            rebuilding = false
            if holding {
                holding = false
                isSeeking = false
                startSeek(to: lastKnownTime)
            }
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

    /// Forces one composed frame while paused, for a recipe that changed
    /// under an item that did not (a property-only edit, spec §7.6).
    ///
    /// The standard trick, a zero-tolerance seek to the time the player is
    /// already at, is a NO-OP on macOS 26.5.1 (measured by
    /// `tools/proof/preview_refresh_probe.py`: the completion fires, no
    /// composition request is issued; re-assigning `videoComposition` and
    /// `AVPlayerItem.seek` are the same no-op). Only a seek to a DIFFERENT
    /// time composes, so this steps one tick off the playhead — inside the
    /// same frame, so the picture between the two seeks is the picture — with
    /// the return queued as `pendingSeek`, and lands back on the playhead's
    /// own tick with the new recipe drawn. Parked AT the end, as a transport
    /// that played through is, it rests on the last frame's final tick
    /// instead: the end tick composes nothing (every seek to it, tolerant or
    /// not, displays black — measured), so a return there would blank it.
    ///
    /// Both seeks are a RESTORE, not a playhead move: `onTimeChanged` hears
    /// neither jump, and hears the landing only when it differs from the tick
    /// last reported — which the end branch's `end - 1` does, once.
    func refreshPausedFrame() {
        refreshWanted = false
        guard player.rate == 0, player.currentItem != nil else { return }
        if isSeeking {
            refreshWanted = true
            return
        }
        let here = currentTime
        let end = built.map { CompositionBuilder.ticks($0.composition.duration) } ?? 0
        if here >= end {
            if end >= 1 {
                restoring = true
                startSeek(to: end - 1)
            }
            return
        }
        let step = here + 1 < end ? here + 1 : here - 1
        guard step >= 0 else { return }
        restoring = true
        startSeek(to: step)
        startSeek(to: here)
    }

    // MARK: - Preview quality and the second layer (road map 2's phase 8)

    /// View ▸ Preview Quality ▸ — Full, Half or Quarter of the canvas, for the
    /// PLAYER's composition alone.
    ///
    /// The setting has to survive two different moments, which is why it is
    /// stored as well as applied: with an item on the player it is a
    /// re-assignment (`AVPlayerItem.videoComposition` is a COPY property, so
    /// nothing done to the retained composition could reach the live item),
    /// and with no item — an empty timeline, or
    /// a rebuild still on the queue — there is nothing to re-assign and
    /// `finishRebuild` applies it to the item it is about to install. Both go
    /// through `previewComposition`, so the two paths cannot drift.
    ///
    /// Not routed through `update(project:urls:isLive:)`, deliberately: that
    /// function short-circuits on the plan JSON and the audio DSP, neither of
    /// which a quality change touches, and teaching it a third term would make
    /// every property edit compare one more thing for a setting that changes
    /// once in a session. Not `invalidate()` either — the editor's forced
    /// rebuild path pauses the transport and blanks the preview, which is a
    /// heavy price for what is one property assignment.
    func setPreviewQuality(_ quality: PreviewQuality) {
        guard quality != previewQuality else { return }
        previewQuality = quality
        quality.store()
        guard let item = player.currentItem, let built = built else { return }
        item.videoComposition = Self.previewComposition(built, quality: quality)
        // A paused preview would otherwise keep the frame it has until the
        // next seek: the item's composition changed, but nothing asked it for
        // a picture. The same trick a property-only edit uses.
        refreshPausedFrame()
    }

    /// A second `AVPlayerLayer` on this document's player, for the preview
    /// window (`PreviewWindowController.swift`).
    ///
    /// The factory exists so `player` can stay `private`: one place in the app
    /// knows a second layer on one player is legal, and it is the object that
    /// owns the player. The archived AVFoundation Programming Guide says it is
    /// NOT — "only the most recently created such layer will display any video
    /// content onscreen" — and that is measured false on macOS 26.5.1;
    /// `PreviewWindowController`'s doc carries the measurement, because that is
    /// where somebody would go to "fix" this back into one moved layer.
    func makePreviewLayer() -> AVPlayerLayer {
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        return layer
    }

    // MARK: - Rebuilding

    private func startRebuild() {
        guard let request = pending else { return }
        pending = nil
        canvasSize = request.plan.renderSizeCG

        // Only an EMPTY timeline (duration 0) drops the item: the preview shows
        // the layer's background and the transport refuses. A timeline of only
        // graphics, text, shapes or images has no plan track, and the builder's
        // placeholder gives its item one to tick against (road map 10 §10.8).
        guard request.plan.duration > 0 else {
            let held = holding
            generation += 1
            rebuilding = false
            holding = false
            isSeeking = false
            built = nil
            builtPlanJSON = request.planJSON
            builtAudioDSP = request.audioDSP
            player.replaceCurrentItem(with: nil)
            if held { endHoldWithoutItem() }
            return
        }

        generation += 1
        let generation = self.generation
        let key = recipeKey
        let plan = request.plan
        let planJSON = request.planJSON
        let urls = request.urls
        let audioDSP = request.audioDSP
        let hop = rebuildHop
        rebuilding = true
        rebuildQueue.async { [weak self] in
            let result = Result {
                // The ONE metering build in the app. An export and a rendered
                // frame build the audio path they always built; the meter has
                // no consumer there and a tap on a track that had none would
                // put an unmeasured object in the write path.
                try CompositionBuilder.build(
                    plan: plan, planJSON: planJSON, urls: urls, recipeKey: key, metering: true)
            }
            let finish: ((any Error)?) -> Void = { [weak self] fault in
                let outcome =
                    fault.map { Result<BuiltComposition, any Error>.failure($0) } ?? result
                self?.finishRebuild(outcome, generation: generation, audioDSP: audioDSP)
            }
            if let hop = hop { hop(finish) } else { DispatchQueue.main.async { finish(nil) } }
        }
    }

    private func finishRebuild(
        _ result: Result<BuiltComposition, any Error>, generation: Int,
        audioDSP: AudioDSPParameters
    ) {
        // A newer rebuild started while this one was on the queue: its result
        // is the current one, and this item would be a step backwards.
        guard generation == self.generation else { return }
        rebuilding = false
        switch result {
        case .failure(let error):
            // A held scope change drops the outgoing item rather than keep it (#185).
            if holding {
                player.replaceCurrentItem(with: nil)
                built = nil
                builtPlanJSON = nil
                builtAudioDSP = .empty
                endHoldWithoutItem()
            }
            onError?(error)
        case .success(let composition):
            holding = false
            let time = currentTime
            let rate = player.rate
            let item = AVPlayerItem(asset: composition.composition)
            // Through `previewComposition`, or a structural rebuild would put
            // the preview silently back to Full: the item is new, and the
            // quality lives on this object rather than in the plan.
            item.videoComposition = Self.previewComposition(composition, quality: previewQuality)
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
            seekSerial += 1
            pendingSeek = nil
            refreshWanted = false
            // Land on the same frame with the same transport state: an edit
            // mid-playback must not jump the playhead — nor report the new
            // item's 0 on the way (a restore; see `onTimeChanged`).
            restoring = true
            player.replaceCurrentItem(with: item)
            startSeek(to: time)
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

    /// THE ASKED DOOR: a seek someone wants, so its jump is reported as a
    /// playhead move. This object's own restores go through `startSeek`. Asked
    /// while a restore is seeking, it queues silently and is heard once where
    /// it lands (#130).
    func seek(to t: Ticks) {
        if !isSeeking { restoring = false }
        startSeek(to: t)
    }

    /// One in-flight seek at a time, intermediates dropped (§7.6): a scrub
    /// generates far more positions than the decoder can serve, and queueing
    /// them all makes the preview lag seconds behind the pointer.
    func startSeek(to t: Ticks) {
        let clamped = max(0, t)
        lastKnownTime = clamped
        guard player.currentItem != nil else {
            report(clamped)
            return
        }
        guard !isSeeking else {
            pendingSeek = clamped
            return
        }
        isSeeking = true
        seekSerial += 1
        let serial = seekSerial
        player.seek(
            to: CompositionBuilder.time(clamped), toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] _ in
            guard let self = self else { return }
            self.onMain {
                guard serial == self.seekSerial else { return }
                self.seekFinished()
            }
        }
    }

    /// One seek has landed: take the newest position that arrived while it
    /// was in flight, if any, dropping the rest; else end it — a restore or an
    /// asked seek alike — heard once only if it rests off the tick last
    /// reported (the observer may have carried it already); then any paused
    /// refresh waiting.
    private func seekFinished() {
        isSeeking = false
        if let next = pendingSeek {
            pendingSeek = nil
            startSeek(to: next)
            return
        }
        restoring = false
        let rest = currentTime
        if rest != reported { report(rest) }
        if refreshWanted { refreshPausedFrame() }
    }

    /// The ONE caller of `onTimeChanged`.
    private func report(_ t: Ticks) {
        reported = t
        onTimeChanged?(t)
    }

    // MARK: - Observers

    /// The periodic observer. While playing every tick is heard. While paused
    /// a tick is heard only when it is where the player is or is seeking to
    /// (`currentTime`) and differs from the last report: AVFoundation can
    /// deliver a callback late, for a seek since superseded or an item since
    /// swapped out, and that one is dropped (#204, #209).
    private func timeAdvanced(_ time: CMTime) {
        if restoring { return }
        let ticks = max(0, CompositionBuilder.ticks(time))
        if player.rate == 0, ticks != currentTime || ticks == reported { return }
        if !isSeeking { lastKnownTime = ticks }
        report(ticks)
        guard let loop = loopRange, player.rate != 0, loop.duration > 0,
            ticks >= loop.start + loop.duration
        else { return }
        seek(to: loop.start)
    }
}
