import AppKit

/// The output level meter in the timeline bar (road map 2, phase 5b): the one
/// view of `LevelMeter.shared` — and, since road map 3's recorder panel, of
/// any other `LevelMeter` handed to `init(meter:)`. The default is `.shared`,
/// so `TimelineBar`'s `LevelMeterView()` and every chrome render are byte for
/// byte what they were; the panel binds one to `ScreenRecorder.shared.meter`,
/// because a microphone published to `.shared` would light the timeline bar's
/// meter with the microphone (`ScreenRecorder`'s doc).
///
/// **The measurement is the model's, the ballistics are the view's.** What
/// arrives is a `LevelMeterReading` — per channel peak and RMS as linear
/// magnitude, already multiplied by the plan's envelope. Peak hold, the fall
/// and the clip dwell are display behaviour and live here, which is what lets
/// the phase's proof assert on the number without photographing a window.
/// `LevelMeter.swift`'s header argues the rest, including why the meter reads
/// the DSP tap that already exists instead of the second PostEffects tap the
/// road map asked for (there is one `audioTapProcessor` per input parameters
/// object, so that tap cannot be built).
///
/// **It subscribes itself, so nothing in the frozen files changes.** The model
/// is process-wide and `addObserver` hands back a token whose lifetime is the
/// subscription, so this view needs no handle kept for it in `TimelineView`,
/// no fan-out line in `EditorViewController` and no `setLevels` to call —
/// phase 5b touches neither frozen file.
///
/// **Where it sits, and why it is not beside the tracks it sums.** The bar
/// spans the whole window — `timelineContainer` is the bottom arranged subview
/// of `mainSplit`, pinned root leading→trailing — so its right end is under
/// the 304 pt inspector column, nowhere near the lanes. That is deliberate and
/// is not a bug to fix by moving the meter over the tracks: the meter is the
/// MIX, not a track, and the homes that would put it nearer the audio all
/// reopen a settled decision (the window toolbar has one job; a track header
/// at S has no 12 pt to give and repaints the whole column when anything in it
/// changes; the inspector is per-clip; a status bar is refused outright by the
/// design handoff).
///
/// **It goes in the flexible gap immediately left of the zoom cluster, and it
/// carries no divider.** `TimelineBar.build` states that arithmetic where the
/// row is assembled. What it means here is that the meter must survive being
/// starved: it has hugging AND compression resistance at priority 1, a
/// `lessThanOrEqualTo` cap so it cannot become a progress bar on a wide
/// window, and a `guard bounds.width` that lets it VANISH rather than draw a
/// scale too small to read — `TimelineSelectionBlock.draw`'s own
/// `guard textWidth > 8` precedent. Measured: at the 900 pt minimum window the
/// whole chrome renders BYTE-IDENTICALLY to the build before this phase, and
/// at 1080 and 1440 the only pixels that change are the meter's own 120 × 12.
///
/// **One resting appearance, always drawn.** The offscreen chrome harness has
/// no player, so every chrome render photographs this view at rest, and the
/// harness writes a PNG only when two consecutive captures are byte-identical.
/// So there is no free-running animation: the 30 Hz tick starts only when a
/// non-silent reading arrives and INVALIDATES ITSELF once the model has gone
/// silent and every bar has fallen to the floor —
/// `TimelineView.flashRefusal`'s shape, the project's one idiom for a bounded
/// repeating tick. Offscreen the model is silent, so no timer ever starts and
/// the view is static from its first draw.
final class LevelMeterView: NSView {
    // MARK: - Metrics

    /// The size the bar's stack view asks for. 120 pt reads a −60…0 dB scale
    /// at about 2 pt per dB; 12 pt is two 5 pt channel rows and the gap
    /// between them, well inside the 30 pt the other bar controls take.
    static let intrinsicWidth: CGFloat = 120
    static let intrinsicHeight: CGFloat = 12
    /// The cap on what the meter absorbs from the row's slack. Without it a
    /// wide window could hand the meter several hundred points, which reads as
    /// a progress bar rather than as a level. In practice the row's existing
    /// spacer wins the slack and the meter sits at its intrinsic width at
    /// every window size above the minimum; the cap is the guarantee, not the
    /// mechanism.
    static let maximumWidth: CGFloat = 160
    /// Below this the meter draws NOTHING rather than a scale nobody can read.
    private static let minimumWidth: CGFloat = 40

    private static let channelGap: CGFloat = 2
    /// The clip cell at the right end of each channel row: always drawn, lit
    /// only on an over. Separating it from the scale is what keeps the resting
    /// state legible as a meter rather than as an empty pill.
    private static let clipCell: CGFloat = 3
    private static let clipGap: CGFloat = 2

    // MARK: - Ballistics

    /// The bottom of the SCALE — not `LevelMeterMath.floorDB`, which is −120
    /// and exists to keep a logarithm finite. Linear in dB from here to
    /// 0 dBFS: a mapping a reader can predict, at the cost of spending a third
    /// of the width on the quietest 20 dB.
    private static let scaleFloorDB: Float = -60
    /// Instant attack, 24 dB/s fall — near IEC's peak-programme fallback, fast
    /// enough to track a cut and slow enough to read at 30 Hz.
    private static let fallDBPerSecond: Float = 24
    /// The hold mark dwells, then falls at half the bar's rate.
    private static let holdFallDBPerSecond: Float = 12
    private static let holdSeconds: TimeInterval = 1.2
    /// How long an over stays lit — long enough to catch out of the corner of
    /// an eye while playback runs on.
    private static let clipSeconds: TimeInterval = 2
    private static let tickInterval: TimeInterval = 1.0 / 30

    /// One channel's animated state, all three levels in dBFS.
    private struct Bar {
        var rms: Float
        var peak: Float
        var hold: Float
        var holdUntil: Date
        var clipUntil: Date

        static let rest = Bar(
            rms: LevelMeterView.scaleFloorDB, peak: LevelMeterView.scaleFloorDB,
            hold: LevelMeterView.scaleFloorDB, holdUntil: .distantPast,
            clipUntil: .distantPast)

        var isResting: Bool {
            hold <= LevelMeterView.scaleFloorDB && Date() >= clipUntil
        }
    }

    /// Left then right, always both: `LevelMeterReading` is two channels by
    /// construction (a mono track is widened downstream of the tap and a 5.1
    /// one is reported by its first two), so the meter's SHAPE never changes
    /// and the resting appearance is simply both bars at the floor.
    private var bars: [Bar] = [.rest, .rest]
    private var lastTick = Date.distantPast
    private var tick: Timer?
    private var observation: LevelMeterObservation?
    /// The model this view draws — `.shared` unless the caller says otherwise.
    private let meter: LevelMeter

    // MARK: - Life cycle

    init(meter: LevelMeter = .shared) {
        self.meter = meter
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumWidth).isActive = true
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel("Output levels")
        // Dropping the token unsubscribes, so the meter's whole teardown is
        // this view's own lifetime and nothing has to remember to detach it.
        observation = meter.addObserver { [weak self] reading in
            self?.wake(reading)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LevelMeterView does not support NSCoder")
    }

    deinit {
        tick?.invalidate()
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.intrinsicWidth, height: Self.intrinsicHeight)
    }

    // MARK: - The tick

    /// A published reading only ever STARTS the clock; the clock then POLLS
    /// the model.
    ///
    /// That asymmetry is deliberate. `LevelMeter.publish` notifies observers
    /// only when the reading CHANGES, and a steady tone measured over
    /// identical buffers publishes the same four floats every time — so a
    /// meter that decayed between callbacks would fall to silence over exactly
    /// the material a level proof is written against. Polling `reading` on the
    /// tick reads what is true now, and the model's own silence — which
    /// `Playback` publishes when the rate drops to zero and again from its
    /// `deinit` — is what releases the meter.
    private func wake(_ reading: LevelMeterReading) {
        guard tick == nil, !reading.isSilent else { return }
        lastTick = Date()
        tick = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) {
            [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            self.advance(timer)
        }
    }

    /// One step of the ballistics, then one redraw.
    ///
    /// When the model has gone silent the bars fall to the floor and the timer
    /// invalidates itself, which is what leaves the meter — and the run loop —
    /// exactly as they were before playback started.
    private func advance(_ timer: Timer) {
        let now = Date()
        let elapsed = Float(min(max(now.timeIntervalSince(lastTick), 0), 0.5))
        lastTick = now
        let reading = meter.reading
        let releasing = reading.isSilent
        bars[0] = step(
            bars[0], peak: reading.peakLeft, rms: reading.rmsLeft,
            elapsed: elapsed, now: now, releasing: releasing)
        bars[1] = step(
            bars[1], peak: reading.peakRight, rms: reading.rmsRight,
            elapsed: elapsed, now: now, releasing: releasing)
        if releasing, bars.allSatisfy({ $0.isResting }) {
            timer.invalidate()
            tick = nil
            bars = [.rest, .rest]
        }
        needsDisplay = true
    }

    /// Instant attack, timed fall, and a hold that dwells before it follows.
    /// `hold` is never below `peak` and `peak` is never below `rms`, so the
    /// three marks can only ever be drawn left to right.
    ///
    /// `releasing` is the silent case, and it drops the hold's dwell and falls
    /// it at the bar's own rate. Without that an over would leave its mark
    /// sinking for six seconds after playback stopped, which both reads wrong
    /// (the meter is no longer measuring anything) and keeps the tick alive
    /// for six seconds to say so. With it the whole tail is bounded by the
    /// clip cell's two seconds and a fall from the top of the scale: the meter
    /// is back at rest, and the timer gone, inside about 2.6 s.
    private func step(
        _ bar: Bar, peak: Float, rms: Float, elapsed: Float, now: Date, releasing: Bool
    ) -> Bar {
        var next = bar
        let fall = Self.fallDBPerSecond * elapsed
        next.rms = max(Self.scaled(rms), max(bar.rms - fall, Self.scaleFloorDB))
        next.peak = max(Self.scaled(peak), max(bar.peak - fall, Self.scaleFloorDB))
        next.rms = min(next.rms, next.peak)
        if !releasing, next.peak >= next.hold {
            next.hold = next.peak
            next.holdUntil = now.addingTimeInterval(Self.holdSeconds)
        } else if releasing || now >= next.holdUntil {
            let rate = releasing ? Self.fallDBPerSecond : Self.holdFallDBPerSecond
            next.hold = max(next.peak, max(next.hold - rate * elapsed, Self.scaleFloorDB))
        }
        if peak >= 1 {
            next.clipUntil = now.addingTimeInterval(Self.clipSeconds)
        }
        return next
    }

    /// Linear magnitude to a level on THIS scale. The conversion itself is the
    /// model's — one implementation of dBFS in the phase, not two — and this
    /// only lifts its −120 floor to the bottom of the drawn scale.
    private static func scaled(_ magnitude: Float) -> Float {
        max(scaleFloorDB, LevelMeterMath.decibels(magnitude))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width >= Self.minimumWidth else { return }
        let scaleWidth = bounds.width - Self.clipCell - Self.clipGap
        guard scaleWidth > 0 else { return }

        let now = Date()
        let rows = CGFloat(bars.count)
        let gaps = Self.channelGap * (rows - 1)
        let rowHeight = max(1, ((bounds.height - gaps) / rows).rounded(.down))
        let top = ((bounds.height - (rowHeight * rows + gaps)) / 2).rounded()
        let radius = min(2, rowHeight / 2)

        for (index, bar) in bars.enumerated() {
            let y = top + CGFloat(index) * (rowHeight + Self.channelGap)

            let trough = NSRect(x: 0, y: y, width: scaleWidth, height: rowHeight)
            DS.meterTrough.setFill()
            NSBezierPath(roundedRect: trough, xRadius: radius, yRadius: radius).fill()

            let cell = NSRect(
                x: bounds.width - Self.clipCell, y: y,
                width: Self.clipCell, height: rowHeight)
            (now < bar.clipUntil ? DS.meterClip : DS.meterTrough).setFill()
            NSBezierPath(roundedRect: cell, xRadius: radius, yRadius: radius).fill()

            // The instantaneous peak washes the trough behind the RMS bar, so
            // one glance gives both the body of the sound and its transients.
            let peakWidth = Self.width(forDB: bar.peak, in: scaleWidth)
            if peakWidth > 0 {
                DS.meterFill.withAlphaComponent(0.35).setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 0, y: y, width: peakWidth, height: rowHeight),
                    xRadius: radius, yRadius: radius
                ).fill()
            }
            let rmsWidth = Self.width(forDB: bar.rms, in: scaleWidth)
            if rmsWidth > 0 {
                DS.meterFill.setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 0, y: y, width: rmsWidth, height: rowHeight),
                    xRadius: radius, yRadius: radius
                ).fill()
            }
            // The hold mark. It is never behind the RMS bar (`step` keeps the
            // three ordered), so it always reads against the trough or against
            // the wash and needs no fourth ink of its own.
            let holdWidth = Self.width(forDB: bar.hold, in: scaleWidth)
            if holdWidth > 0 {
                DS.meterFill.setFill()
                NSRect(
                    x: min(holdWidth, scaleWidth) - 2, y: y, width: 2, height: rowHeight
                ).fill()
            }
        }
    }

    /// A level in dBFS to a width on the scale, linear in dB from the floor to
    /// 0 dBFS. Anything above 0 pins at full — saying an over is the clip
    /// cell's job, not the bar's.
    private static func width(forDB decibels: Float, in scale: CGFloat) -> CGFloat {
        let fraction = (min(decibels, 0) - scaleFloorDB) / -scaleFloorDB
        guard fraction > 0 else { return 0 }
        return (CGFloat(min(fraction, 1)) * scale).rounded()
    }
}
