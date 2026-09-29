import Accelerate
import Foundation
import Synchronization

/// The level meter's MODEL: what the audio thread measured, how it crosses to
/// the main thread, and the arithmetic that turns per-track measurements into
/// the one reading a meter draws. No view, no AVFoundation, no AppKit.
///
/// **Why the meter reads the DSP tap instead of its own.** The road map asked
/// for "a second, read-only `MTAudioProcessingTap` per composition track
/// created with `kMTAudioProcessingTapCreationFlag_PostEffects`". There is no
/// such thing. `AVMutableAudioMixInputParameters` has exactly ONE
/// `audioTapProcessor`, and `MTAudioProcessingTap.h` says either the PreEffects
/// or the PostEffects flag must be set but not both — so a track already
/// carrying the DSP tap (`AudioTap.swift`, PreEffects, deliberately, so the
/// compressor sits ahead of the fader) cannot carry a second one, and moving
/// the DSP tap to PostEffects would change how every existing project with a
/// compressor sounds. So the meter reads the tap that already exists and
/// multiplies by the plan's envelope: the tap sees the samples BEFORE volume,
/// the fades and ducking, and the envelope at that tick is exactly what
/// `CompositionBuilder` hands AVFoundation as volume ramps. The displayed
/// number is therefore computed rather than observed, and it is exact rather
/// than approximate — the ramps are the same ones AVFoundation is applying.
/// `SilenceDetector` already established this as the app's rule ("a peak is
/// pre-fader, so the level you want is peak × envelope"). Do not "fix" this
/// back toward a second tap; it cannot be built.
///
/// **Why the publish is lock-free, when everything else in the app is an
/// `NSLock`.** `RecipeSource`, `AudioDSPSource`, `ReverseSource`,
/// `ExportWriter`'s progress — every cross-thread value in `app/Sources` is a
/// lock or a `DispatchQueue.main.async` hop. Neither may be used here.
/// `LevelMeterSink.publish` runs inside `MTAudioProcessingTap`'s process
/// callback, on AVPlayer's real-time render thread, where `AudioDSP.swift`'s
/// stated discipline holds: nothing takes a lock, nothing allocates. A lock
/// can block on a lower-priority thread that holds it (priority inversion) and
/// a `main.async` allocates, and both fail the same way — an occasional
/// glitch nobody can reproduce. So the sink is two 64-bit words written with
/// relaxed atomic stores and read the same way: wait-free, no allocation, no
/// ordering the render thread has to wait on. This is the app's first
/// `import Synchronization`, and it is a deliberate exception of the same
/// class as `async` being confined to `MediaImporter.swift`.
///
/// **The model publishes a RAW measurement; the VIEW owns the ballistics.**
/// Peak hold and decay are display behaviour, and keeping them out here is
/// what lets a proof assert on the number without photographing a window.
///
/// **The model is process-wide.** `LevelMeter.shared` is what a meter view
/// observes and what `Playback` publishes into, which is what keeps the meter
/// out of the frozen `TimelineView`/`EditorViewController` wiring entirely: a
/// view subscribes to it directly. With two documents open the meter follows
/// whichever transport published last — they share one output device, so
/// showing one of them is honest where showing neither is not — with one
/// rule that stops the obvious wrong: a SILENT publish from a transport that
/// is not the one currently lighting the meter is ignored, so stopping
/// playback in window B cannot blank window A's live meter.
///
/// The units, once: a `LevelMeterReading` is LINEAR magnitude, 1.0 being full
/// scale, because that is what the samples are and what multiplies by an
/// envelope. dBFS is a computed accessor, floored rather than allowed to reach
/// −∞.

// MARK: - What is measured

/// One measurement: peak and RMS magnitude for two channels, linear.
///
/// Two channels because the meter has two bars. A mono composition track is
/// prepared with one channel and widened downstream of the tap, so its one
/// channel is reported in both; a track with more than two (a 5.1 source) is
/// reported by its first two, which is what a two-bar meter can honestly say
/// about it.
struct LevelMeterReading: Equatable {
    var peakLeft: Float
    var peakRight: Float
    var rmsLeft: Float
    var rmsRight: Float

    init(peakLeft: Float = 0, peakRight: Float = 0, rmsLeft: Float = 0, rmsRight: Float = 0) {
        self.peakLeft = LevelMeterReading.sanitised(peakLeft)
        self.peakRight = LevelMeterReading.sanitised(peakRight)
        // RMS can never exceed peak in one buffer, and the two are read from
        // two separate atomic words that may be one buffer apart (see
        // `LevelMeterSink`), so the invariant is restored here rather than
        // left for the view to draw an RMS fill past the peak tick.
        self.rmsLeft = min(LevelMeterReading.sanitised(rmsLeft), self.peakLeft)
        self.rmsRight = min(LevelMeterReading.sanitised(rmsRight), self.peakRight)
    }

    /// A sample that is not a finite number poisons everything downstream —
    /// one NaN in a buffer makes the bar vanish and stay vanished — so it is
    /// answered as silence, at the one place every value passes through.
    private static func sanitised(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    static let silent = LevelMeterReading()

    var isSilent: Bool { peakLeft <= 0 && peakRight <= 0 }

    var peakLeftDB: Float { LevelMeterMath.decibels(peakLeft) }
    var peakRightDB: Float { LevelMeterMath.decibels(peakRight) }
    var rmsLeftDB: Float { LevelMeterMath.decibels(rmsLeft) }
    var rmsRightDB: Float { LevelMeterMath.decibels(rmsRight) }

    /// The loudest of the two channels' peaks, in dBFS — what a clip
    /// indication is decided on.
    var peakDB: Float { LevelMeterMath.decibels(max(peakLeft, peakRight)) }

    /// This track's contribution, scaled by the mix envelope over it (the
    /// volume, fades and ducking the tap ran ahead of).
    func scaled(by gain: Float) -> LevelMeterReading {
        guard gain.isFinite else { return .silent }
        guard gain != 1 else { return self }
        let g = max(0, gain)
        return LevelMeterReading(
            peakLeft: peakLeft * g, peakRight: peakRight * g,
            rmsLeft: rmsLeft * g, rmsRight: rmsRight * g)
    }

    /// Two tracks' readings as one.
    ///
    /// **Peaks add LINEARLY and RMS adds in POWER**, and the difference is not
    /// a nicety. A linear sum of peaks is the arithmetic upper bound on what
    /// the mix can reach — the honest thing for a meter whose job is to warn —
    /// while adding two RMS values linearly would claim +6 dB for two
    /// uncorrelated sources that actually sum to +3. With one audio track,
    /// which is most projects, both reduce to the track's own numbers and the
    /// distinction never arises.
    func adding(_ other: LevelMeterReading) -> LevelMeterReading {
        LevelMeterReading(
            peakLeft: peakLeft + other.peakLeft,
            peakRight: peakRight + other.peakRight,
            rmsLeft: (rmsLeft * rmsLeft + other.rmsLeft * other.rmsLeft).squareRoot(),
            rmsRight: (rmsRight * rmsRight + other.rmsRight * other.rmsRight).squareRoot())
    }
}

// MARK: - The arithmetic

/// The pure pieces: one channel's measurement, and magnitude → dBFS.
///
/// Separated out so a proof can measure a buffer it authored itself without a
/// player, a document or a window anywhere in the picture.
enum LevelMeterMath {
    /// Where the dB scale bottoms out. −120 dBFS is far under the least
    /// significant bit of any 16-bit material, so nothing real is clipped by
    /// it; it exists so that `log10(0)` never reaches a layout constraint as
    /// −∞ (which lays out as NaN, which AppKit reports as a broken constraint
    /// rather than as a silent meter).
    static let floorDB: Float = -120

    private static let floorLinear: Float = 1e-6  // 10^(-120/20)

    /// Peak and RMS of one channel's `frames` samples.
    ///
    /// `vDSP_maxmgv` and `vDSP_rmsqv` are two linear passes with no allocation
    /// and no state, which is what the render thread can afford: at 4096
    /// frames this is two orders of magnitude under one noise-reduction frame.
    static func measure(_ data: UnsafePointer<Float>, frames: Int) -> (peak: Float, rms: Float) {
        guard frames > 0 else { return (0, 0) }
        var peak: Float = 0
        var rms: Float = 0
        vDSP_maxmgv(data, 1, &peak, vDSP_Length(frames))
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(frames))
        return (peak.isFinite ? peak : 0, rms.isFinite ? rms : 0)
    }

    /// Linear magnitude → dBFS, floored at `floorDB`. 1.0 is 0 dBFS.
    static func decibels(_ magnitude: Float) -> Float {
        guard magnitude.isFinite, magnitude > floorLinear else { return floorDB }
        return 20 * log10f(magnitude)
    }
}

// MARK: - The crossing

/// One composition audio track's meter: written by the tap on the audio
/// thread, read by `Playback`'s timer on the main one.
///
/// **Two words, both relaxed.** Peak L and peak R live in one 64-bit word as
/// two `Float` bit patterns; RMS L and RMS R live in the other. One relaxed
/// store each per buffer, one relaxed load each per tick. Relaxed is enough
/// because there is nothing else to order against: the words carry no
/// pointers, publish no other state, and a reader that sees the previous
/// buffer's number instead of this one's is showing a meter 1/60 s stale,
/// which is invisible. The two words may be one buffer apart from each other
/// — `LevelMeterReading.init` restores `rms ≤ peak` for exactly that reason.
///
/// **One value per BUFFER, not per tick.** `prepare`'s `maxFrames` is about
/// 4096 frames — 85 ms — on the paths this app has measured, so the real
/// measurement rate is 12–20 Hz and the 30 Hz timer merely re-reads. That is
/// what a digital peak meter does; do not read the timer's interval as the
/// meter's resolution.
final class LevelMeterSink: @unchecked Sendable {
    private let peaks = Atomic<UInt64>(0)
    private let levels = Atomic<UInt64>(0)

    init() {}

    /// AUDIO THREAD. Measures one buffer of planar float channels and stores
    /// the result. Allocation-free, lock-free, and no read-modify-write: the
    /// buffer's own peak IS the value, and the hold and the decay belong to
    /// the view.
    ///
    /// `channels` is the same shape `AudioDSPChain.process` takes — the base
    /// pointer of each channel, `frames` samples each — so a proof can drive
    /// this with two plain allocations and no player.
    func measure(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int
    ) {
        guard frames > 0, count > 0 else { return }
        var left: (peak: Float, rms: Float) = (0, 0)
        if let data = channels[0] { left = LevelMeterMath.measure(data, frames: frames) }
        // A mono composition track is widened to stereo downstream of the tap,
        // so its single channel is what both bars are showing.
        var right = left
        if count >= 2, let data = channels[1] {
            right = LevelMeterMath.measure(data, frames: frames)
        }
        store(peakLeft: left.peak, peakRight: right.peak, rmsLeft: left.rms, rmsRight: right.rms)
    }

    /// AUDIO THREAD. The two stores, spelled once.
    func store(peakLeft: Float, peakRight: Float, rmsLeft: Float, rmsRight: Float) {
        levels.store(Self.pack(rmsLeft, rmsRight), ordering: .relaxed)
        // Peak last, so a reader that catches the pair mid-update sees an RMS
        // that belongs to an older, quieter buffer rather than a peak that
        // does — the direction that under-reports rather than over-reports.
        peaks.store(Self.pack(peakLeft, peakRight), ordering: .relaxed)
    }

    /// MAIN THREAD. The last buffer's measurement.
    func read() -> LevelMeterReading {
        let p = Self.unpack(peaks.load(ordering: .relaxed))
        let r = Self.unpack(levels.load(ordering: .relaxed))
        return LevelMeterReading(
            peakLeft: p.0, peakRight: p.1, rmsLeft: r.0, rmsRight: r.1)
    }

    /// Forgets the last buffer, so a resumed preview does not open on the peak
    /// it paused at. Two relaxed stores like any other, so it is safe from
    /// wherever it is called — the transport calls it on the main thread when
    /// playback stops, and the tap calls it from `prepare`/`unprepare` on
    /// whichever AVFoundation thread it is handed.
    func clear() {
        peaks.store(0, ordering: .relaxed)
        levels.store(0, ordering: .relaxed)
    }

    private static func pack(_ high: Float, _ low: Float) -> UInt64 {
        UInt64(high.bitPattern) << 32 | UInt64(low.bitPattern)
    }

    private static func unpack(_ word: UInt64) -> (Float, Float) {
        (Float(bitPattern: UInt32(truncatingIfNeeded: word >> 32)),
         Float(bitPattern: UInt32(truncatingIfNeeded: word)))
    }
}

/// One metered composition audio track: the sink its tap writes into, the
/// envelope that turns what the tap saw into what the mix hears, and the spans
/// over which the track plays anything at all.
///
/// The ramps and the spans are copied out of the plan when the composition is
/// built, beside the sink, because that is the one moment all three are known
/// — `Playback`'s timer must not go looking for a plan track by id thirty
/// times a second.
///
/// **A sink has no age** (#65). It holds the LAST buffer its tap measured, and
/// nothing replaces that buffer over an empty stretch of the composition track
/// — past a short clip's end, or while the other format family of a
/// mixed-format plan track plays — so a reading taken from the sinks alone
/// kept a finished clip's level lit. `sounding` is what says the buffer is
/// current: `mix` counts a track only while one of its OWN spans holds the
/// tick.
struct LevelMeterTrack {
    let id: Int
    /// The plan's envelope over this track's whole extent — volume, the fades,
    /// volume actions and ducking already folded in by `audio.rs`. Nil for a
    /// track the plan gave no ramps, which means unity (`audio.rs`'s meaning
    /// of an unmodified track).
    let ramps: [PlanRamp]?
    /// [start, start + duration) of every segment this composition track plays
    /// media over — its format family's segments whose source resolved,
    /// exactly what `CompositionBuilder.fill` inserts media for.
    let sounding: [Range<Ticks>]
    let sink: LevelMeterSink

    /// True while one of this track's own sounding spans holds `t`.
    func isSounding(at t: Ticks) -> Bool {
        sounding.contains { $0.contains(t) }
    }

    /// The meter's reading at a project tick: from silence, in array order,
    /// every track sounding at `t` adds its sink's last buffer scaled by the
    /// mix envelope over it. `Playback.meterReading()` answers this, and the
    /// offscreen harness calls it rather than a copy.
    static func mix(_ meters: [LevelMeterTrack], at t: Ticks) -> LevelMeterReading {
        var total = LevelMeterReading.silent
        for track in meters where track.isSounding(at: t) {
            let gain = Float(LevelMeterEnvelope.value(track.ramps, at: t))
            total = total.adding(track.sink.read().scaled(by: gain))
        }
        return total
    }
}

/// The mix envelope a metered track is under, at a project tick — the multiply
/// that turns what a PreEffects tap measured into what the mix hears.
///
/// **One line, and it must stay one.** Phase 5 shipped the search itself here,
/// as a second copy of `SilenceDetector`'s, with a comment saying it should not
/// stay one; the consolidation moved the arithmetic to `MediaPeaks.envelope`,
/// which is now the app's single spelling of the plan's piecewise-linear mix
/// rule and the same call the detector makes. Both are asking one question —
/// "what gain is the mix applying here", the rule `audio.rs` expresses as a
/// ZERO envelope for a mute and a solo — and the app has already paid once for
/// two disagreeing project-to-source conversions. This name survives as the
/// meter's own way of asking it; nothing about the numbers is decided here.
enum LevelMeterEnvelope {
    static func value(_ ramps: [PlanRamp]?, at t: Ticks) -> Double {
        MediaPeaks.envelope(ramps, at: t)
    }
}

// MARK: - The model

/// A subscription to `LevelMeter`. Holding it is what keeps the observation
/// alive; dropping it removes the observer, so a view that goes away takes its
/// callback with it and nothing has to remember to unsubscribe.
final class LevelMeterObservation {
    private let id: Int
    private weak var meter: LevelMeter?

    fileprivate init(id: Int, meter: LevelMeter) {
        self.id = id
        self.meter = meter
    }

    deinit { meter?.removeObserver(id) }
}

/// What is playing, right now, as a level — the one thing a meter view draws
/// and the one thing a proof asserts on.
///
/// MAIN THREAD ONLY, which is why there is no lock in it: `Playback`'s meter
/// timer is a run-loop timer on the main thread and every observer is a view.
/// The crossing from the audio thread happened in `LevelMeterSink`, one layer
/// down, and this side of it is ordinary main-thread state.
final class LevelMeter {
    /// The instance the app uses. A view observes this directly rather than
    /// being handed a meter through the frozen controller and view — see the
    /// file's header for why that is the design and not a shortcut.
    static let shared = LevelMeter()

    private(set) var reading: LevelMeterReading = .silent

    /// Which transport is lighting the meter, as an identity rather than a
    /// reference: a `Playback` publishes its final silence from `deinit`, and
    /// nothing here may retain (or resurrect) it.
    private var source: ObjectIdentifier?
    private var observers: [Int: (LevelMeterReading) -> Void] = [:]
    private var nextObserver = 1

    init() {}

    /// MAIN THREAD. Takes one measurement from one transport.
    ///
    /// A non-silent reading always wins and claims the meter. A silent one is
    /// accepted only from the transport that holds the claim (or when nothing
    /// does), which is what stops a second document's stop from blanking a
    /// meter the first document is still driving.
    func publish(_ reading: LevelMeterReading, from source: ObjectIdentifier) {
        if reading.isSilent {
            guard self.source == nil || self.source == source else { return }
            self.source = nil
        } else {
            self.source = source
        }
        guard reading != self.reading else { return }
        self.reading = reading
        for observer in observers.values { observer(reading) }
    }

    /// MAIN THREAD. `body` is called on every change, and once immediately
    /// with the current reading so a freshly built view starts drawn rather
    /// than blank until the next tick.
    func addObserver(_ body: @escaping (LevelMeterReading) -> Void) -> LevelMeterObservation {
        let id = nextObserver
        nextObserver += 1
        observers[id] = body
        body(reading)
        return LevelMeterObservation(id: id, meter: self)
    }

    fileprivate func removeObserver(_ id: Int) {
        observers.removeValue(forKey: id)
    }
}
