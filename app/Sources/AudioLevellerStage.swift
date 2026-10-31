import Foundation

/// What one clip's leveller asks the tap for (spec §11 AU-66 (d)): its target
/// and two caps in dB, and the clip's curve for its response
/// (`AudioLevellerCurve`), made ahead of time. A hand-edited value outside the
/// model's ranges is held to them (the core's `clamp_leveller` says the same).
struct AudioLevellerSettings: Equatable {
    /// dB re the clip's loudness.
    let targetDB: Double
    let maxUpDB: Double
    let maxDownDB: Double
    let curve: AudioLevellerCurve

    /// The response's model range, in ticks: the key `curves` is made under.
    static func response(_ props: LevellerProps) -> Ticks {
        Swift.min(Swift.max(props.response, 300_000), 6_000_000)
    }

    /// nil when `curves` has none for the props' response: the clip plays
    /// un-levelled (pending or unmeasurable, AU-66 (e)).
    init?(props: LevellerProps, curves: [Ticks: AudioLevellerCurve]) {
        guard let curve = curves[Self.response(props)] else { return nil }
        func bounded(_ value: Double, _ low: Double, _ high: Double, _ neutral: Double) -> Double {
            value.isNaN ? neutral : Swift.min(Swift.max(value, low), high)
        }
        targetDB = bounded(props.targetDb, -20, 10, 0)
        maxUpDB = bounded(props.maxUpDb, 0, 24, 12)
        maxDownDB = bounded(props.maxDownDb, 0, 24, 12)
        self.curve = curve
    }

    /// The linear gain where the material sits `r` dB re L:
    /// 10^(clamp(target − r, −max down, +max up)/20).
    func gain(_ r: Float) -> Float {
        let db = Swift.min(Swift.max(targetDB - Double(r), -maxDownDB), maxUpDB)
        return Float(exp(db * (log(10.0) / 20)))
    }
}

/// One run of the leveller in the tap (spec §11 AU-66 (d)): the gain at each
/// step centre from the run's settings, a sample's the straight line in gain
/// between the two step centres around its tick, one gain for every channel.
///
/// **Stateless.** A sample's tick is `(firstFrame + i)·perSecond/rate`, the
/// lookup frame the automation reads (AU-87): the samples after the reducer
/// belong to `t + lookupLead`. So the output is a pure function of the
/// absolute frame — no reset, nothing carried across a cut, a seek or a clip
/// — and block size, seeks, the preview, the export and AU-64's render agree
/// by construction. Nothing allocated or locked; `exp` runs once per step
/// centre the run crosses.
struct AudioLevellerRun {
    let settings: AudioLevellerSettings
    let firstFrame: Int64
    let ticksPerFrame: Double

    init(settings: AudioLevellerSettings, firstFrame: Int64, rate: Int64) {
        self.settings = settings
        self.firstFrame = firstFrame
        ticksPerFrame = Double(ReelTime.perSecond) / Double(max(rate, 1))
    }

    /// Levels `frames` samples in place across `count` channels.
    func apply(
        _ channels: UnsafeMutableBufferPointer<UnsafeMutablePointer<Float>?>, count: Int,
        frames: Int
    ) {
        let count = min(count, channels.count)
        let curve = settings.curve
        guard frames > 0, count > 0, !curve.values.isEmpty else { return }
        var held = -1
        var heldNext = -1
        var from: Float = 1
        var to: Float = 1
        for i in 0..<frames {
            let tick = Double(firstFrame + Int64(i)) * ticksPerFrame
            let at = curve.position(atTick: tick)
            if at.index != held || at.next != heldNext {
                // The step after the last one is usually the next one in.
                from = at.index == heldNext ? to : settings.gain(curve.values[at.index])
                to = at.next == at.index ? from : settings.gain(curve.values[at.next])
                (held, heldNext) = (at.index, at.next)
            }
            let g = from + (to - from) * Float(at.fraction)
            for channel in 0..<count { channels[channel]?[i] *= g }
        }
    }
}
