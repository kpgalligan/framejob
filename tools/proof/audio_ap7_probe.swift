import Foundation

// The live loudness meter's probe (road map "audio" AP7, spec §11 AU-70..AU-78),
// compiled as main.swift over app/Sources by audio_ap7_proof.py. Signals are
// written into sinks' rings (`LevelMeterSink.capture`, the tap's own call, and
// `measure`, for the per-track bars) as two or three tracks whose writes lead by
// 0, 2.7 and 13.4 ms, in chunks cycling 1920/512/4096 frames, and consumed by
// `LiveLoudness` at rate 1 after every cycle. Each row prints `ok|FAIL <row> …`.

func say(_ row: String, _ good: Bool, _ detail: String) {
    print("\(good ? "ok  " : "FAIL") \(row) \(detail)")
}

func fmt(_ value: Double?) -> String {
    guard let value else { return "nil" }
    return value.isFinite ? String(format: "%.4f", value) : "\(value)"
}

func near(_ value: Double?, _ wanted: Double, _ tolerance: Double) -> Bool {
    guard let value, value.isFinite else { return false }
    return abs(value - wanted) <= tolerance
}

func ramps(_ json: String) -> [PlanRamp] {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode([PlanRamp].self, from: Data(json.utf8))
}

/// A signal: (left, right) at a frame; mono uses left.
typealias Signal = (Int64) -> (Float, Float)

func sine(_ hz: Double, amplitude: Double, rate: Int, phase: Double = 0) -> Signal {
    { f in
        let x = Float(amplitude * sin(2 * Double.pi * hz * Double(f) / Double(rate) + phase))
        return (x, x)
    }
}

func dbfs(_ db: Double) -> Double { pow(10, db / 20) }

/// Tech 3341's stepped stereo 1 kHz tones: (seconds, dBFS) in order.
func steps(_ parts: [(Double, Double)], rate: Int) -> (Signal, Int64) {
    var bounds: [(Int64, Double)] = []
    var at: Int64 = 0
    for (seconds, db) in parts {
        at += Int64((seconds * Double(rate)).rounded())
        bounds.append((at, dbfs(db)))
    }
    let signal: Signal = { f in
        let amplitude = bounds.first { f < $0.0 }?.1 ?? 0
        let x = Float(amplitude * sin(2 * Double.pi * 1000 * Double(f) / Double(rate)))
        return (x, x)
    }
    return (signal, at)
}

/// One probe track: its sink and meter, its signal, where it writes, how far.
final class ProbeTrack {
    var sink = LevelMeterSink()
    let ramps: [PlanRamp]?
    let sounding: [Range<Ticks>]
    let signal: Signal
    let channels: Int
    let lead: Int64
    /// The frames its tap delivers (nil: every frame).
    let delivers: [Range<Int64>]?
    var cursor: Int64 = 0
    var stalledAt: Int64?
    let rate: Int

    init(_ signal: @escaping Signal, channels: Int = 2, lead: Int64 = 0, ramps: [PlanRamp]? = nil,
         sounding: [Range<Int64>], delivers: [Range<Int64>]? = nil, rate: Int) {
        self.signal = signal
        self.channels = channels
        self.lead = lead
        self.ramps = ramps
        self.rate = rate
        self.sounding = sounding.map {
            ($0.lowerBound * ReelTime.perSecond / Int64(rate))..<($0.upperBound * ReelTime.perSecond / Int64(rate))
        }
        self.delivers = delivers
    }

    var meter: LevelMeterTrack { LevelMeterTrack(id: 0, ramps: ramps, sounding: sounding, sink: sink) }

    func sample(_ f: Int64) -> (Float, Float) {
        if let delivers, !delivers.contains(where: { $0.contains(f) }) { return (0, 0) }
        return signal(f)
    }

    /// Writes [cursor, to) as the tap would: one chunk, split where it delivers nothing.
    func write(to end: Int64) {
        let to = stalledAt.map { min($0, end) } ?? end
        guard to > cursor else { return }
        var runs: [Range<Int64>] = [cursor..<to]
        if let delivers {
            runs = delivers.compactMap { r in
                let lo = max(r.lowerBound, cursor), hi = min(r.upperBound, to)
                return lo < hi ? lo..<hi : nil
            }
        }
        for run in runs { put(run) }
        cursor = to
    }

    func put(_ run: Range<Int64>) {
        let n = Int(run.count)
        let l = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let r = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { l.deallocate(); r.deallocate() }
        for i in 0..<n {
            let (a, b) = signal(run.lowerBound + Int64(i))
            l[i] = a
            r[i] = b
        }
        var pointers: [UnsafeMutablePointer<Float>?] = channels == 2 ? [l, r] : [l]
        pointers.withUnsafeMutableBufferPointer { p in
            sink.measure(p, count: channels, frames: n)
            sink.capture(p, count: channels, frames: n, start: run.lowerBound, sampleRate: rate)
        }
    }
}

/// The tracks, the meter, and a clock.
final class Rig {
    let rate: Int
    var tracks: [ProbeTrack]
    let live = LiveLoudness()
    var t: Int64 = 0
    var cycle = 0
    var now: TimeInterval = 100
    var playRate: Float = 1
    var readings = 0

    init(rate: Int, _ tracks: [ProbeTrack]) {
        self.rate = rate
        self.tracks = tracks
        live.onReading = { [weak self] _ in self?.readings += 1 }
    }

    var meters: [LevelMeterTrack] { tracks.map(\.meter) }

    /// Writes cycle by cycle up to `end`, consuming after each (unless `consume` is false).
    func run(to end: Int64, consume: Bool = true, each: ((LiveLoudness) -> Void)? = nil) {
        while t < end {
            let size = Int64([1920, 512, 4096][cycle % 3])
            cycle += 1
            t = min(t + size, end)
            for track in tracks { track.write(to: min(t + track.lead, end)) }
            now += Double(size) / Double(rate)
            if consume {
                live.consume(meters, rate: playRate, now: now)
                each?(live)
            }
        }
        // A leading track stops at `end` too, so the last consume sees all of it.
        if consume { live.consume(meters, rate: playRate, now: now); each?(live) }
    }

    /// Writes continue from `frame` (a seek, a restart).
    func moveTo(_ frame: Int64, newSinks: Bool = false) {
        t = frame
        for track in tracks {
            track.cursor = frame
            if newSinks { track.sink = LevelMeterSink() }
        }
    }

    func seconds(_ s: Double) -> Int64 { Int64((s * Double(rate)).rounded()) }
}

/// A fresh meter fed Σ env·x over [from, to), silence where a track delivers nothing.
func reference(_ tracks: [ProbeTrack], rate: Int, from: Int64, to: Int64) -> LoudnessMeter {
    let meter = LoudnessMeter(sampleRate: Double(rate), channelCount: 2)!
    var f = from
    while f < to {
        let n = Int(min(1013, to - f))
        var buffer = [Float](repeating: 0, count: n * 2)
        for i in 0..<n {
            let frame = f + Int64(i)
            for track in tracks {
                let g = Float(MediaPeaks.envelope(track.ramps, at: frame * ReelTime.perSecond / Int64(rate)))
                let (a, b) = track.sample(frame)
                buffer[2 * i] += a * g
                buffer[2 * i + 1] += (track.channels == 2 ? b : a) * g
            }
        }
        buffer.withUnsafeBufferPointer { meter.feed($0.baseAddress!, frames: n) }
        f += Int64(n)
    }
    return meter
}

let leads: [Int64] = [0, 130, 643]  // 0, 2.7 and 13.4 ms at 48 kHz

/// A signal split over three tracks at 0.5, 0.3 and 0.2, unity envelopes.
func split(_ signal: @escaping Signal, frames: Int64, rate: Int) -> Rig {
    let weights: [Float] = [0.5, 0.3, 0.2]
    let tracks = weights.enumerated().map { index, w in
        ProbeTrack({ f in let (a, b) = signal(f); return (a * w, b * w) },
                   lead: leads[index] * Int64(rate) / 48000, sounding: [0..<frames], rate: rate)
    }
    return Rig(rate: rate, tracks)
}

// MARK: - T1–T7: EBU Tech 3341

func steady(_ row: String, _ db: Double, rate: Int = 48000) -> Double? {
    let (signal, frames) = steps([(20, db)], rate: rate)
    let rig = split(signal, frames: frames, rate: rate)
    rig.run(to: frames)
    let r = rig.live.reading
    let wanted = db
    say(row, near(r.momentaryLUFS, wanted, 0.1) && near(r.shortTermLUFS, wanted, 0.1)
        && near(r.integratedLUFS, wanted, 0.1),
        "\(rate) Hz: M \(fmt(r.momentaryLUFS)) S \(fmt(r.shortTermLUFS)) I \(fmt(r.integratedLUFS)) (want \(wanted) ±0.1)")
    return r.integratedLUFS
}

func gated(_ row: String, _ parts: [(Double, Double)]) {
    let (signal, frames) = steps(parts, rate: 48000)
    let rig = split(signal, frames: frames, rate: 48000)
    rig.run(to: frames)
    let i = rig.live.reading.integratedLUFS
    say(row, near(i, -23, 0.1), "I \(fmt(i)) (want -23.0 ±0.1)")
}

func windowed(_ row: String, _ parts: [(Double, Double)], repeats: Int, from start: Double,
              short: Bool) {
    let (signal, frames) = steps(Array(Array(repeating: parts, count: repeats).joined()), rate: 48000)
    let rig = split(signal, frames: frames, rate: 48000)
    var worst = 0.0
    var reads = 0
    var lastHop: Int64 = -1
    rig.run(to: frames) { live in
        let r = live.reading
        guard let to = r.toFrame, let from = r.fromFrame else { return }
        let hop = (to - from) / 4800
        guard Double(to - from) >= start * 48000, hop != lastHop else { return }
        lastHop = hop
        let value = short ? r.shortTermLUFS : r.momentaryLUFS
        reads += 1
        worst = max(worst, value.map { abs($0 + 23) } ?? .infinity)
    }
    say(row, reads > 0 && worst <= 0.1,
        "\(short ? "S" : "M") at \(reads) 100 ms reads from \(start) s: worst |Δ| \(String(format: "%.4f", worst)) LU (≤ 0.1)")
}

let i48 = steady("T1", -23)
_ = steady("T2", -33)
gated("T3", [(10, -36), (60, -23), (10, -36)])
gated("T4", [(10, -72), (10, -36), (60, -23), (10, -36), (10, -72)])
gated("T5", [(20, -26), (20.1, -20), (20, -26)])
windowed("T6", [(1.34, -20), (1.66, -30)], repeats: 5, from: 3, short: true)
windowed("T7", [(0.18, -20), (0.22, -30)], repeats: 25, from: 0.4, short: false)

// MARK: - T8, T9: true peak

func truePeak(_ row: String, rate: Int, divisor: Double, degrees: Double, amplitude: Double,
              wanted: Double) {
    let frames = Int64(rate)
    let tone = sine(Double(rate) / divisor, amplitude: amplitude, rate: rate,
                    phase: degrees * Double.pi / 180)
    // A 20 ms raised-cosine fade-in: a sine switched on from silence rings
    // the interpolator past its own peak, which is the onset's, not the tone's.
    let fade = Int64(rate / 50)
    let signal: Signal = { f in
        let (a, b) = tone(f)
        guard f < fade else { return (a, b) }
        let g = Float(0.5 - 0.5 * cos(Double.pi * Double(f) / Double(fade)))
        return (a * g, b * g)
    }
    let rig = split(signal, frames: frames, rate: rate)
    rig.run(to: frames)
    let tp = rig.live.reading.truePeakDBTP
    let good = tp.map { $0 <= wanted + 0.2 && $0 >= wanted - 0.4 } ?? false
    let text = "\(rate) Hz fs/\(Int(divisor)) at \(degrees)°: TP \(fmt(tp)) dBTP (want \(String(format: "%.2f", wanted)) +0.2/-0.4)"
    if row.isEmpty { print("info \(text)") } else { say(row, good, text) }
}

// Tech 3341 cases 15–18 pair the frequencies and the phases; the rest of the
// grid is printed, not scored (the Annex 2 filter's own ripple near fs/4).
let tech3341: Set<String> = ["4.0/0.0", "4.0/45.0", "6.0/60.0", "8.0/67.5"]
for divisor in [4.0, 6.0, 8.0] {
    for degrees in [0.0, 45.0, 60.0, 67.5] {
        truePeak(tech3341.contains("\(divisor)/\(degrees)") ? "T8" : "", rate: 48000,
                 divisor: divisor, degrees: degrees, amplitude: 0.5, wanted: 20 * log10(0.5))
    }
}
// fs/4 at 45°: every sample at ±1.0 (0 dBFS), the peak between them at √2.
truePeak("T8", rate: 48000, divisor: 4, degrees: 45, amplitude: 2.0.squareRoot(),
         wanted: 20 * log10(2.0.squareRoot()))

let i44 = steady("T9", -23, rate: 44100)
say("T9", near(i44, i48 ?? .nan, 0.02),
    "44.1 kHz I \(fmt(i44)) against 48 kHz I \(fmt(i48)) (≤ 0.02 LU)")
truePeak("T9", rate: 44100, divisor: 4, degrees: 45, amplitude: 0.5, wanted: 20 * log10(0.5))

// MARK: - T10: the mix against Σ env·x

do {
    let rate = 48000
    let frames = Int64(10 * rate)
    let tone: Signal = { f in
        (Float(0.4 * sin(2 * Double.pi * 440 * Double(f) / 48000)),
         Float(0.4 * sin(2 * Double.pi * 554 * Double(f) / 48000)))
    }
    var noise: [Float] = []
    var seed: UInt32 = 12345
    for _ in 0..<frames {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        noise.append((Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.6)
    }
    let tracks = [
        ProbeTrack(tone, lead: leads[0],
                   ramps: ramps(#"[{"start":0,"duration":0,"from":0.5,"to":0.5}]"#),
                   sounding: [0..<frames], rate: rate),
        ProbeTrack({ f in (noise[Int(f)], noise[Int(f)]) }, channels: 1, lead: leads[1],
                   ramps: ramps(#"[{"start":0,"duration":6000000,"from":1,"to":0.25}]"#),
                   sounding: [0..<frames], rate: rate),
        ProbeTrack(tone, lead: leads[2],
                   ramps: ramps(#"[{"start":0,"duration":3000000,"from":0,"to":0},{"start":3000000,"duration":600000,"from":0,"to":0.7}]"#),
                   sounding: [0..<frames], rate: rate),
    ]
    let rig = Rig(rate: rate, tracks)
    rig.run(to: frames)
    let r = rig.live.reading
    let ref = reference(tracks, rate: rate, from: r.fromFrame ?? 0, to: r.toFrame ?? 0)
    let report = ref.finish()
    let dI = abs((r.integratedLUFS ?? .nan) - (report.integratedLUFS ?? .nan))
    let dM = abs((r.momentaryLUFS ?? .nan) - (ref.momentaryLUFS ?? .nan))
    let dS = abs((r.shortTermLUFS ?? .nan) - (ref.shortTermLUFS ?? .nan))
    say("T10", r.fromFrame == 0 && r.toFrame == frames && dI <= 0.01 && dM <= 0.01 && dS <= 0.01,
        "frames [\(r.fromFrame ?? -1), \(r.toFrame ?? -1)) of \(frames); I \(fmt(r.integratedLUFS)) vs \(fmt(report.integratedLUFS)), "
            + "|ΔI| \(fmt(dI)) |ΔM| \(fmt(dM)) |ΔS| \(fmt(dS)) LU (≤ 0.01)")
}

// MARK: - T11: continuity

func steadyPair(rate: Int, seconds: Double = 60) -> [ProbeTrack] {
    let frames = Int64(seconds * Double(rate))
    return [
        ProbeTrack(sine(997, amplitude: 0.1, rate: rate), lead: leads[0], sounding: [0..<frames], rate: rate),
        ProbeTrack(sine(311, amplitude: 0.08, rate: rate), lead: leads[2], sounding: [0..<frames], rate: rate),
    ]
}

do {
    let rate = 48000
    let tracks = steadyPair(rate: rate)
    let rig = Rig(rate: rate, tracks)
    rig.run(to: rig.seconds(3))
    let before = rig.live.reading
    // A seek 0.5 s ahead of where the writes are.
    rig.moveTo(rig.t + rig.seconds(0.5))
    rig.run(to: rig.t + rig.seconds(2))
    let jumped = rig.live.reading
    say("T11", jumped.resets == before.resets + 1 && jumped.lastReset == .jump
        && jumped.fromFrame.map { $0 >= rig.seconds(3.5) - 700 } == true,
        "a +0.5 s seek: resets \(before.resets) → \(jumped.resets), last \(jumped.lastReset?.rawValue ?? "nil"), from \(jumped.fromFrame ?? -1)")
    // An edit's rebuild: new sinks, the restore landing 0.3 s behind.
    rig.moveTo((rig.live.reading.toFrame ?? 0) - rig.seconds(0.3), newSinks: true)
    rig.run(to: rig.t + rig.seconds(2))
    // A pause, then continue from 0.2 s behind the frame reached.
    rig.live.stop()
    rig.moveTo((rig.live.reading.toFrame ?? 0) - rig.seconds(0.2))
    rig.run(to: rig.t + rig.seconds(2))
    let r = rig.live.reading
    let span = (r.toFrame ?? 0) - (r.fromFrame ?? 0)
    let ref = reference(tracks, rate: rate, from: r.fromFrame ?? 0, to: r.toFrame ?? 0).finish()
    let dI = abs((r.integratedLUFS ?? .nan) - (ref.integratedLUFS ?? .nan))
    say("T11", r.resets == jumped.resets && rig.live.fedFrames == span && dI <= 0.01,
        "a rebuild 0.3 s behind and a pause 0.2 s behind: resets \(r.resets) (want \(jumped.resets)), "
            + "frames fed \(rig.live.fedFrames) of [\(r.fromFrame ?? -1), \(r.toFrame ?? -1)) = \(span), |ΔI| \(fmt(dI)) (≤ 0.01)")

    // A seek as the player delivers it (measured, AP7): each track hands over
    // a buffer of the old position first, and one track a second one in the
    // drain after another has already moved.
    let p = rig.t + rig.seconds(2)
    for track in rig.tracks { track.put(track.cursor..<(track.cursor + 4096)) }
    rig.tracks[0].put(p..<(p + 4096))
    rig.live.consume(rig.meters, rate: 1, now: rig.now + 0.03)
    let old = rig.tracks[1].cursor + 4096
    rig.tracks[1].put(old..<(old + 4096))
    rig.tracks[1].put(p..<(p + 4096))
    rig.now += 0.06
    rig.live.consume(rig.meters, rate: 1, now: rig.now)
    rig.moveTo(p + 4096)
    rig.run(to: rig.t + rig.seconds(2))
    let s = rig.live.reading
    let sSpan = (s.toFrame ?? 0) - (s.fromFrame ?? 0)
    let sRef = reference(tracks, rate: rate, from: s.fromFrame ?? 0, to: s.toFrame ?? 0).finish()
    let sI = abs((s.integratedLUFS ?? .nan) - (sRef.integratedLUFS ?? .nan))
    say("T11", s.resets == r.resets + 1 && s.lastReset == .jump && s.fromFrame == p
        && rig.live.fedFrames == sSpan && sI <= 0.01,
        "a seek with a stale buffer per track first: resets \(r.resets) → \(s.resets) (want +1), from \(s.fromFrame ?? -1) (want \(p)), "
            + "fed \(rig.live.fedFrames) of \(sSpan), |ΔI| \(fmt(sI))")
}

// MARK: - T12: a stalled track and a track past its last span

do {
    let rate = 48000
    let tracks = steadyPair(rate: rate, seconds: 10)
    tracks[1].stalledAt = 96000
    let rig = Rig(rate: rate, tracks)
    rig.run(to: rig.seconds(2.3))
    let held = rig.live.reading.toFrame
    rig.run(to: rig.seconds(5))
    let freed = rig.live.reading.toFrame
    say("T12", held == 96000 && freed == rig.seconds(5),
        "track 2 stalls at 2.0 s: the sum at \(held ?? -1) with track 1 at 2.3 s (want 96000), at \(freed ?? -1) with it at 5 s (want 240000)")

    let past = [
        ProbeTrack(sine(997, amplitude: 0.1, rate: rate), sounding: [0..<480000], rate: rate),
        ProbeTrack(sine(311, amplitude: 0.08, rate: rate), lead: leads[2], sounding: [0..<96000],
                   delivers: [0..<96000], rate: rate),
    ]
    let rig2 = Rig(rate: rate, past)
    rig2.run(to: rig2.seconds(2.3))
    let at = rig2.live.reading.toFrame
    say("T12", at == rig2.seconds(2.3) && rig2.live.reading.resets == 0,
        "track 2's last span ends at 2.0 s: the sum at \(at ?? -1) with track 1 at 2.3 s (want 110400), resets \(rig2.live.reading.resets)")
}

// MARK: - T13: overrun

do {
    let rate = 48000
    let rig = Rig(rate: rate, steadyPair(rate: rate))
    rig.run(to: rig.seconds(1))
    rig.run(to: rig.seconds(4), consume: false)  // 3 s unread: more than the ring holds
    rig.run(to: rig.seconds(6))
    let r = rig.live.reading
    say("T13", r.resets == 1 && r.lastReset == .overrun && r.toFrame == rig.seconds(6),
        "3 s unread: resets \(r.resets), last \(r.lastReset?.rawValue ?? "nil"), measuring on to \(r.toFrame ?? -1)")
}

// MARK: - T14: rate, then stop

do {
    let rate = 48000
    let rig = Rig(rate: rate, steadyPair(rate: rate))
    rig.run(to: rig.seconds(4))
    let one = rig.live.reading
    rig.playRate = 2
    rig.run(to: rig.seconds(5))
    let two = rig.live.reading
    say("T14", two.momentaryLUFS == nil && two.shortTermLUFS == nil && !two.measuring
        && two.integratedLUFS == one.integratedLUFS && two.truePeakDBTP == one.truePeakDBTP
        && two.toFrame == one.toFrame && two.offSpeed,
        "×2: M \(fmt(two.momentaryLUFS)) S \(fmt(two.shortTermLUFS)) I \(fmt(two.integratedLUFS)) (held \(fmt(one.integratedLUFS))) "
            + "TP \(fmt(two.truePeakDBTP)) measuring \(two.measuring), to \(two.toFrame ?? -1) (held \(one.toFrame ?? -1))")
    rig.run(to: rig.seconds(5.2), consume: false)
    let fired = rig.readings
    rig.live.stop()
    let stopped = rig.live.reading
    let empty = rig.tracks.allSatisfy { $0.sink.ring.drain().chunks.isEmpty }
    say("T14", stopped.momentaryLUFS == one.momentaryLUFS && stopped.shortTermLUFS == one.shortTermLUFS
        && stopped.integratedLUFS == one.integratedLUFS && stopped.truePeakDBTP == one.truePeakDBTP
        && !stopped.measuring && rig.readings == fired + 1 && empty && rig.live.bars == nil,
        "stop: M \(fmt(stopped.momentaryLUFS)) S \(fmt(stopped.shortTermLUFS)) held, measuring \(stopped.measuring), "
            + "onReading \(rig.readings - fired) time(s), rings empty \(empty)")
    rig.playRate = 1
    rig.moveTo(stopped.toFrame ?? 0)
    rig.run(to: rig.t + rig.seconds(2))
    let resumed = rig.live.reading
    let span = (resumed.toFrame ?? 0) - (resumed.fromFrame ?? 0)
    say("T14", resumed.resets == 0 && resumed.fromFrame == one.fromFrame && rig.live.fedFrames == span
        && resumed.measuring,
        "resume at ×1 from \(stopped.toFrame ?? -1): resets \(resumed.resets), from \(resumed.fromFrame ?? -1), fed \(rig.live.fedFrames) of \(span)")
}

// MARK: - T15: the bars

do {
    let rate = 48000
    let frames = Int64(rate)
    let tone = sine(1000, amplitude: 0.5, rate: rate)
    for (name, inverse) in [("correlated", false), ("inverse", true)] {
        let second: Signal = inverse ? { f in let (a, b) = tone(f); return (-a, -b) } : tone
        let tracks = [
            ProbeTrack(tone, sounding: [0..<frames * 2], rate: rate),
            ProbeTrack(second, sounding: [0..<frames * 2], rate: rate),
        ]
        let rig = Rig(rate: rate, tracks)
        rig.run(to: frames)
        let bars = rig.live.bars
        let perTrack = LevelMeterTrack.mix(rig.meters, at: 0)
        let wanted: Float = inverse ? 0 : 1
        say("T15", bars.map { abs($0.peakLeft - wanted) <= 0.01 && abs($0.peakRight - wanted) <= 0.01 } == true
            && abs(perTrack.peakLeft - 1) <= 0.01,
            "\(name): the mix's peak \(bars.map { String(format: "%.4f", $0.peakLeft) } ?? "nil") (want \(wanted)), "
                + "the per-track sum's \(String(format: "%.4f", perTrack.peakLeft))")
    }
}

// MARK: - T16: gaps between clips

do {
    let rate = 48000
    let end: Int64 = 240000
    func gap(_ row: String, _ name: String, seconds: Double, twoTracks: Bool) {
        let resume = 96000 + Int64(seconds * Double(rate))
        let clips: [Range<Int64>] = [0..<96000, resume..<end]
        var tracks = [ProbeTrack(sine(997, amplitude: 0.1, rate: rate), sounding: clips, delivers: clips, rate: rate)]
        if twoTracks {
            tracks.append(ProbeTrack(sine(311, amplitude: 0.08, rate: rate), lead: leads[2],
                                     sounding: [0..<end], rate: rate))
        }
        let rig = Rig(rate: rate, tracks)
        rig.run(to: end)
        let r = rig.live.reading
        let span = (r.toFrame ?? 0) - (r.fromFrame ?? 0)
        let ref = reference(tracks, rate: rate, from: r.fromFrame ?? 0, to: r.toFrame ?? 0).finish()
        let dI = abs((r.integratedLUFS ?? .nan) - (ref.integratedLUFS ?? .nan))
        say(row, r.resets == 0 && r.fromFrame == 0 && r.toFrame == end && rig.live.fedFrames == span && dI <= 0.01,
            "\(name): resets \(r.resets), frames [\(r.fromFrame ?? -1), \(r.toFrame ?? -1)), fed \(rig.live.fedFrames), "
                + "I \(fmt(r.integratedLUFS)) vs \(fmt(ref.integratedLUFS)) |ΔI| \(fmt(dI)) (≤ 0.01)")
    }
    gap("T16", "a 0.3 s gap on one track", seconds: 0.3, twoTracks: false)
    gap("T16", "a 1 s gap on one track", seconds: 1, twoTracks: false)
    gap("T16", "a 0.3 s gap on one of two tracks", seconds: 0.3, twoTracks: true)
    gap("T16", "a 1 s gap on one of two tracks", seconds: 1, twoTracks: true)
}
