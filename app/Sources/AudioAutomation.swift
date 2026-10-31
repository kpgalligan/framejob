import Foundation

// An audio segment's automation (road map "audio" AP8b, spec §11 AU-85..AU-88): the plan's
// points, read and interpolated; the tap's settings at a run's anchor on the absolute 32-frame
// grid; the per-sample pan between two points; and the inspector's routing inside an action.
// The core evaluates every point (`audio_automation.rs`); this side only draws straight lines
// between them.

/// One point of a segment's automation: the tap keys of the clip's
/// evaluated audio at `at`, in project (= composition) ticks. Every other
/// key decodes to its default and is never read.
struct PlanAudioPoint: Codable, Equatable {
    let at: Ticks
    let audio: AudioProps

    init(at: Ticks, audio: AudioProps) {
        self.at = at
        self.audio = audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = c.lenient(.at, 0)
        audio = c.lenient(.audio, AudioProps())
    }
}

// MARK: - Interpolation (AU-85, AU-86)

private func mix(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }

/// A tick field between two points, rounded as the core's `lerp_number`
/// rounds an integral pair.
private func mix(_ a: Ticks, _ b: Ticks, _ f: Double) -> Ticks {
    Ticks((Double(a) + Double(b - a) * f).rounded())
}

/// `a` toward `b` when both are present, else `a`: presence comes from the
/// left point (AU-85).
private func both<T>(_ a: T?, _ b: T?, _ blend: (T, T) -> T) -> T? {
    guard let a else { return nil }
    guard let b else { return a }
    return blend(a, b)
}

extension AudioProps {
    /// These props `f` of the way (0…1) toward `next`'s, as the plan's points
    /// are joined: a number moves linearly when its group is present on both
    /// sides; presence, a switch, an enum, `bypass`, and the EQ slopes, the
    /// hum's mains and its harmonics (the core's `HELD_AUDIO_NUMBERS`,
    /// AU-86) are the left point's. Keys the plan's points do not carry
    /// (volume, fades, duck, keep pitch, voice) are this side's, unread.
    func interpolated(toward next: AudioProps, by f: Double) -> AudioProps {
        let compressor = both(self.compressor, next.compressor) { a, b in
            CompressorProps(
                thresholdDb: mix(a.thresholdDb, b.thresholdDb, f), ratio: mix(a.ratio, b.ratio, f),
                attack: mix(a.attack, b.attack, f), release: mix(a.release, b.release, f),
                makeupDb: mix(a.makeupDb, b.makeupDb, f))
        }
        let limiter = both(self.limiter, next.limiter) { a, b in
            LimiterProps(
                ceilingDb: mix(a.ceilingDb, b.ceilingDb, f), release: mix(a.release, b.release, f))
        }
        let eq = both(self.eq, next.eq) { a, b in
            func pass(_ x: EqPassProps?, _ y: EqPassProps?) -> EqPassProps? {
                both(x, y) { EqPassProps(frequency: mix($0.frequency, $1.frequency, f), slope: $0.slope) }
            }
            func shelf(_ x: EqShelfProps?, _ y: EqShelfProps?) -> EqShelfProps? {
                both(x, y) {
                    EqShelfProps(
                        frequency: mix($0.frequency, $1.frequency, f),
                        gainDb: mix($0.gainDb, $1.gainDb, f))
                }
            }
            func band(_ x: EqBandProps?, _ y: EqBandProps?) -> EqBandProps? {
                both(x, y) {
                    EqBandProps(
                        frequency: mix($0.frequency, $1.frequency, f),
                        gainDb: mix($0.gainDb, $1.gainDb, f), q: mix($0.q, $1.q, f))
                }
            }
            return EqProps(
                highPass: pass(a.highPass, b.highPass), lowShelf: shelf(a.lowShelf, b.lowShelf),
                band1: band(a.band1, b.band1), band2: band(a.band2, b.band2),
                band3: band(a.band3, b.band3), highShelf: shelf(a.highShelf, b.highShelf),
                lowPass: pass(a.lowPass, b.lowPass), bypass: a.bypass)
        }
        let hum = both(self.hum, next.hum) { a, b in
            HumProps(
                frequency: a.frequency, depthDb: mix(a.depthDb, b.depthDb, f),
                harmonics: a.harmonics)
        }
        let gate = both(self.gate, next.gate) { a, b in
            GateProps(
                thresholdDb: mix(a.thresholdDb, b.thresholdDb, f), ratio: mix(a.ratio, b.ratio, f),
                rangeDb: mix(a.rangeDb, b.rangeDb, f), attack: mix(a.attack, b.attack, f),
                hold: mix(a.hold, b.hold, f), release: mix(a.release, b.release, f))
        }
        let deEsser = both(self.deEsser, next.deEsser) { a, b in
            DeEsserProps(
                frequency: mix(a.frequency, b.frequency, f),
                thresholdDb: mix(a.thresholdDb, b.thresholdDb, f),
                rangeDb: mix(a.rangeDb, b.rangeDb, f))
        }
        return AudioProps(
            volume: volume, muted: muted, fadeIn: fadeIn, fadeOut: fadeOut, duck: duck,
            mono: mono, keepPitch: keepPitch, pan: mix(pan, next.pan, f), compressor: compressor,
            noiseReduction: mix(noiseReduction, next.noiseReduction, f),
            fadeInShape: fadeInShape, fadeOutShape: fadeOutShape, limiter: limiter,
            isolation: mix(isolation, next.isolation, f), eq: eq, hum: hum, channels: channels,
            gate: gate, deEsser: deEsser, voice: voice)
    }
}

// MARK: - The tap's view (AU-87)

/// One automated span's points and the base facts its settings keep: the
/// limiter's divisor is the BASE volume (AU-22), the gate's and de-esser's
/// level the base measurement (AU-41), and a nest's fold and the tracks'
/// balance are the segment's, not the points'.
struct AudioDSPAutomation: Equatable {
    /// The control grid, in frames: a run's settings are read at its anchor
    /// and a run never crosses one of these boundaries.
    static let controlFrames: Int64 = 32

    /// Sorted by `at`, at least one.
    let points: [PlanAudioPoint]
    let volume: Double
    let level: Double?
    let enclosingMono: Bool
    let trackBalance: AudioTrackBalance

    /// The index of the last point at or before `tick` (0 before the first).
    private func index(atTick tick: Double) -> Int {
        var low = 0
        var high = points.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Double(points[middle].at) <= tick { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The props at `tick`: the two points around it joined linearly.
    func props(at tick: Double) -> AudioProps {
        let i = index(atTick: tick)
        guard i + 1 < points.count else { return points[i].audio }
        let a = points[i]
        let b = points[i + 1]
        let width = Double(b.at - a.at)
        let f = width > 0 ? min(max((tick - Double(a.at)) / width, 0), 1) : 0
        return a.audio.interpolated(toward: b.audio, by: f)
    }

    /// The chain's settings at `tick`.
    func settings(at tick: Double) -> AudioClipDSP {
        var dsp = AudioDSPParameters.dsp(
            props(at: tick), volume: volume, level: level, enclosingMono: enclosingMono)
        dsp.trackBalance = trackBalance
        return dsp
    }

    /// `⌈tick · rate / perSecond⌉`: the first frame at or after `tick`.
    static func frame(ofTick tick: Ticks, rate: Int64) -> Int64 {
        let scaled = tick * rate
        let quotient = scaled / ReelTime.perSecond
        return scaled % ReelTime.perSecond > 0 ? quotient + 1 : quotient
    }

    /// The index of the last point whose frame is at or before `frame`, 0
    /// when none is. Value arithmetic only: the tap calls it per run.
    func pointIndex(atFrame frame: Int64, rate: Int64) -> Int {
        var low = 0
        var high = points.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if Self.frame(ofTick: points[middle].at, rate: rate) <= frame {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// The run starting at lookup frame `frame` of a span starting at
    /// `spanStart` (AU-87): the settings at the run's ANCHOR — the latest of
    /// the grid boundary at or before `frame`, the left point's frame and the
    /// span's first frame — how many frames they hold for (to the next grid
    /// boundary or point frame), and the per-sample pan between the two
    /// points when they differ.
    func control(atFrame frame: Int64, spanStart: Ticks, rate: Int64)
        -> (settings: AudioClipDSP, frames: Int, pan: AudioPanRamp?)
    {
        let i = pointIndex(atFrame: frame, rate: rate)
        let step = Self.controlFrames
        let remainder = frame % step
        let grid = remainder < 0 ? frame - remainder - step : frame - remainder
        let anchor = max(
            grid, Self.frame(ofTick: points[i].at, rate: rate),
            Self.frame(ofTick: spanStart, rate: rate))
        var next = grid + step
        var pan: AudioPanRamp?
        let ticksPerFrame = Double(ReelTime.perSecond) / Double(rate)
        if i + 1 < points.count {
            let a = points[i]
            let b = points[i + 1]
            next = min(next, Self.frame(ofTick: b.at, rate: rate))
            if a.audio.pan != b.audio.pan {
                pan = AudioPanRamp(
                    from: a.audio.pan, to: b.audio.pan, fromTick: Double(a.at),
                    toTick: Double(b.at), firstFrame: frame, ticksPerFrame: ticksPerFrame)
            }
        }
        let frames = Int(max(1, next - frame))
        return (settings(at: Double(anchor) * ticksPerFrame), frames, pan)
    }

    /// Whether any point asks for noise reduction or a limiter: each runs
    /// for the whole track once one does (AU-23, AU-87).
    var usesNoiseReduction: Bool { points.contains { $0.audio.noiseReduction > 0 } }
    var usesLimiter: Bool { points.contains { $0.audio.limiter != nil } }

    /// Whether no point asks for any sample work: joined linearly, two inert
    /// points are inert between them.
    var isInert: Bool { points.allSatisfy { settings(at: Double($0.at)).isInert } }

    /// Whether any point asks for isolation.
    var isolates: Bool { points.contains { $0.audio.isolation > 0 } }
}

/// The pan between two points, per sample (AU-87): the sample's tick on the
/// lookup grid, the pan there by the straight line between the points.
struct AudioPanRamp: Equatable {
    let from: Double
    let to: Double
    let fromTick: Double
    let toTick: Double
    /// The run's first lookup frame, and ticks per frame at the tap's rate.
    let firstFrame: Int64
    let ticksPerFrame: Double

    func pan(sample i: Int) -> Double {
        let tick = Double(firstFrame + Int64(i)) * ticksPerFrame
        let width = toTick - fromTick
        let f = width > 0 ? min(max((tick - fromTick) / width, 0), 1) : 0
        return from + (to - from) * f
    }

    /// The chain's pan stage with a gain pair per sample: scalar, in place,
    /// nothing allocated. A one-channel track has nothing to lean (the caller
    /// asks for two).
    func apply(_ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, frames: Int) {
        let left = channels[0]
        let right = channels[1]
        for i in 0..<frames {
            let gains = AudioPanLaw.gains(pan(sample: i))
            left?[i] *= gains.left
            right?[i] *= gains.right
        }
    }
}

// MARK: - The inspector (AU-88)

extension AudioPatch {
    /// A write with an action selected (spec §11 AU-88, amending CI-3): the
    /// duck, Keep pitch, the fade shapes and the voice effect stay with the
    /// clip's base props, and so does a NEST clip's mono (its fold is the
    /// nest's mix, carried down at the base); everything else — volume, the
    /// fades and the eleven tap keys — goes to the action's end, where a
    /// switch turned off becomes `off` (`ReelOp.setActionEnd`).
    func routedInsideAction(nestClip: Bool) -> (base: AudioPatch?, end: AudioPatch?) {
        let base = AudioPatch(
            duck: duck, mono: nestClip ? mono : nil, keepPitch: keepPitch,
            fadeInShape: fadeInShape, fadeOutShape: fadeOutShape, voice: voice)
        var end = self
        (end.duck, end.keepPitch, end.voice) = (nil, nil, nil)
        (end.fadeInShape, end.fadeOutShape) = (nil, nil)
        if nestClip { end.mono = nil }
        return (base.isEmpty ? nil : base, end.isEmpty ? nil : end)
    }
}
