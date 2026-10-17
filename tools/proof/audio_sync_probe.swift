// Road maps "audio-sync" (AS-1, AS-2) and "audio-sync-2" (AS-3, AS-4), its
// round 3 and the clean-up — spec §11 SY-1..SY-22, SY-28..SY-34 — Synchronize
// Audio's arithmetic, measured through the app's own
// `SyncFeatures`, `AudioSyncMatch`, `AudioSyncPHAT`, `SyncResampler` and
// `AudioSync` with no document and no window; only P19, P23 and P25 touch
// the disk, each in a folder of its own that it removes.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a`, by
// `swift_build.build` (`audio_sync_proof.py` builds and runs it). One process,
// no arguments (or `cost <dir>` for P19 alone, `determinism <dir>` for P25
// alone); the answer is one JSON object on stdout, `{"rows": [...]}`, each
// row `{"id", "pass", "detail", "instrument"}`.
//
// Every array is made here from a seeded LCG, so a run is the same run. No
// expected number is read back from the code under test: each is written as
// the arithmetic the spec states (delta = snap(zeroA − zeroN + lag·9600)).
// Features are frame-major, 26 floats a frame, one frame per 9,600 ticks;
// samples (the refinement's input, SY-20) 8 kHz int16, 75 ticks each. The
// smooth `featureBumps` keep AS-2's 6,000-tick bucket as their clock, so a
// planted lag is a multiple of 48,000 ticks, whole on both grids. A reading
// with no samples is never refined, and its drift is the features' line; a
// pair with no samples at all keeps the features' tier (SY-29), so the rows
// built on features alone still read the search.
//
//   P1  delta arithmetic: five placements of a mover whose features are the
//       anchor's shifted by a known number of frames, each delta, start and
//       lag against its hand-worked value at 30 fps (no samples: unrefined).
//   P2  the anchor rule (SY-2): pictures first, then earliest start, then
//       rearmost track, then lowest id; a named anchor wins; a named stranger
//       is nil.
//   P3  end to end, `SyncFeatures.frames` of 30 s of 8 kHz bursts and of the
//       same 313 frames later, 9 dB down with noise, searched: lag −313 ±0.5,
//       chosen by confidence.
//   P4  unrelated features plan to the refusal naming the played windows'
//       candidates and the rule from its constants, the waveform clause
//       (SY-29) included; two 100-frame files (no search can run) to "too
//       little room to compare their sound."
//   P5  drift (SY-21) on smooth features stretched by known ratios, within
//       ±5 ppm, including 100 ppm at exactly `driftMinimumOverlapFrames` and
//       200 ppm with the mover's frames 4,000–7,000 seeded noise (whole
//       windows of it, skipped by the window floor); one frame under the
//       minimum is not measured; a mover that sounds only in its first 1,875
//       of 9,375 frames is not measured (the span rule); a 4,000-frame
//       overlap where only the two end windows can match is not measured,
//       naming 2 windows (the count rule, checked first), and the same with
//       the other frames seeded noise rather than silence. The noise case
//       holds by the robust filter (Theil–Sen, MAD inliers, SY-21).
//   P6  the refusals (SY-4): windows that never meet, two clips on one
//       track, a neighbour on the mover's track; a neighbour that only abuts
//       the new window is not refused; a silent anchor is named once, and not
//       against the movers, and a silent mover is named alone.
//   P7  correction (SY-6, SY-10): a +1,000 ppm mover (it lengthens) and a
//       −1,000 ppm one (it shortens): the set_speed rate within 5 ppm of s/k,
//       keep_pitch false, delta the hand-worked snap(zeroA + 6000·c − S + I·k)
//       (c in buckets; the plan's own c is in samples, the same tick)
//       — the centre-line delta printed as a control at least 2 frames away —
//       and the ops in SY-10's order; a neighbour abutting the old end with
//       delta 0 is refused, the same neighbour 10 frames later is not.
//   P8  SY-8's boundaries (4.99 vs 5.0 ms, a drift just over, exactly at and
//       just under 3× its uncertainty, a new speed
//       0.0019 vs 0.0021 from ×1), a 20 ppm drift left with its note; a
//       reading at speed 1/k with the drifted features makes no op, one at
//       ×0.9999 is set to within 5 ppm of 1/k; `rateProblem` at
//       ×2, ×1.002, ×1.0021, ×0.998, ×0.9979.
//   P9  `SyncFeatures` (SY-11): `frameCount` at its edges, the frames of a
//       signal delayed by 5·128 samples (fed in odd pieces) are its frames
//       shifted by 5 (max |Δ| < 1e-3), digital silence `isSilent` and a noise
//       floor not, `frameTicks` 9,600.
//   P10 `summedCorrelation` equals a brute-force sum on short arrays; a lag
//       planted at a partial overlap, the mover's gain and coefficient levels
//       changed and noise added, is recovered within ±0.25 frame and chosen
//       by confidence; the candidates lie more than 60 frames apart.
//   P11 `choose` at its boundaries, written from the constants (z confidentZ
//       against 0.01 under, margin confidentMargin against 0.01 under, a near
//       peak at plausibleZ against 0.01 under, confident beats nearer); the near
//       placement within 188 frames and not at 189; a strong peak with only
//       its flank inside the radius and a margin under 1.5 gives no near
//       placement and no choice (the flank's z ≥ 4 is the control); `find`:
//       the played windows before the whole files, the whole files when the
//       played windows choose nothing and a window is a part of its file or
//       is under 125 frames, never when both are whole files, and the refusal
//       naming each search's first candidate as its move.
//   P12 the head trim (SY-16) against hand-worked numbers: a ×1 mover at
//       −0.5 s is trimmed by 0.5 s (ops, start 0, trimmed, duration); a
//       +1,000 ppm mover needing 5 s gets set_speed, trim_start, move_clip;
//       exactly one frame left is planned, under one refused; a trimmed span
//       that no longer meets the anchor is refused; a neighbour meeting the
//       trimmed span is refused, the same one frame clear is not.
//   P13 unrelated sound placed where it overlaps (both at 0, placement lag
//       0): four pairs of 30 s bursts from different seeds, each reading
//       carrying its bursts as int16 samples, and one pair of white-noise
//       frames with seeded noise samples, each refused "no matching sound
//       found" — never planned, not even weak (SY-18, SY-29); each near
//       placement's z printed, and whether the search or the gate refused.
//   P14 speech-only matching (SY-17): `speechMask` on a hand-worked chunk
//       list (the frame's centre chunk, ≥ 0.5) and on none; `frameCentreTicks`
//       19,200; `resampledMask` the identity at ×1 and as long as
//       `resampledFrames` at ×1.001; the masked `standardised` of 200 frames
//       with 120 speech frames (mean 0, sd 1 over them, the others 0); a
//       planted pair whose speech segment (300 frames, lag +200) loses to an
//       unmarked longer one (400 frames, lag −300) on sound and wins on
//       speech; 124 speech frames in the mover is on sound, 125 on speech.
//   P15 the weak tier's words (SY-18, SY-19): `weakMoves` of a confident
//       mover, a weak one that moves and trims, a weak one already in place;
//       `weakQuestion`'s message and one-mover detail and `weakNote`, each
//       exactly; two weak movers joined with "; "; a weak mover listed only
//       for its drift correction worded as the speed it plays at.
//   P16 the PHAT refinement (SY-20): `correlation` against a naive-DFT PHAT on
//       256 and 200 samples (worst relative |Δ| ≤ 1e-4); seeded Gaussian pips
//       (σ 4 ms, 400–3,000 Hz, at fractional times) planted 37.4 samples
//       late, the mover 6 dB down with its own noise: shift 37.4 ±0.1 and
//       clear; unrelated pips not clear (z printed); a true lag of exactly
//       `reachSamples` not clear (its z ≥ `clearZ` the control); a decoy
//       stretch shared at lag +2,000 holding 64% of the region beside the
//       true +20: 20 ±0.1 (control: the decoy's r above the true peak's); a
//       15,999-sample region and an all-zero slice nil.
//   P17 through `plan`: pips PCM with `SyncFeatures.frames` features, the
//       anchor 1.204 s later, no drift: refined clear, |offset − truth| ≤ 75
//       ticks, delta the snapped truth (control: |coarse − truth| > 150
//       ticks, else an instrument failure); the same pips over 120 s at +200
//       ppm: drift measured on PHAT within ±1 ppm; and with the mover's
//       [40 s, 70 s) seeded noise: on the features alone (no samples) within
//       ±5 ppm on features, with samples within ±5 ppm on PHAT (control: the
//       features-only line skipped a gap window).
//   P19 (only with the arguments `cost <dir>`, and then alone; the proof's
//       `--cost`, built -O whole-module): SY-22's budget. One hour of pips
//       and a mover at +100 ppm, their `.bin`, `.pcm` and current marker written
//       under <dir>/cache/sync/; the thread CPU and wall of loading both
//       files and of `AudioSync.plan`, the total ≤ 1.5 s of CPU (control:
//       confident, drift on PHAT over 64 windows, the refinement clear);
//       drift again with no shared setup, printed; <dir> removed.
//   P18 #300: 160 s of pips against a mover at ±1,000 ppm (features from its
//       own PCM): confident, drift measured on PHAT, the set_speed rate
//       within 5 ppm of 1/k; the plan's wall seconds printed.
//   P20 the waveform gate (SY-29) through `plan`: 30 s seeded feature
//       frames with a planted lag of 300 frames, the mover 60 frames from
//       it, and pips PCM planted 300·128 + 37.4 samples late. (a) the lag at
//       weight 0.03 (control: its near peak 4 ≤ z < 10, chosen by
//       placement) with the coherent samples: weak, the refinement clear,
//       `weakMoves` non-empty; (b) the same features, unrelated pips:
//       refused, the reason exactly `incoherent` of the plan's own numbers
//       (`find`, the snapped delta, the region, `refine`, written out
//       here); (c) the lag at full weight (control: chosen by confidence),
//       unrelated pips: refused the same way; (d) (a)'s features and no
//       samples at all: weak, the refinement nil; (g) (a) with the mover's
//       samples all 0: refused, exactly `unconfirmed` (the fail-closed
//       ruling); (e) the anchor playing [0, 9 s) and the mover [0, 6 s) of
//       a file 500 frames on, 5,000 frames from its placement: the whole
//       files choose by confidence, the played spans meet for 1 s once
//       moved (control: the played region under 2 s), and the refinement
//       runs over the files' overlap and is clear; with unrelated pips,
//       refused as written; (f) two 188-frame files sharing the outermost
//       scored lag (63, a 125-frame overlap), the mover's zero the first in
//       0, 200, … ticks whose snapped played overlap is under 2 s: the
//       refinement runs over the outward-rounded files' overlap (≥ 16,000
//       samples) and is clear (control: the lag 63 ±0.5).
//   P21 the region chosen by the features (SY-32) through `plan`: a 54 s
//       pips pair (seed 401), the anchor 1.204 s later (P17's construction),
//       the mover's [12 s, 42 s) replaced by seeded noise (LCG 402) and its
//       features those of the edited samples. (a) the noise at 0.1 and (b) at
//       −60 dBFS (room tone): confident, the refinement clear, |offset −
//       truth| ≤ 75 ticks, the region printed (control, an instrument
//       failure otherwise: PHAT over the old centred 30 s of the same overlap
//       is not clear); (c) (a) with the anchor's samples unrelated pips (seed
//       403): refused, exactly `incoherent` of the plan's own numbers.
//   P23 a file under one frame (SY-31): 40 ms of a 1 kHz tone at −6 dBFS, 16
//       kHz, written by `AVAudioFile` under the temporary directory's
//       `framejob-sync-probe-<pid>/` (removed after) and passed through the
//       product's `writeSyncFeatures`: the marker present, no frames,
//       samples whose `frameCount` is 0, current; control: 1 s of the same
//       tone gives `frameCount(samples:)` frames.
//   P24 `SyncResampler` (SY-34): an impulse at 48,000, 44,100, 16,000 and
//       44,099.5 Hz (not whole, its phase rounded)
//       lands (the response's first moment) within ±0.05 output sample of
//       8000·t; ⌈N·8000/rate⌉ outputs; the whole input against pieces of 1,
//       777 and 4,096 samples byte-identical; at 8,000 Hz the identity.
//   P25 (only with the arguments `determinism <dir>`, and then alone; the
//       proof's `--determinism`, built -O whole-module): #305's measurement.
//       Each of <dir>'s D1–D4 read by three arms, each twice, interleaved —
//       T, the pass as it stood before SY-34 (the reader converting to 8 kHz,
//       kept here for good), P the product's `writeSyncFeatures`, N the
//       native-rate decode — and each pair compared byte for byte (the
//       samples that differ, their clusters, the largest |Δ|); scored as
//       SY-34 rules: P and N identical on all four and P's wall ≤ 1.5× T's on
//       D1 and D2 (fastest of two each); with the cache below version 3, P
//       on D3 and D4 only.
import AVFoundation
import Foundation

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String, instrument: Bool = false) {
    rows.append(["id": id, "pass": pass && !instrument, "detail": String(detail.prefix(1500)),
                 "instrument": instrument])
}

/// The answer, `{"rows": [...]}` on stdout, and the end of the process.
func emit() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func signed() -> Float { Float(next() * 2 - 1) }
}

let width = SyncFeatures.coefficients

func randomArray(_ count: Int, seed: UInt64) -> [Float] {
    var lcg = LCG(state: seed)
    return (0..<count).map { _ in lcg.signed() }
}

/// `count` frames of seeded noise, frame-major.
func randomFrames(_ count: Int, seed: UInt64) -> [Float] { randomArray(count * width, seed: seed) }

/// `mover[m] = anchor[m + shift]` frame by frame where that exists, fresh
/// noise elsewhere: the mover's sound at frame m is the anchor's at m + shift,
/// so lag = shift.
func shiftedFrames(_ anchor: [Float], by shift: Int, count: Int, seed: UInt64) -> [Float] {
    var lcg = LCG(state: seed)
    let frames = anchor.count / width
    var out: [Float] = []
    out.reserveCapacity(count * width)
    for m in 0..<count {
        let a = m + shift
        for k in 0..<width {
            out.append(a >= 0 && a < frames ? anchor[a * width + k] : lcg.signed())
        }
    }
    return out
}

let fps = Fps(num: 30, den: 1)
let bucket: Ticks = 6000
let step: Ticks = SyncFeatures.frameTicks

/// A reading whose in point is `(start − zero)·speed`, so that its zero is
/// `start − in/speed` as `AudioSync.read` writes it.
func reading(
    _ clip: UInt32, track: Int, start: Ticks, end: Ticks, zero: Ticks, video: Bool = false,
    samples: [Int16] = [], features: [Float] = [], speech: [Bool]? = nil,
    neighbours: [AudioSync.Neighbour] = [], speed: Double = 1
) -> AudioSync.Reading {
    AudioSync.Reading(
        clip: clip, media: clip + 100, trackIndex: track, start: start, end: end, zero: zero,
        hasVideo: video, samples: samples, features: features, speech: speech,
        neighbours: neighbours,
        speed: speed, sourceIn: Ticks((Double(start - zero) * speed).rounded()))
}

/// A smooth signal: Gaussian bumps (σ `sigma` buckets) at seeded moments.
struct Bumps {
    var at: [Double] = []
    var amp: [Double] = []
    var sigma = 2.0
    init(seed: UInt64, length: Double, sigma: Double = 2) {
        var lcg = LCG(state: seed)
        var t = 0.0
        while t < length {
            t += 4 + lcg.next() * 16
            at.append(t)
            amp.append(0.2 + lcg.next())
        }
        self.sigma = sigma
    }
    /// Samples `f(m·k + c)` for m in 0..<count.
    func sample(count: Int, k: Double, c: Double) -> [Float] {
        var out = [Double](repeating: 0, count: count)
        let reach = sigma == 2 ? 12 : Int(6 * sigma / k) + 1
        for (t, a) in zip(at, amp) {
            let centre = (t - c) / k
            let low = max(0, Int(centre) - reach)
            let high = min(count - 1, Int(centre) + reach)
            guard low <= high else { continue }
            for m in low...high {
                let d = Double(m) * k + c - t
                out[m] += a * exp(-d * d / (2 * sigma * sigma))
            }
        }
        let mean = out.reduce(0, +) / Double(max(count, 1))
        return out.map { Float($0 - mean) }
    }
}

/// Smooth features: coefficient q is its own `Bumps` (σ 6 buckets, seed
/// `seed + q`) read at bucket time `f·1.6·k + c` for frame f, so the lag at
/// anchor frame a is `a − (a − c/1.6)/k` frames and the drift (1 − 1/k).
func featureBumps(seed: UInt64, length: Double, count: Int, k: Double, c: Double) -> [Float] {
    let perFrame = Double(step) / Double(bucket)
    let columns = (0..<width).map {
        Bumps(seed: seed + UInt64($0), length: length, sigma: 6)
            .sample(count: count, k: perFrame * k, c: c)
    }
    var out = [Float](repeating: 0, count: count * width)
    for f in 0..<count {
        for q in 0..<width { out[f * width + q] = columns[q][f] }
    }
    return out
}

func describe(_ plan: AudioSync.Plan) -> String {
    switch plan {
    case .refused(let problems):
        return "refused: " + problems.map { $0.description }.joined(separator: " | ")
    case .planned(let anchor, let synced, let ops):
        let parts = synced.map {
            "clip \($0.clip) lag \($0.lag) delta \($0.delta) start \($0.start) "
                + "z \(String(format: "%.2f", $0.confidence)) \($0.search.rawValue)/"
                + "\($0.chosenBy.rawValue) on \($0.matchedOn.rawValue) trimmed \($0.trimmed)"
        }
        return "planned: anchor \(anchor), \(parts.joined(separator: "; ")), \(ops.count) op(s)"
    }
}

func refusal(_ plan: AudioSync.Plan) -> String? {
    if case .refused(let problems) = plan {
        return problems.map { $0.description }.joined(separator: " ")
    }
    return nil
}

// MARK: - P19 the cost (only with the arguments `cost <dir>`)

/// This thread's CPU seconds.
func threadCPU() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
}

/// SY-22's budget: one hour of pips written as the cache would hold it, then
/// timed as `sync_audio` spends it — both files' loads, then `plan`.
func runCost(_ dir: URL) {
    let manager = FileManager.default
    try? manager.removeItem(at: dir)
    defer { try? manager.removeItem(at: dir) }
    let cache = dir.appendingPathComponent("cache", isDirectory: true)
    var notes: [String] = []
    var instrument = false
    let count = 3600 * 8000
    let k = 1 + 100e-6
    let delay = 9632.0
    let made = Date()
    do {
        let pips = Pips(seed: 301, samples: Double(count) * k + delay + 1000)
        let stamp = MediaImporter.CacheStamp(
            size: 0, modified: 0, duration: Ticks(count) * AudioSyncPHAT.sampleTicks, width: 0,
            height: 0, hasVideo: false, hasAudio: true, thumbnailHeight: 0, maxThumbnails: 0,
            peakBucketsPerSecond: 100)
        for id: UInt32 in [1, 2] {
            let samples = id == 1
                ? pcm(pips.sample(count: count), noise: 0.003, seed: 302)
                : pcm(pips.sample(count: count, k: k, c: delay), gain: 0.5, noise: 0.003, seed: 303)
            let frames = SyncFeatures.frames(floats(samples))
            let bin = MediaImporter.syncFeaturesURL(for: id, in: cache)
            try? manager.createDirectory(
                at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
            let wroteBin = (try? frames.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: bin))
                != nil
            let wrotePCM = (try? samples.map { $0.littleEndian }
                .withUnsafeBufferPointer { Data(buffer: $0) }
                .write(to: MediaImporter.syncSamplesURL(for: id, in: cache))) != nil
            let wroteMarker = MediaImporter.writeStamp(
                MediaImporter.SyncFeaturesStamp(stamp),
                to: MediaImporter.syncFeaturesMarkerURL(for: id, in: cache))
            if !(wroteBin && wrotePCM && wroteMarker) { instrument = true }
        }
    }
    notes.append("fixture made in \(String(format: "%.1f", Date().timeIntervalSince(made))) s "
        + "(untimed)")

    let cpu0 = threadCPU()
    let wall0 = Date()
    let anchorFeatures = MediaImporter.loadSyncFeatures(for: 1, in: cache) ?? []
    let anchorSamples = MediaImporter.loadSyncSamples(for: 1, in: cache) ?? []
    let moverFeatures = MediaImporter.loadSyncFeatures(for: 2, in: cache) ?? []
    let moverSamples = MediaImporter.loadSyncSamples(for: 2, in: cache) ?? []
    let cpu1 = threadCPU()
    let wall1 = Date()
    if anchorSamples.count != count || moverSamples.count != count { instrument = true }
    let end = Ticks(count) * AudioSyncPHAT.sampleTicks
    let input = AudioSync.Input(
        readings: [
            reading(1, track: 0, start: 0, end: end, zero: 0, video: true, samples: anchorSamples,
                    features: anchorFeatures),
            reading(2, track: 1, start: 0, end: end, zero: 0, samples: moverSamples,
                    features: moverFeatures),
        ], problems: [], anchor: nil, fps: fps)
    let plan = AudioSync.plan(input)
    let cpu2 = threadCPU()
    let wall2 = Date()
    let total = cpu2 - cpu0
    notes.append(
        "load both files: CPU \(String(format: "%.3f", cpu1 - cpu0)) s, wall "
            + "\(String(format: "%.3f", wall1.timeIntervalSince(wall0))) s; plan: CPU "
            + "\(String(format: "%.3f", cpu2 - cpu1)) s, wall "
            + "\(String(format: "%.3f", wall2.timeIntervalSince(wall1))) s; total CPU "
            + "\(String(format: "%.3f", total)) s (want ≤ 1.5)")
    if case .planned(_, let synced, _) = plan, let one = synced.first,
       case .measured(let drift) = one.drift {
        let control = one.chosenBy == .confidence && drift.on == .phat && drift.windows == 64
            && one.refinement?.clear == true
        if !control { instrument = true }
        notes.append(
            "z \(String(format: "%.2f", one.confidence)) by \(one.chosenBy.rawValue), drift "
                + "\(String(format: "%.3f", drift.ppm)) ppm (true "
                + "\(String(format: "%.3f", (1 - 1 / k) * 1e6))) on \(drift.on.rawValue) over "
                + "\(drift.windows) windows, \(describe(one.refinement)) (control: confident, "
                + "phat, 64 windows, clear: \(control))")
        // Drift again, with the shared setup and without it.
        let coarse = ReelTime.snapToFrame(one.coarseLag, fps: fps)
        let overlap = Int(max(0, coarse) / SyncFeatures.frameTicks)
            ..< Int(min(end, end + coarse) / SyncFeatures.frameTicks)
        let lag = Double(one.coarseLag) / Double(SyncFeatures.frameTicks)
        for (name, fft) in [("shared setup", AudioSyncPHAT.FFT(log2n: AudioSyncPHAT.planLog2n)),
                            ("a setup per call", nil)] {
            let began = threadCPU()
            _ = AudioSyncMatch.drift(
                anchor: anchorFeatures, mover: moverFeatures, anchorSpeech: nil,
                moverSpeech: nil, anchorSamples: anchorSamples, moverSamples: moverSamples,
                anchorSpeed: 1, moverSpeed: 1, lag: lag, overlap: overlap, fft: fft)
            notes.append("drift alone, \(name): CPU \(String(format: "%.3f", threadCPU() - began)) s")
        }
    } else {
        instrument = true
        notes.append("plan: \(describe(plan))")
    }
    var load = [Double](repeating: 0, count: 3)
    getloadavg(&load, 3)
    notes.append("host load \(load.map { String(format: "%.2f", $0) }.joined(separator: " "))")
    row("P19", total <= 1.5, notes.joined(separator: "; "), instrument: instrument)
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "cost" {
    runCost(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
    emit()
}

// MARK: - P25 the cache pass's determinism (only with the arguments `determinism <dir>`)

/// One reader pass over `url`'s first audio track with `settings` as its
/// output, every buffer's floats handed to `body` with the rate the buffer
/// says; whether the reader ended `.completed`, and its wall seconds.
func readAudio(
    _ url: URL, settings: [String: Any], _ body: (UnsafeBufferPointer<Float>, Double) -> Void
) -> (completed: Bool, wall: Double) {
    let began = Date()
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first,
          let reader = try? AVAssetReader(asset: asset)
    else { return (false, 0) }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return (false, 0) }
    reader.add(output)
    guard reader.startReading() else { return (false, 0) }
    while let sample = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let byteCount = CMBlockBufferGetDataLength(block)
        guard byteCount >= 4 else { continue }
        var rate = 0.0
        if let format = CMSampleBufferGetFormatDescription(sample),
           let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
            rate = basic.pointee.mSampleRate
        }
        var samples = [Float](repeating: 0, count: byteCount / 4)
        let copied = samples.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount,
                                              destination: base)
        }
        guard copied == noErr else { continue }
        samples.withUnsafeBufferPointer { body($0, rate) }
    }
    let status = reader.status
    reader.cancelReading()
    return (status == .completed, Date().timeIntervalSince(began))
}

/// The pass's output settings (`writeSyncFeatures`' before SY-34), with
/// `AVSampleRateKey` only when `rate` is given.
func syncSettings(rate: Double?) -> [String: Any] {
    var settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    ]
    if let rate { settings[AVSampleRateKey] = rate }
    return settings
}

/// How two files differ, as arrays of `T`: the elements that differ, the
/// clusters they fall in (a new one more than 1,000 elements after the
/// last), and the largest |Δ|; "identical" when the bytes are.
func compare<T: BinaryFloatingPoint>(_ a: URL, _ b: URL, as type: T.Type) -> (Bool, String) {
    compareValues(a, b, stride: MemoryLayout<T>.size) { raw, index in
        Double(raw.load(fromByteOffset: index * MemoryLayout<T>.size, as: T.self))
    }
}

func compareInt16(_ a: URL, _ b: URL) -> (Bool, String) {
    compareValues(a, b, stride: 2) { raw, index in
        Double(Int16(littleEndian: raw.load(fromByteOffset: index * 2, as: Int16.self)))
    }
}

func compareValues(
    _ a: URL, _ b: URL, stride: Int, value: (UnsafeRawBufferPointer, Int) -> Double
) -> (Bool, String) {
    guard let x = try? Data(contentsOf: a, options: .alwaysMapped),
          let y = try? Data(contentsOf: b, options: .alwaysMapped)
    else { return (false, "a file is missing") }
    if x == y { return (true, "identical (\(x.count) bytes)") }
    var difference = Difference()
    x.withUnsafeBytes { xr in
        y.withUnsafeBytes { yr in
            for index in 0..<(min(x.count, y.count) / stride) {
                difference.note(index, value(xr, index), value(yr, index))
            }
        }
    }
    return (false, "\(x.count) and \(y.count) bytes, " + difference.said)
}

/// How two float streams differ: `differ` elements, in `clusters` (a new
/// one more than 1,000 elements after the last), the largest |Δ|.
struct Difference {
    var differing = 0
    var clusters = 0
    var first: [Int] = []
    var largest = 0.0
    private var last: Int?

    mutating func note(_ index: Int, _ u: Double, _ v: Double) {
        guard u != v else { return }
        differing += 1
        if last.map({ index - $0 > 1000 }) ?? true {
            clusters += 1
            if first.count < 3 { first.append(index) }
        }
        last = index
        largest = max(largest, abs(u - v))
    }

    var said: String {
        "\(differing) elements differ in \(clusters) clusters (first at \(first)), largest |Δ| "
            + String(format: "%g", largest)
    }
}

/// #305's measurement (SY-34): each file in `dir` (`D1.m4a`, `D2.m4a`,
/// `D3.wav`, `D4.wav`) through three arms, each twice, the arms interleaved
/// (T, P, N, then again) so a drifting host load falls on them alike: T,
/// today's arm kept here for good (8 kHz from the reader into a
/// `SyncFeatures.Extractor`, the same int16 rounding, written as the pass
/// writes); P the product's `writeSyncFeatures`; N the native-rate decode,
/// its first pass held in memory and the second compared as it comes. Each
/// pair is compared byte for byte; the walls are each arm's whole pass.
func runDeterminism(_ dir: URL) {
    let manager = FileManager.default
    let scratch = dir.appendingPathComponent("passes", isDirectory: true)
    try? manager.removeItem(at: scratch)
    try? manager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: scratch) }
    let shipped = MediaImporter.syncFeaturesVersion >= 3
    var good = true
    var instrument = false
    var notes: [String] = []
    var walls: [String: (t: Double, p: Double)] = [:]
    func seconds(_ values: [Double]) -> String {
        values.map { String(format: "%.2f", $0) }.joined(separator: ", ")
    }
    let files = [("D1", "D1.m4a"), ("D2", "D2.m4a"), ("D3", "D3.wav"), ("D4", "D4.wav")]
    for (name, file) in files {
        let url = dir.appendingPathComponent(file)
        let media = MediaSnapshot(id: 1, path: url.path, kind: .audio, hasVideo: false,
                                  hasAudio: true)
        guard manager.fileExists(atPath: url.path),
              let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url)
        else {
            instrument = true
            notes.append("\(name): \(file) is missing")
            continue
        }
        var tWalls: [Double] = []
        var pWalls: [Double] = []
        var nWalls: [Double] = []
        var rates: Set<Double> = []
        var native: [Float] = []
        var nDifference = Difference()
        var nCounts: [Int] = []
        var caches: [URL] = []
        for pass in 1...2 {
            // T: today's arm.
            let tBegan = Date()
            let extractor = SyncFeatures.Extractor()
            var pcm: [Int16] = []
            let read = readAudio(url, settings: syncSettings(rate: Double(SyncFeatures.sampleRate))) {
                samples, _ in
                extractor.feed(samples)
                for x in samples {
                    pcm.append(x.isFinite ? Int16((min(1, max(-1, x)) * 32767).rounded()) : 0)
                }
            }
            let frames = extractor.finish()
            if !read.completed { instrument = true }
            let tCache = scratch.appendingPathComponent("\(name)-T\(pass)", isDirectory: true)
            try? manager.createDirectory(at: tCache, withIntermediateDirectories: true)
            try? frames.withUnsafeBufferPointer { Data(buffer: $0) }
                .write(to: tCache.appendingPathComponent("T.bin"), options: .atomic)
            try? pcm.map { $0.littleEndian }.withUnsafeBufferPointer { Data(buffer: $0) }
                .write(to: tCache.appendingPathComponent("T.pcm"), options: .atomic)
            tWalls.append(Date().timeIntervalSince(tBegan))
            // P: the product's pass, into its own cache.
            let pBegan = Date()
            let asset = AVURLAsset(url: url)
            let cache = scratch.appendingPathComponent("\(name)-P\(pass)", isDirectory: true)
            if let track = asset.tracks(withMediaType: .audio).first {
                MediaImporter.writeSyncFeatures(
                    for: media, asset: asset, track: track, stamp: stamp, into: cache, pass: nil)
            } else {
                instrument = true
            }
            pWalls.append(Date().timeIntervalSince(pBegan))
            caches.append(cache)
            // N: the native-rate decode.
            var index = 0
            let nRead = readAudio(url, settings: syncSettings(rate: nil)) { samples, rate in
                rates.insert(rate)
                if pass == 1 {
                    native.append(contentsOf: samples)
                } else {
                    for x in samples {
                        let u = index < native.count ? Double(native[index]) : .nan
                        nDifference.note(index, u, Double(x))
                        index += 1
                    }
                }
            }
            if !nRead.completed { instrument = true }
            nWalls.append(nRead.wall)
            nCounts.append(pass == 1 ? native.count : index)
        }
        native = []
        let nSame = nDifference.differing == 0 && nCounts[0] == nCounts[1]
        let t = (compareInt16(scratch.appendingPathComponent("\(name)-T1/T.pcm"),
                              scratch.appendingPathComponent("\(name)-T2/T.pcm")),
                 compare(scratch.appendingPathComponent("\(name)-T1/T.bin"),
                         scratch.appendingPathComponent("\(name)-T2/T.bin"), as: Float.self))
        let p = (compareInt16(MediaImporter.syncSamplesURL(for: 1, in: caches[0]),
                              MediaImporter.syncSamplesURL(for: 1, in: caches[1])),
                 compare(MediaImporter.syncFeaturesURL(for: 1, in: caches[0]),
                         MediaImporter.syncFeaturesURL(for: 1, in: caches[1]), as: Float.self))
        for pass in 1...2 {
            try? manager.removeItem(at: scratch.appendingPathComponent("\(name)-T\(pass)"))
            try? manager.removeItem(at: caches[pass - 1])
        }
        walls[name] = (tWalls.min() ?? 0, pWalls.min() ?? 0)
        // Scored as SY-34 rules: shipped, P identical on every file and the
        // native decode too; not shipped, P on the PCM sources D3 and D4.
        let scored = shipped || name == "D3" || name == "D4"
        if scored && !(p.0.0 && p.1.0) { good = false }
        if shipped && !nSame { good = false }
        notes.append(
            "\(name) (\(file)): T walls \(seconds(tWalls)) s, .pcm \(t.0.1), .bin \(t.1.1); "
                + "P walls \(seconds(pWalls)) s, .pcm \(p.0.1), .bin \(p.1.1); N walls "
                + "\(seconds(nWalls)) s at \(rates.sorted().map { String(format: "%g", $0) }) Hz, "
                + "\(nCounts) samples, "
                + (nSame ? "identical" : nDifference.said))
    }
    for name in ["D1", "D2"] {
        guard let w = walls[name] else { continue }
        let ratio = w.t > 0 ? w.p / w.t : .infinity
        if shipped && !(ratio <= 1.5) { good = false }
        notes.append("\(name) P/T wall \(String(format: "%.3f", ratio)) (fastest of two each; "
            + "want ≤ 1.5 when shipped)")
    }
    notes.append("the path shipped (cache version \(MediaImporter.syncFeaturesVersion)): \(shipped)")
    // The whole of it on stderr too: the row's detail is cut at 1,500.
    for note in notes { FileHandle.standardError.write(Data(("P25: " + note + "\n").utf8)) }
    row("P25", good, notes.joined(separator: "; "), instrument: instrument)
}

if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "determinism" {
    runDeterminism(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
    emit()
}

// MARK: - P1 delta arithmetic

do {
    let anchor = randomFrames(3000, seed: 11)
    // (zeroA, startA, zeroN, startN, shift k frames, expected delta) — each
    // worked by hand: zeroA − zeroN + k·9600, rounded to the nearest 20 000.
    let table: [(Ticks, Ticks, Ticks, Ticks, Int, Ticks)] = [
        (600_000, 600_000, 0, 0, 250, 3_000_000),  // 600 000 + 2 400 000, on a frame
        (600_000, 600_000, 0, 0, 251, 3_000_000),  // 3 009 600 = frame 150.48 → 150
        (6_000_000, 6_000_000, 0, 0, -250, 3_600_000),  // 6 000 000 − 2 400 000
        (0, 0, 600_000, 1_200_000, 400, 3_240_000),  // a trimmed mover: −600 000 + 3 840 000
        (0, 0, 0, 0, 33, 320_000),  // 316 800 = frame 15.84 → 16
    ]
    var good = true
    var notes: [String] = []
    for (index, entry) in table.enumerated() {
        let (zeroA, startA, zeroN, startN, shift, expected) = entry
        let mover = shiftedFrames(anchor, by: shift, count: 3000, seed: 100 + UInt64(index))
        let input = AudioSync.Input(
            readings: [
                reading(1, track: 0, start: startA, end: startA + 3000 * step, zero: zeroA,
                        video: true, features: anchor),
                reading(2, track: 1, start: startN, end: startN + 2500 * step, zero: zeroN,
                        features: mover),
            ], problems: [], anchor: nil, fps: fps)
        let plan = AudioSync.plan(input)
        guard case .planned(let anchorClip, let synced, let ops) = plan, let one = synced.first
        else {
            good = false
            notes.append("case \(index): \(describe(plan))")
            continue
        }
        let lagOK = abs(one.lag - Ticks(shift) * step) <= 960
        let ok = anchorClip == 1 && one.clip == 2 && one.delta == expected
            && one.start == startN + expected && lagOK && ops.count == (expected != 0 ? 1 : 0)
            && one.trimmed == 0
        if !ok { good = false }
        notes.append(
            "case \(index): k \(shift) delta \(one.delta) (want \(expected)) start \(one.start) "
                + "lag \(one.lag) (want \(Ticks(shift) * step) ±960) z "
                + "\(String(format: "%.1f", one.confidence)) \(one.search.rawValue)")
    }
    row("P1", good, notes.joined(separator: "; "))
}

// MARK: - P2 the anchor rule

do {
    let late = reading(3, track: 0, start: 600_000, end: 6_000_000, zero: 0, video: true)
    let early = reading(5, track: 1, start: 0, end: 6_000_000, zero: 0)
    let lateSound = reading(3, track: 0, start: 600_000, end: 6_000_000, zero: 0)
    let rearTie = reading(5, track: 1, start: 0, end: 6_000_000, zero: 0)
    let frontTie = reading(3, track: 2, start: 0, end: 6_000_000, zero: 0)
    let idHigh = reading(7, track: 1, start: 0, end: 6_000_000, zero: 0)
    let idLow = reading(4, track: 1, start: 0, end: 6_000_000, zero: 0)
    let cases: [(String, UInt32?, UInt32?)] = [
        ("pictures first", AudioSync.chooseAnchor([early, late], named: nil)?.clip, 3),
        ("earliest start", AudioSync.chooseAnchor([lateSound, early], named: nil)?.clip, 5),
        ("rearmost track", AudioSync.chooseAnchor([frontTie, rearTie], named: nil)?.clip, 5),
        ("lowest id", AudioSync.chooseAnchor([idHigh, idLow], named: nil)?.clip, 4),
        ("named", AudioSync.chooseAnchor([early, late], named: 5)?.clip, 5),
        ("named stranger", AudioSync.chooseAnchor([early, late], named: 9)?.clip, nil),
    ]
    let failed = cases.filter { $0.1 != $0.2 }
    row(
        "P2", failed.isEmpty,
        cases.map { "\($0.0): \($0.1.map(String.init) ?? "nil") (want "
            + "\($0.2.map(String.init) ?? "nil"))" }.joined(separator: "; "))
}

// MARK: - P3 a known lag through the extractor

/// `seconds` of 8 kHz bursts — noise or a tone, 30–400 ms, gaps of 50–600
/// ms — over a floor near −66 dBFS (the proof's `source_samples`, smaller).
func bursts(seconds: Int, seed: UInt64) -> [Float] {
    var lcg = LCG(state: seed)
    let rate = SyncFeatures.sampleRate
    let total = rate * seconds
    var out = (0..<total).map { _ in Float(lcg.signed()) * 0.0005 }
    var n = Int((0.05 + lcg.next() * 0.55) * Double(rate))
    while n < total {
        let length = Int((0.03 + lcg.next() * 0.37) * Double(rate))
        let level = 0.1 + lcg.next() * 0.7
        let tone = lcg.next() < 0.5
        let freq = 200 + lcg.next() * 1800
        for i in 0..<min(length, total - n) {
            let env = level * min(1, Double(i) / 32) * (1 - 0.6 * Double(i) / Double(length))
            let value = tone ? sin(2 * Double.pi * freq * Double(i) / Double(rate)) : lcg.next() * 2 - 1
            out[n + i] += Float(env * value)
        }
        n += length + Int((0.05 + lcg.next() * 0.55) * Double(rate))
    }
    return out
}

do {
    // The mover is the same sound 313 frames (40 064 samples) later, 9 dB
    // down, with noise at −60 dBFS: its frame m is the anchor's m − 313.
    let source = bursts(seconds: 30, seed: 31)
    var lcg = LCG(state: 32)
    let delay = 313 * SyncFeatures.hop
    let later = (0..<(source.count - 20_000)).map { n -> Float in
        let a = n - delay
        return (a >= 0 ? source[a] * 0.3548 : 0) + Float(lcg.signed()) * 0.001
    }
    let anchorFrames = SyncFeatures.frames(source)
    let moverFrames = SyncFeatures.frames(later)
    let result = AudioSyncMatch.search(
        anchor: anchorFrames, mover: moverFrames, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: 10_000)
    let chosen = result.flatMap { AudioSync.choose($0) }
    let lagOK = chosen.map { abs($0.0.lag - -313) <= 0.5 && $0.1 == .confidence } ?? false
    row(
        "P3", lagOK,
        "through SyncFeatures (\(anchorFrames.count / width) and "
            + "\(moverFrames.count / width) frames): lag "
            + "\(chosen.map { String(format: "%.3f", $0.0.lag) } ?? "nil") (want −313 ±0.5), z "
            + "\(chosen.map { String(format: "%.2f", $0.0.z) } ?? "nil"), chosen by "
            + "\(chosen.map { $0.1.rawValue } ?? "nothing"); candidates "
            + "\(result.map { $0.candidates.map { String(format: "%.1f@%.2f", $0.lag, $0.z) } } ?? [])")
}

// MARK: - P4 the refusals a search makes

do {
    var good = true
    var notes: [String] = []
    // The mover sits 5,000 frames from the anchor, beyond every lag the two
    // can be compared at, so no peak is near its placement: only the
    // confident rule can choose, and white noise never reaches it. (Near a
    // placement, white noise CAN reach plausibleZ: z is taken over every lag,
    // and the short-overlap lags at the ends lower the sd; see P11.)
    let anchor = randomFrames(1500, seed: 41)
    let unrelated = randomFrames(1500, seed: 42)
    let plan = AudioSync.plan(
        AudioSync.Input(
            readings: [
                reading(1, track: 0, start: 0, end: 1500 * step, zero: 0, video: true,
                        features: anchor),
                reading(2, track: 1, start: 5000 * step, end: 6500 * step, zero: 5000 * step,
                        features: unrelated),
            ], problems: [], anchor: nil, fps: fps))
    let said = refusal(plan) ?? ""
    let rule = " A match applies on its own at confidence ≥ 10 and 1.5 above the next "
        + "candidate; one ≥ 4 within 3 s of where clip 2 sits now is offered as a weak match. "
        + "Either counts only when the two waveforms line up there (a clear GCC-PHAT peak of "
        + "at least 15 within 48 ms)."
    let unrelatedOK = said.hasPrefix(
        "no matching sound found between clip 1 and clip 2: in the played windows, moving clip 2 "
            + "by ") && said.hasSuffix(rule) && said.contains("(confidence ")
        && !said.contains("in the whole files")
    if !unrelatedOK { good = false }
    notes.append("unrelated 1,500 frames: \(describe(plan))")

    let short = AudioSync.plan(
        AudioSync.Input(
            readings: [
                reading(1, track: 0, start: 0, end: 100 * step, zero: 0, video: true,
                        features: randomFrames(100, seed: 43)),
                reading(2, track: 1, start: 0, end: 100 * step, zero: 0,
                        features: randomFrames(100, seed: 44)),
            ], problems: [], anchor: nil, fps: fps))
    if refusal(short) != "no matching sound found between clip 1 and clip 2: too little room to "
        + "compare their sound." {
        good = false
    }
    notes.append("two 100-frame files: \(describe(short))")
    row("P4", good, notes.joined(separator: "; "))
}

// MARK: - P5 drift

/// SY-21's drift on features alone (no samples: the features' line).
func featureDrift(_ anchor: [Float], _ mover: [Float], lag: Double, overlap: Range<Int>)
    -> AudioSyncMatch.DriftAnswer {
    AudioSyncMatch.drift(
        anchor: anchor, mover: mover, anchorSpeech: nil, moverSpeech: nil, anchorSamples: [],
        moverSamples: [], anchorSpeed: 1, moverSpeed: 1, lag: lag, overlap: overlap)
}

do {
    let length = 16_500.0
    let anchor = featureBumps(seed: 51, length: length, count: 10_000, k: 1, c: 0)
    let minimum = AudioSyncMatch.driftMinimumOverlapFrames
    // (name, ppm asked, offset c in buckets, overlap in frames, the mover's
    // frames made seeded noise): the mover's frame m is the anchor's at
    // m·k + c/1.6, so the coarse lag is c/1.6 frames and the drift is
    // (1 − 1/k)·1e6.
    let cases: [(String, Double, Double, Range<Int>, Range<Int>?)] = [
        ("+200 ppm over 9,325 frames", 200, 80, 50..<9_375, nil),
        ("−150 ppm over 9,325 frames", -150, 80, 50..<9_375, nil),
        ("0 ppm over 9,325 frames", 0, 80, 50..<9_375, nil),
        ("+100 ppm at exactly the minimum", 100, 1600, 1000..<(1000 + minimum), nil),
        ("+200 ppm, the mover's frames 4,000–7,000 noise", 200, 80, 50..<9_375, 4000..<7000),
    ]
    var good = true
    var notes: [String] = []
    for (name, asked, c, overlap, noise) in cases {
        let k = 1 + asked * 1e-6
        var mover = featureBumps(seed: 51, length: length, count: 10_000, k: k, c: c)
        var wholly = 0
        if let noise {
            var lcg = LCG(state: 52)
            for index in (noise.lowerBound * width)..<(noise.upperBound * width) {
                mover[index] = lcg.signed()
            }
            // The control: windows whose mover frames are noise throughout.
            let lag = Int((c / 1.6).rounded())
            let window = AudioSyncMatch.driftWindowFrames
            let reach = overlap.count - window
            let step = max(AudioSyncMatch.driftWindowStepFrames, (reach + 62) / 63)
            for start in stride(from: overlap.lowerBound, through: overlap.upperBound - window,
                                by: step)
            where start - lag >= noise.lowerBound && start - lag + window <= noise.upperBound {
                wholly += 1
            }
            if wholly < 1 { good = false }
        }
        let want = (1 - 1 / k) * 1e6
        let answer = featureDrift(anchor, mover, lag: c / 1.6, overlap: overlap)
        guard case .measured(let drift) = answer else {
            good = false
            notes.append("\(name): \(answer)")
            continue
        }
        let overlapMs = Double(overlap.count) * 128 / 8
        let wantMs = want * 1e-6 * overlapMs
        let ok = abs(drift.ppm - want) <= 5 && abs(drift.milliseconds - wantMs) <= 5e-6 * overlapMs
            && drift.on == .features
        if !ok { good = false }
        notes.append(
            "\(name): \(String(format: "%.2f", drift.ppm)) ppm (want "
                + "\(String(format: "%.2f", want)) ±5), \(String(format: "%.3f", drift.milliseconds)) "
                + "ms (want \(String(format: "%.3f", wantMs))), ±"
                + "\(String(format: "%.3f", drift.errorMilliseconds)) ms over \(drift.windows) windows "
                + "on \(drift.on.rawValue)"
                + (noise == nil ? "" : " (\(wholly) windows wholly noise, want ≥ 1)"))
    }
    let short = featureDrift(
        anchor, featureBumps(seed: 51, length: length, count: 10_000, k: 1.0001, c: 1600),
        lag: 1000, overlap: 1000..<(1000 + minimum - 1))
    if short != .notMeasured("the two play together for under 60 s, too short to measure drift.") {
        good = false
    }
    notes.append("one frame under the minimum: \(short)")

    // Sound only in the mover's first 1,875 frames: the windows that match
    // sit at the overlap's start, too close together for a line.
    var early = featureBumps(seed: 51, length: length, count: 10_000, k: 1, c: 80)
    for index in (1875 * width)..<early.count { early[index] = 0 }
    let narrow = featureDrift(anchor, early, lag: 50, overlap: 50..<9_375)
    if narrow != .notMeasured(
        "the windows that matched cover too little of the overlap to measure drift.") {
        good = false
    }
    notes.append("sound in the first 1,875 of 9,375 frames only: \(narrow)")

    // A 4,000-frame overlap [1000, 5000) at lag 1000 whose mover sounds only
    // in its first and last 200 frames: windows [1000, 2250) and [3750, 5000)
    // hold them; the other starts (every 312 from 1312 to 3496) hold none.
    // The two windows' centres span 2,750 ≥ (4000 − 1250)/2, so the span
    // rule would pass: the note must be the count's.
    var ends = featureBumps(seed: 51, length: length, count: 10_000, k: 1, c: 1600)
    for f in 0..<10_000 where !(f < 200 || (f >= 3800 && f < 4000)) {
        for q in 0..<width { ends[f * width + q] = 0 }
    }
    let two = featureDrift(anchor, ends, lag: 1000, overlap: 1000..<5000)
    if two != .notMeasured("only 2 of the overlap's windows matched; drift needs at least 3.") {
        good = false
    }
    notes.append("only the two end windows can match: \(two)")

    // The same, with every frame but the two ends seeded noise in place of
    // silence: the eight noise windows fall under the window floor, so the
    // count is still the two ends'.
    var noisyEnds = ends
    var endNoise = LCG(state: 53)
    for f in 0..<10_000 where !(f < 200 || (f >= 3800 && f < 4000)) {
        for q in 0..<width { noisyEnds[f * width + q] = endNoise.signed() }
    }
    let noisyTwo = featureDrift(anchor, noisyEnds, lag: 1000, overlap: 1000..<5000)
    if noisyTwo != .notMeasured(
        "only 2 of the overlap's windows matched; drift needs at least 3.") {
        good = false
    }
    notes.append("only the two end windows can match, the rest seeded noise: \(noisyTwo)")
    row("P5", good, notes.joined(separator: "; "))
}

// MARK: - P6 refusals

do {
    let anchor = randomFrames(3000, seed: 61)
    var good = true
    var notes: [String] = []
    func expect(_ name: String, _ plan: AudioSync.Plan, refusedWith words: String?) {
        let said = refusal(plan)
        let ok = words.map { said?.contains($0) ?? false } ?? (said == nil)
        if !ok { good = false }
        notes.append("\(name): \(describe(plan))")
    }
    let late = shiftedFrames(anchor, by: 300, count: 3000, seed: 62)
    let far = shiftedFrames(anchor, by: 2000, count: 3000, seed: 64)

    // Never meeting: the anchor plays its first 2 s (125 frames), the mover
    // its first 1 s (under 125, so the whole files are searched), which lands
    // at 19.2 s.
    expect(
        "windows never meet",
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 0, end: 1_200_000, zero: 0, video: true,
                            features: anchor),
                    reading(2, track: 1, start: 0, end: 600_000, zero: 0, features: far),
                ], problems: [], anchor: nil, fps: fps)),
        refusedWith: "clip 2: once lined up it would not play at any moment clip 1 plays.")
    // Same track.
    expect(
        "same track",
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 600_000, end: 18_600_000, zero: 600_000,
                            video: true, features: anchor),
                    reading(2, track: 0, start: 20_000_000, end: 38_000_000, zero: 20_000_000,
                            features: late),
                ], problems: [], anchor: nil, fps: fps)),
        refusedWith: "clip 1 and clip 2 are on one track")
    // A neighbour: lag 300 frames (2 880 000) puts the mover on
    // [3 480 000, 21 480 000).
    func withNeighbour(_ start: Ticks, _ end: Ticks) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 600_000, end: 18_600_000, zero: 600_000,
                            video: true, features: anchor),
                    reading(2, track: 1, start: 0, end: 18_000_000, zero: 0, features: late,
                            neighbours: [AudioSync.Neighbour(clip: 99, start: start, end: end)]),
                ], problems: [], anchor: nil, fps: fps))
    }
    expect("neighbour overlapped", withNeighbour(20_000_000, 21_000_000),
           refusedWith: "clip 2: would overlap clip 99 on its track.")
    expect("neighbour abutting after", withNeighbour(21_480_000, 22_000_000), refusedWith: nil)
    expect("neighbour abutting before", withNeighbour(1_000_000, 3_480_000),
           refusedWith: nil)
    // Silence is the silent clip's own problem, named on it alone.
    let quiet = [Float](repeating: 0, count: 3000 * width)
    func silence(anchor first: [Float], mover second: [Float]) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 600_000, end: 18_600_000, zero: 600_000,
                            video: true, features: first),
                    reading(2, track: 1, start: 0, end: 18_000_000, zero: 0, features: second),
                    reading(3, track: 2, start: 0, end: 18_000_000, zero: 0, features: late),
                ], problems: [], anchor: nil, fps: fps))
    }
    let silentAnchor = silence(anchor: quiet, mover: late)
    if refusal(silentAnchor) != "clip 1: has no sound to line up by." {
        good = false
    }
    notes.append("silent anchor: \(describe(silentAnchor))")
    let silentMover = silence(anchor: anchor, mover: quiet)
    if refusal(silentMover) != "clip 2: has no sound to line up by." {
        good = false
    }
    notes.append("silent mover: \(describe(silentMover))")
    row("P6", good, notes.joined(separator: "; "))
}

// MARK: - P7 correction

/// "name(arg=value, …)" for each op, keys sorted.
func opList(_ ops: [ReelOp]) -> String {
    ops.map { op in
        op.name + "(" + op.args.keys.sorted().map { "\($0)=\(op.args[$0]!)" }
            .joined(separator: ", ") + ")"
    }.joined(separator: ", ")
}

do {
    // The anchor plays f(a) for a in [0, 8000) from 150 s (zeroA 90 000 000,
    // in 0). The mover's file is 20,000 buckets, silent for its first 12,000
    // (so the in point lies far ahead of the overlap, which is what makes the
    // pivot matter) and then f(m·k − 12000). It is trimmed to in I =
    // 3 000 000 (5 s) and starts at S = 3 000 000 (zero 0), d = 117 s.
    let anchorFeatures = featureBumps(seed: 171, length: 8_100, count: 5_000, k: 1, c: 0)
    let zeroA: Ticks = 90_000_000
    let c = -12_000.0
    let frame: Ticks = 20_000
    let anchor = reading(
        1, track: 0, start: zeroA, end: zeroA + 48_000_000, zero: zeroA, video: true,
        features: anchorFeatures)
    /// The mover's features: silent for its first 7,500 frames (12,000
    /// buckets), then the anchor's on the same drifted clock.
    func moverFeatures(_ k: Double) -> [Float] {
        var file = featureBumps(seed: 171, length: 8_100, count: 12_500, k: k, c: c)
        for index in 0..<(7_500 * width) { file[index] = 0 }
        return file
    }
    var good = true
    var notes: [String] = []
    // (name, k, the hand-worked delta, the centre-line delta, the ops' names
    // in SY-10's order). delta = snap(zeroA + 6000·c − S + I·k) =
    // snap(15 000 000 + 3 000 000·k):
    //   k 1.001: 18 003 000 = frame 900.15 → 18 000 000 (0.35 frame from an edge);
    //   k 0.999: 17 997 000 = frame 899.85 → 18 000 000 (0.35 frame from an edge).
    // The centre-line delta (aMid 4000, lag 4000 − 16000/k, zeroN 0):
    //   k 1.001: 114 000 000 − 95 904 096 = 18 095 904 → 18 100 000 (5 frames off);
    //   k 0.999: 114 000 000 − 96 096 096 = 17 903 904 → 17 900 000 (5 frames off).
    let cases: [(String, Double, Ticks, Ticks, [String])] = [
        ("+1000 ppm (lengthens)", 1.001, 18_000_000, 18_100_000, ["move_clip", "set_speed"]),
        ("−1000 ppm (shortens)", 0.999, 18_000_000, 17_900_000, ["set_speed", "move_clip"]),
    ]
    for (name, k, want, centreLine, order) in cases {
        let mover = reading(
            2, track: 1, start: 3_000_000, end: 120_000_000, zero: 0, features: moverFeatures(k))
        var coarse: AudioSync.Found?
        if case .found(let found) = AudioSync.find(
            anchor: anchor, anchorFrames: anchor.features, anchorSpeech: nil, mover: mover,
            moverFrames: mover.features, moverSpeech: nil, fps: fps) {
            coarse = found
        }
        let coarseDelta = coarse.map {
            ReelTime.snapToFrame(zeroA + Ticks(($0.lag * Double(step)).rounded()), fps: fps)
        }
        let plan = AudioSync.plan(
            AudioSync.Input(readings: [anchor, mover], problems: [], anchor: nil, fps: fps))
        let control = abs(centreLine - want) >= 2 * frame
        guard case .planned(_, let synced, let ops) = plan, let one = synced.first else {
            good = false
            notes.append("\(name): \(describe(plan))")
            continue
        }
        let speedOp = ops.first { $0.name == "set_speed" }
        let rate = speedOp?.args["rate"] as? Double ?? .nan
        let keep = speedOp?.args["keep_pitch"] as? Bool
        let moveDelta = ops.first { $0.name == "move_clip" }?.args["delta"] as? Ticks
        let rateOK = abs(rate * k - 1) <= 5e-6
        let ok = rateOK && keep == false && one.delta == want && moveDelta == want
            && ops.map { $0.name } == order && one.correction == .apply(speed: rate) && control
        if !ok { good = false }
        notes.append(
            "\(name): rate \(String(format: "%.7f", rate)) (want 1/k "
                + "\(String(format: "%.7f", 1 / k)) ±5 ppm), keep_pitch \(keep.map(String.init) ?? "nil"), "
                + "delta \(one.delta) (want \(want)), duration \(one.duration); ops \(opList(ops)) "
                + "(want \(order)); control: centre-line delta \(centreLine), coarse delta "
                + "\(coarseDelta.map(String.init) ?? "nil") (z "
                + "\(coarse.map { String(format: "%.2f", $0.confidence) } ?? "nil"), "
                + "\(coarse.map { $0.search.rawValue } ?? "nil")), drift \(one.drift)")
    }
    // The neighbour: k 1.001 at S 21 000 000 (zero 18 000 000, I 3 000 000)
    // puts delta at snap(3 000) = 0; d 117 000 000 grows to about
    // 117 120 000, so a neighbour from the old end 138 000 000 is overlapped
    // and one 10 frames later (138 200 000) is not.
    let movedFeatures = moverFeatures(1.001)
    func withNeighbour(_ at: Ticks) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    anchor,
                    reading(
                        2, track: 1, start: 21_000_000, end: 138_000_000, zero: 18_000_000,
                        features: movedFeatures,
                        neighbours: [AudioSync.Neighbour(clip: 99, start: at, end: 150_000_000)]),
                ], problems: [], anchor: nil, fps: fps))
    }
    let abutting = withNeighbour(138_000_000)
    let later = withNeighbour(138_000_000 + 10 * frame)
    if refusal(abutting) != "clip 2: would overlap clip 99 on its track." { good = false }
    if case .planned(_, let synced, let ops) = later,
       synced.first?.delta == 0, ops.map({ $0.name }) == ["set_speed"] {
        notes.append("neighbour 10 frames later: \(describe(later)), ops \(opList(ops))")
    } else {
        good = false
        notes.append("neighbour 10 frames later: \(describe(later))")
    }
    notes.append("neighbour abutting the old end, delta 0: \(describe(abutting))")
    row("P7", good, notes.joined(separator: "; "))
}

// MARK: - P8 the decision and the band

do {
    typealias D = AudioSyncMatch.Drift
    func fit(ms: Double, rate: Double, error: Double) -> AudioSyncMatch.DriftAnswer {
        .measured(
            D(ppm: rate * 1e6, milliseconds: ms, rate: rate, intercept: 0,
              errorMilliseconds: error, windows: 10))
    }
    var good = true
    var notes: [String] = []
    func expect(_ name: String, _ got: AudioSync.Correction, _ want: AudioSync.Correction) {
        if got != want { good = false }
        notes.append("\(name): \(got)")
    }
    func applies(_ name: String, _ got: AudioSync.Correction, _ want: Double) {
        if case .apply(let speed) = got, abs(speed - want) <= 1e-12 {
            notes.append("\(name): \(got)")
        } else {
            good = false
            notes.append("\(name): \(got) (want apply ×\(want))")
        }
    }
    let one = AudioSync.correction
    expect("4.99 ms", one(fit(ms: 4.99, rate: 1e-4, error: 0.1), 1),
           .leave(note: "a drift of 4.99 ms over the overlap is under the 5 ms Synchronize "
               + "Audio corrects."))
    applies("5.0 ms ±1", one(fit(ms: 5.0, rate: 1e-4, error: 1.0), 1), 1 - 1e-4)
    // max(5, 3 × error): at 5 ms with ±1.7 the 3× test (5.1) is the one that bites.
    expect("5.0 ms ±1.7", one(fit(ms: 5.0, rate: 1e-4, error: 1.7), 1),
           .leave(note: "a drift of 5.00 ms over the overlap is under 3 times its "
               + "uncertainty (±1.70 ms), so it cannot be told from no drift."))
    applies("30 ms ±9.99 (just over 3×)", one(fit(ms: 30, rate: 2e-4, error: 9.99), 1),
            1 - 2e-4)
    applies("30 ms ±10 (exactly 3×)", one(fit(ms: 30, rate: 2e-4, error: 10), 1), 1 - 2e-4)
    expect("30 ms ±10.01 (just under 3×)", one(fit(ms: 30, rate: 2e-4, error: 10.01), 1),
           .leave(note: "a drift of 30.00 ms over the overlap is under 3 times its "
               + "uncertainty (±10.01 ms), so it cannot be told from no drift."))
    expect("−30 ms ±10.01", one(fit(ms: -30, rate: -2e-4, error: 10.01), 1),
           .leave(note: "a drift of -30.00 ms over the overlap is under 3 times its "
               + "uncertainty (±10.01 ms), so it cannot be told from no drift."))
    applies("new speed 0.0019 from ×1", one(fit(ms: 100, rate: 0.0019, error: 0.1), 1), 1 - 0.0019)
    expect("new speed 0.0021 from ×1", one(fit(ms: 100, rate: 0.0021, error: 0.1), 1),
           .leave(note: "correcting it would play the clip at ×0.9979, beyond the 0.2% "
               + "Synchronize Audio corrects."))
    // 20 ppm over a 6,000-bucket overlap: 20e-6 × 60 000 ms = 1.2 ms.
    expect("20 ppm", one(fit(ms: 1.2, rate: 20e-6, error: 0.3), 1),
           .leave(note: "a drift of 1.20 ms over the overlap is under the 5 ms Synchronize "
               + "Audio corrects."))
    expect("not measured", one(.notMeasured("x"), 1), .leave(note: nil))

    // A mover whose file holds f(m·k − 4000) (k 1.001), already playing at
    // 1/k: on its timeline grid its bucket j is the anchor's j − 4000, so it
    // is in sync where zeroN = zeroA − 24 000 000 = 12 000 000 — no op.
    let k = 1.001
    let driftedFeatures = featureBumps(seed: 181, length: 16_500, count: 12_500, k: k, c: -4000)
    let anchor = reading(
        1, track: 0, start: 36_000_000, end: 132_000_000, zero: 36_000_000, video: true,
        features: featureBumps(seed: 181, length: 16_500, count: 10_000, k: 1, c: 0))
    func resync(_ speed: Double) -> AudioSync.Plan {
        AudioSync.plan(
            AudioSync.Input(
                readings: [
                    anchor,
                    reading(
                        2, track: 1, start: 15_000_000, end: 15_000_000 + 117_120_000,
                        zero: 12_000_000, features: driftedFeatures,
                        speed: speed),
                ], problems: [], anchor: nil, fps: fps))
    }
    let settled = resync(1 / k)
    if case .planned(_, let synced, let ops) = settled, ops.isEmpty,
       case .leave = synced.first?.correction {
        notes.append("at 1/k: \(describe(settled)), drift \(synced.first!.drift)")
    } else {
        good = false
        notes.append("at 1/k: \(describe(settled)) (want no op)")
    }
    let near = resync(0.9999)
    if case .planned(_, _, let ops) = near,
       let rate = ops.first(where: { $0.name == "set_speed" })?.args["rate"] as? Double,
       abs(rate * k - 1) <= 5e-6 {
        notes.append("at ×0.9999: \(opList(ops)) (want rate 1/k ±5 ppm)")
    } else {
        good = false
        notes.append("at ×0.9999: \(describe(near)) (want a set_speed to 1/k ±5 ppm)")
    }

    let band: [(Double, Bool)] = [(2, false), (1.002, true), (1.0021, false), (0.998, true),
                                  (0.9979, false)]
    for (rate, inside) in band {
        let problem = AudioSync.rateProblem(rate)
        if (problem == nil) != inside { good = false }
        notes.append("×\(rate): \(problem ?? "matched")")
    }
    if AudioSync.rateProblem(2) != "plays at ×2; Synchronize Audio lines up clips playing at "
        + "×1 or within 0.2% of it." {
        good = false
    }
    row("P8", good, notes.joined(separator: "; "))
}

// MARK: - P9 the extractor

do {
    var good = true
    var notes: [String] = []
    let counts: [(Int, Int)] = [(511, 0), (512, 1), (639, 1), (640, 2), (8000, 59)]
    for (samples, want) in counts {
        let got = SyncFeatures.frameCount(samples: samples)
        if got != want { good = false }
        notes.append("frameCount(\(samples)) \(got) (want \(want))")
    }
    let signal = bursts(seconds: 4, seed: 91)
    let plain = SyncFeatures.frames(signal)
    if plain.count != SyncFeatures.frameCount(samples: signal.count) * width { good = false }
    // Delayed by 5 hops and fed in pieces of 1,000 samples.
    let delayed = [Float](repeating: 0, count: 5 * SyncFeatures.hop) + signal
    let extractor = SyncFeatures.Extractor()
    var at = 0
    while at < delayed.count {
        let piece = Array(delayed[at..<min(at + 1000, delayed.count)])
        piece.withUnsafeBufferPointer { extractor.feed($0) }
        at += 1000
    }
    let shiftedOut = extractor.finish()
    var worst: Float = 0
    let frames = plain.count / width
    if shiftedOut.count != (frames + 5) * width { good = false }
    for f in 0..<min(frames, shiftedOut.count / width - 5) {
        for k in 0..<width {
            worst = max(worst, abs(shiftedOut[(f + 5) * width + k] - plain[f * width + k]))
        }
    }
    if !(worst < 1e-3) { good = false }
    notes.append(
        "\(frames) frames; delayed 5·128 samples, fed in 1,000s: \(shiftedOut.count / width) "
            + "frames, max |Δ| against frame f + 5 \(String(format: "%.2e", worst)) (< 1e-3)")
    let silence = SyncFeatures.frames([Float](repeating: 0, count: 16_000))
    var lcg = LCG(state: 92)
    let floor = SyncFeatures.frames((0..<16_000).map { _ in lcg.signed() * 0.0005 })
    let silentOK = AudioSyncMatch.isSilent(silence) && !AudioSyncMatch.isSilent(floor)
        && !AudioSyncMatch.isSilent(plain)
    if !silentOK { good = false }
    if SyncFeatures.frameTicks != 9600 { good = false }
    notes.append(
        "silence isSilent \(AudioSyncMatch.isSilent(silence)), a −66 dBFS floor "
            + "\(AudioSyncMatch.isSilent(floor)), the bursts \(AudioSyncMatch.isSilent(plain)); "
            + "frameTicks \(SyncFeatures.frameTicks)")
    row("P9", good, notes.joined(separator: "; "))
}

// MARK: - P10 the summed correlation

do {
    var good = true
    var notes: [String] = []
    // Brute force: Σ_k Σ_m x_k[m+L]·y_k[m], on 40 and 25 frames.
    let x = randomFrames(40, seed: 101)
    let y = randomFrames(25, seed: 102)
    let fast = AudioSyncMatch.summedCorrelation(x, y)
    var worst = 0.0
    var scale = 0.0
    for index in 0..<(40 + 25 - 1) {
        let lag = index - 24
        var sum = 0.0
        for m in 0..<25 where m + lag >= 0 && m + lag < 40 {
            for k in 0..<width { sum += Double(x[(m + lag) * width + k]) * Double(y[m * width + k]) }
        }
        worst = max(worst, abs(sum - fast[index]))
        scale = max(scale, abs(sum))
    }
    if !(fast.count == 64 && worst <= 1e-4 * max(scale, 1)) { good = false }
    notes.append(
        "vs brute force over 64 lags: worst |Δ| \(String(format: "%.2e", worst)) of scale "
            + "\(String(format: "%.1f", scale))")

    // A lag planted at a PARTIAL overlap (500 of the mover's 1,000 frames):
    // anchor frame m + 1500 is the mover's m. Each coefficient sits at its
    // own level, as MFCCs do, and the mover's is moved (a gain change moves
    // c0 most) and scaled, with noise; unstandardised, the levels would put
    // the peak where the overlap is longest.
    var lcg = LCG(state: 103)
    var anchor = randomFrames(2000, seed: 104)
    for f in 0..<2000 { for k in 0..<width { anchor[f * width + k] += Float(30 - k) } }
    var mover = [Float](repeating: 0, count: 1000 * width)
    for m in 0..<1000 {
        for k in 0..<width {
            let base = m + 1500 < 2000
                ? anchor[(m + 1500) * width + k] - Float(30 - k) : lcg.signed()
            let level: Float = k == 0 ? 52 : Float(35 - k)
            mover[m * width + k] = 0.5 * base + level + lcg.signed() * 0.2
        }
    }
    let result = AudioSyncMatch.search(
        anchor: anchor, mover: mover, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: -5000)
    let chosen = result.flatMap { AudioSync.choose($0) }
    let lagOK = chosen.map { abs($0.0.lag - 1500) <= 0.25 && $0.1 == .confidence } ?? false
    let lags = result?.candidates.map { $0.lag } ?? []
    var apart = !lags.isEmpty
    for i in lags.indices { for j in lags.indices where j > i && abs(lags[i] - lags[j]) <= 60 {
        apart = false
    } }
    if !lagOK || !apart { good = false }
    notes.append(
        "planted 1500 at a 500-frame overlap: chosen "
            + "\(chosen.map { String(format: "%.3f", $0.0.lag) } ?? "nil") (want 1500 ±0.25) z "
            + "\(chosen.map { String(format: "%.2f", $0.0.z) } ?? "nil") by "
            + "\(chosen.map { $0.1.rawValue } ?? "nothing"); candidates "
            + "\(result.map { $0.candidates.map { String(format: "%.1f@%.2f", $0.lag, $0.z) } } ?? []) "
            + "(each > 60 apart: \(apart))")
    row("P10", good, notes.joined(separator: "; "))
}

// MARK: - P11 the choice and the search order

do {
    typealias C = AudioSyncMatch.Candidate
    typealias R = AudioSyncMatch.SearchResult
    var good = true
    var notes: [String] = []
    func chooses(_ name: String, _ result: R, _ want: (C, AudioSync.ChosenBy)?) {
        let got = AudioSync.choose(result)
        let ok = got?.0 == want?.0 && got?.1 == want?.1
        if !ok { good = false }
        notes.append(
            "\(name): \(got.map { "\($0.1.rawValue) z \($0.0.z)" } ?? "nil")"
                + (ok ? "" : " (want \(want.map { "\($0.1.rawValue) z \($0.0.z)" } ?? "nil"))"))
    }
    let zc = AudioSyncMatch.confidentZ
    let margin = AudioSyncMatch.confidentMargin
    let zp = AudioSyncMatch.plausibleZ
    let six = C(lag: 10, z: zc)
    let near = C(lag: -3, z: zp)
    let exactly = C(lag: 200, z: zc - margin)
    let short = C(lag: 200, z: zc - margin + 0.01)
    chooses("z confidentZ, margin exactly confidentMargin",
            R(candidates: [six, exactly], nearPlacement: nil), (six, .confidence))
    chooses("z confidentZ − 0.01, margin far over",
            R(candidates: [C(lag: 10, z: zc - 0.01), C(lag: 200, z: 1.0)], nearPlacement: nil), nil)
    chooses("z confidentZ, margin 0.01 short", R(candidates: [six, short], nearPlacement: nil), nil)
    chooses("margin 0.01 short, near z plausibleZ",
            R(candidates: [six, short], nearPlacement: near), (near, .placement))
    chooses("margin 0.01 short, near z plausibleZ − 0.01",
            R(candidates: [six, short], nearPlacement: C(lag: -3, z: zp - 0.01)), nil)
    chooses("one candidate z confidentZ", R(candidates: [six], nearPlacement: nil),
            (six, .confidence))
    let strong = C(lag: 400, z: zc + 2)
    chooses("confident beats nearer", R(candidates: [strong, C(lag: 0, z: zp + 1)],
                                        nearPlacement: C(lag: 0, z: zp + 1)), (strong, .confidence))

    // The radius: a planted lag of 100 is the near placement 188 frames from
    // where the mover sits, and not 189 frames away.
    let base = randomFrames(1000, seed: 111)
    let planted = shiftedFrames(base, by: 100, count: 800, seed: 112)
    let inside = AudioSyncMatch.search(
        anchor: base, mover: planted, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: -88)
    let outside = AudioSyncMatch.search(
        anchor: base, mover: planted, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: -89)
    let insideOK = inside?.nearPlacement.map { abs($0.lag - 100) <= 0.5 } ?? false
    let outsideOK = outside.map { result in
        result.nearPlacement.map { abs($0.lag - 100) > 1 && $0.z < AudioSyncMatch.plausibleZ } ?? true
    } ?? false
    if !insideOK || !outsideOK { good = false }
    notes.append(
        "planted 100, placement −88 (188 away): near "
            + "\(inside?.nearPlacement.map { String(format: "%.2f@%.2f", $0.lag, $0.z) } ?? "nil"); "
            + "placement −89: near "
            + "\(outside?.nearPlacement.map { String(format: "%.2f@%.2f", $0.lag, $0.z) } ?? "nil")")

    // A flank: the anchor holds one broad event twice (frames 7,000 and
    // 13,000 of 20,000), the mover once (frame 750 of 1,500), so the two
    // peaks (lags 6,250 and 12,250) tie and the margin fails. The radius
    // around 6,250 − 196 covers only the rising flank up to 8 frames short of
    // the peak: there is no local maximum in it, so no near placement.
    func event(_ count: Int, at centres: [Double], sigma: Double, seed: UInt64) -> [Float] {
        var lcg = LCG(state: seed)
        let signs = (0..<width).map { _ in lcg.next() < 0.5 ? -1.0 : 1.0 }
        var out = [Float](repeating: 0, count: count * width)
        for f in 0..<count {
            let g = centres.reduce(0.0) { $0 + exp(-(Double(f) - $1) * (Double(f) - $1)
                / (2 * sigma * sigma)) }
            for k in 0..<width { out[f * width + k] = Float(g * signs[k]) }
        }
        return out
    }
    let wide = event(20_000, at: [7_000, 13_000], sigma: 106, seed: 113)
    let once = event(1_500, at: [750], sigma: 106, seed: 113)
    let flank = AudioSyncMatch.search(
        anchor: wide, mover: once, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: 6_250 - 196)
    // The control: the flank lag 8 frames short of the peak reaches z ≥ 4,
    // so a rule taking the highest lag in the radius would have chosen it.
    let c = AudioSyncMatch.summedCorrelation(
        AudioSyncMatch.standardised(wide), AudioSyncMatch.standardised(once))
    let mean = c.reduce(0, +) / Double(c.count)
    let sd = (c.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(c.count)).squareRoot()
    let flankZ = (c[6_250 - 8 + 1_499] - mean) / sd
    let flankOK = flank.map { $0.nearPlacement == nil && AudioSync.choose($0) == nil } ?? false
        && flankZ >= AudioSyncMatch.plausibleZ
    if !flankOK { good = false }
    notes.append(
        "flank only: candidates "
            + "\(flank.map { $0.candidates.map { String(format: "%.1f@%.2f", $0.lag, $0.z) } } ?? []), "
            + "near \(flank?.nearPlacement.map { String(format: "%.1f", $0.lag) } ?? "nil"), choice "
            + "\(flank.flatMap { AudioSync.choose($0) }.map { $0.1.rawValue } ?? "nil"); control: "
            + "the flank's z \(String(format: "%.2f", flankZ)) (≥ 4)")

    // `find`. The anchor's file holds an utterance U at frames [2000, 2300)
    // and a longer competing stretch C at [4000, 4800); the mover's file holds
    // C at [0, 800) and U at [6000, 6300). U's lag is −4000, C's +4000, and
    // C wins any whole-file search.
    let anchorFile = randomFrames(5000, seed: 114)
    var moverFile = randomFrames(8000, seed: 115)
    for f in 0..<800 { for k in 0..<width { moverFile[f * width + k] = anchorFile[(4000 + f) * width + k] } }
    for f in 0..<300 { for k in 0..<width {
        moverFile[(6000 + f) * width + k] = anchorFile[(2000 + f) * width + k]
    } }
    func found(
        _ name: String, anchorWindow: Range<Int>, moverWindow: Range<Int>, moverZeroFrames: Int,
        anchorFeatures: [Float] = anchorFile, moverFeatures: [Float] = moverFile
    ) -> AudioSync.FindAnswer {
        let a = reading(
            1, track: 0, start: Ticks(anchorWindow.lowerBound) * step,
            end: Ticks(anchorWindow.upperBound) * step, zero: 0, video: true,
            features: anchorFeatures)
        let zero = Ticks(moverZeroFrames) * step
        let m = reading(
            2, track: 1, start: zero + Ticks(moverWindow.lowerBound) * step,
            end: zero + Ticks(moverWindow.upperBound) * step, zero: zero, features: moverFeatures)
        let answer = AudioSync.find(
            anchor: a, anchorFrames: anchorFeatures, anchorSpeech: nil, mover: m,
            moverFrames: moverFeatures, moverSpeech: nil, fps: fps)
        switch answer {
        case .found(let f):
            notes.append(
                "\(name): \(f.search.rawValue) by \(f.chosenBy.rawValue), lag "
                    + "\(String(format: "%.2f", f.lag)) z \(String(format: "%.2f", f.confidence)), "
                    + "\(f.candidates.count) candidate(s)")
        case .refused(let problem):
            notes.append("\(name): refused \(problem.description)")
        }
        return answer
    }
    func isFound(_ answer: AudioSync.FindAnswer, _ search: AudioSync.Search, lag: Double) -> Bool {
        if case .found(let f) = answer { return f.search == search && abs(f.lag - lag) <= 0.5 }
        return false
    }
    // Played first: both windows hold U, both are parts of their files.
    let first = found("played first", anchorWindow: 1800..<2500, moverWindow: 5900..<6400,
                      moverZeroFrames: -4200)
    if !isFound(first, .played, lag: -4000) { good = false }
    // The played windows hold nothing in common, and are parts of their
    // files: the whole files are searched and C is found. The mover sits at
    // lag 4,000, well away from every lag the played search can see.
    let fallback = found("played chose nothing", anchorWindow: 0..<700, moverWindow: 2000..<2500,
                         moverZeroFrames: 4000)
    if !isFound(fallback, .whole, lag: 4000) { good = false }
    // Under 125 frames, the played windows are not searched.
    let tiny = found("played windows of 100 frames", anchorWindow: 2000..<2100,
                     moverWindow: 6000..<6100, moverZeroFrames: -4000)
    if !isFound(tiny, .whole, lag: 4000) { good = false }
    // Two unrelated files played whole: the played windows ran, the whole
    // files did not, and the refusal names the played search's best candidate
    // as its move. The mover sits 5,000 frames away, beyond every lag (P4).
    let lone = randomFrames(1000, seed: 116)
    let stranger = randomFrames(1000, seed: 117)
    let whole = found("both whole files, unrelated", anchorWindow: 0..<1000,
                      moverWindow: 0..<1000, moverZeroFrames: 5000, anchorFeatures: lone,
                      moverFeatures: stranger)
    let direct = AudioSyncMatch.search(
        anchor: lone, mover: stranger, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: 5000)
    let firstMove = direct?.candidates.first.map { candidate -> String in
        let delta = ReelTime.snapToFrame(
            -5000 * step + Ticks((candidate.lag * Double(step)).rounded()), fps: fps)
        return String(format: "%+.2f", Double(delta) / 600_000).replacingOccurrences(of: "-", with: "−")
            + " s (confidence " + String(format: "%.2f", candidate.z) + ")"
    }
    if case .refused(let problem) = whole, let firstMove {
        if !(problem.reason.hasPrefix("no matching sound found between clip 1 and clip 2: in the "
                + "played windows, moving clip 2 by " + firstMove)
            && !problem.reason.contains("in the whole files")) {
            good = false
        }
    } else {
        good = false
    }
    notes.append("the played search's first candidate as a move: \(firstMove ?? "nil")")
    // The same two files played in part: both searches ran and are named.
    let both = found("both in part, unrelated", anchorWindow: 0..<500, moverWindow: 0..<500,
                     moverZeroFrames: 5000, anchorFeatures: lone, moverFeatures: stranger)
    if case .refused(let problem) = both, problem.reason.contains("in the played windows, moving")
        && problem.reason.contains("; in the whole files, moving") {
    } else {
        good = false
    }
    row("P11", good, notes.joined(separator: "; "))
}

// MARK: - P12 the head trim

do {
    var good = true
    var notes: [String] = []
    let frame: Ticks = 20_000
    let anchorFile = randomFrames(3000, seed: 121)
    // The mover's frame m is the anchor's m − 50: lag −50 frames (−480 000).
    let moverFile = shiftedFrames(anchorFile, by: -50, count: 3000, seed: 122)
    let anchorAt0 = reading(1, track: 0, start: 0, end: 3000 * step, zero: 0, video: true,
                            features: anchorFile)
    /// A ×1 mover at S with in point I and duration d: zeroN = S − I, so
    /// δ = 0 − (S − I) − 480 000 and S + δ = I − 480 000.
    func trimmed(_ name: String, anchor: AudioSync.Reading = anchorAt0, start: Ticks, sourceIn: Ticks,
                 duration: Ticks, neighbours: [AudioSync.Neighbour] = []) -> AudioSync.Plan {
        let plan = AudioSync.plan(
            AudioSync.Input(
                readings: [
                    anchor,
                    reading(2, track: 1, start: start, end: start + duration,
                            zero: start - sourceIn, features: moverFile, neighbours: neighbours),
                ], problems: [], anchor: nil, fps: fps))
        notes.append("\(name): \(describe(plan))"
            + (planOps(plan).map { ", ops \(opList($0))" } ?? ""))
        return plan
    }
    func planOps(_ plan: AudioSync.Plan) -> [ReelOp]? {
        if case .planned(_, _, let ops) = plan { return ops }
        return nil
    }
    func expectTrim(_ plan: AudioSync.Plan, delta: Ticks, to: Ticks, excess: Ticks,
                    duration: Ticks) -> Bool {
        guard case .planned(let anchorClip, let synced, let ops) = plan, let one = synced.first
        else { return false }
        return anchorClip == 1 && one.delta == delta && one.start == 0 && one.trimmed == excess
            && one.duration == duration && ops.map { $0.name } == ["trim_start", "move_clip"]
            && ops[0].args["to"] as? Ticks == to && ops[0].args["clip"] as? UInt32 == 2
            && ops[1].args["delta"] as? Ticks == delta
    }
    // ×1 at −0.5 s: S 600 000, I 180 000 (zeroN 420 000), d 14 400 000.
    // δ = −420 000 − 480 000 = −900 000 (frame −45); S + δ = −300 000, so
    // e = 300 000: trim_start to S + e = 900 000, then move_clip −900 000;
    // the span [0, 14 100 000) and in I + e = 480 000 (the core's trim).
    let half = trimmed("×1 at −0.5 s", start: 600_000, sourceIn: 180_000, duration: 14_400_000)
    if !expectTrim(half, delta: -900_000, to: 900_000, excess: 300_000, duration: 14_100_000) {
        good = false
    }
    notes.append("want in 480 000 after trim_start (I + e)")
    // Exactly one frame left: d 320 000 − e 300 000 = 20 000.
    let oneFrame = trimmed("one frame left", start: 600_000, sourceIn: 180_000, duration: 320_000)
    if !expectTrim(oneFrame, delta: -900_000, to: 900_000, excess: 300_000, duration: frame) {
        good = false
    }
    let under = trimmed("under a frame left", start: 600_000, sourceIn: 180_000, duration: 319_999)
    if refusal(under) != "clip 2: would have to lose 0.50 s of its head to start at 0, leaving "
        + "under a frame of it." {
        good = false
    }
    // The anchor plays only from 20 s: the trimmed span [0, 14 100 000)
    // never meets it.
    let late = reading(1, track: 0, start: 20_000_000, end: 3000 * step, zero: 0, video: true,
                       features: anchorFile)
    let apart = trimmed("trimmed span misses the anchor", anchor: late, start: 600_000,
                        sourceIn: 180_000, duration: 14_400_000)
    if refusal(apart) != "clip 2: once lined up it would not play at any moment clip 1 plays." {
        good = false
    }
    // S 3 000 000, I 180 000 (zeroN 2 820 000), d 1 500 000: δ = −3 300 000,
    // e 300 000, the trimmed span [0, 1 200 000), clear of the mover's old
    // span [3 000 000, 4 500 000).
    let hit = trimmed("neighbour meeting the trimmed span", start: 3_000_000, sourceIn: 180_000,
                      duration: 1_500_000,
                      neighbours: [AudioSync.Neighbour(clip: 99, start: 1_180_000, end: 2_000_000)])
    if refusal(hit) != "clip 2: would overlap clip 99 on its track." { good = false }
    let clear = trimmed("the same neighbour one frame clear", start: 3_000_000, sourceIn: 180_000,
                        duration: 1_500_000,
                        neighbours: [AudioSync.Neighbour(clip: 99, start: 1_200_000, end: 2_000_000)])
    if !expectTrim(clear, delta: -3_300_000, to: 3_300_000, excess: 300_000, duration: 1_200_000) {
        good = false
    }

    // +1,000 ppm needing a trim: P7's mover (S 3 000 000, I 3 000 000, zero
    // 0, d 117 s) against P7's anchor moved 24 000 000 earlier (zeroA
    // 66 000 000, a multiple of 48 000). δ = snap(66 000 000 − 72 000 000 −
    // 3 000 000 + 3 000 000·1.001) = snap(−5 997 000) = −6 000 000; S + δ =
    // −3 000 000, so e = 3 000 000: set_speed (≈ 1/k), trim_start to
    // 6 000 000, move_clip −6 000 000; in after I + e·s' ≈ 3 000 000 +
    // 3 000 000/1.001 = 5 997 003 (the core's trim at s').
    let k = 1.001
    var moverFeatures = featureBumps(seed: 171, length: 8_100, count: 12_500, k: k, c: -12_000)
    for index in 0..<(7_500 * width) { moverFeatures[index] = 0 }
    let zeroA: Ticks = 66_000_000
    let drifted = AudioSync.plan(
        AudioSync.Input(
            readings: [
                reading(1, track: 0, start: zeroA, end: zeroA + 48_000_000, zero: zeroA,
                        video: true,
                        features: featureBumps(seed: 171, length: 8_100, count: 5_000, k: 1, c: 0)),
                reading(2, track: 1, start: 3_000_000, end: 120_000_000, zero: 0,
                        features: moverFeatures),
            ], problems: [], anchor: nil, fps: fps))
    if case .planned(_, let synced, let ops) = drifted, let one = synced.first,
       ops.map({ $0.name }) == ["set_speed", "trim_start", "move_clip"],
       let rate = ops[0].args["rate"] as? Double, abs(rate * k - 1) <= 5e-6,
       ops[1].args["to"] as? Ticks == 6_000_000, ops[2].args["delta"] as? Ticks == -6_000_000,
       one.start == 0, one.trimmed == 3_000_000 {
        notes.append(
            "+1000 ppm with a trim: \(opList(ops)); duration \(one.duration); want in "
                + "\(String(format: "%.0f", 3_000_000 + 3_000_000 * rate)) after trim_start")
    } else {
        good = false
        notes.append("+1000 ppm with a trim: \(describe(drifted))"
            + (planOps(drifted).map { ", ops \(opList($0))" } ?? ""))
    }
    row("P12", good, notes.joined(separator: "; "))
}

// MARK: - P13 unrelated sound placed where it overlaps

do {
    // The case P4 and P11 keep out of reach (AS-3's review, finding 3): two
    // clips that are not the same take, placed so they overlap — both at 0,
    // placement lag 0, the user's natural first try — must never apply
    // without asking (SY-18), and since SY-29 not even be offered: each
    // reading carries its own samples, which never line up, so the waveform
    // gate refuses whatever the features chose. Each pair is
    // `SyncFeatures.frames` of two seeds' 30 s of bursts (CAMERA and
    // UNRELATED's recipe) with those bursts as its int16 samples, and one
    // pair is white-noise frames with seeded noise samples; every one must be
    // refused "no matching sound found" — never planned. The near
    // placement's z is printed beside each, for SY-14's calibration, and
    // which refusal it was (the search's, or the gate's naming GCC-PHAT).
    var good = true
    var notes: [String] = []
    func unrelatedAtPlacement(
        _ name: String, _ anchor: [Float], _ mover: [Float], _ samples: ([Int16], [Int16])
    ) {
        let count = (anchor.count / width, mover.count / width)
        let plan = AudioSync.plan(
            AudioSync.Input(
                readings: [
                    reading(1, track: 0, start: 0, end: Ticks(count.0) * step, zero: 0,
                            video: true, samples: samples.0, features: anchor),
                    reading(2, track: 1, start: 0, end: Ticks(count.1) * step, zero: 0,
                            samples: samples.1, features: mover),
                ], problems: [], anchor: nil, fps: fps))
        let near = AudioSyncMatch.search(
            anchor: anchor, mover: mover, anchorSpeech: nil, moverSpeech: nil,
            offset: 0, placementLag: 0
        ).flatMap { $0.nearPlacement }
        let said = refusal(plan) ?? ""
        let refused = said.hasPrefix("no matching sound found between clip 1 and clip 2")
        if !refused { good = false }
        let how = said.contains("GCC-PHAT confidence") ? "refused by the waveform gate"
            : "refused by the search"
        // The gate's clause, whole words: from its first "(GCC-PHAT
        // confidence" to the end (#308), the whole reason when it is absent.
        let gate = said.range(of: "(GCC-PHAT confidence").map { String(said[$0.lowerBound...]) }
            ?? said
        notes.append(
            "\(name) (\(count.0) and \(count.1) frames, both at 0): near placement "
                + (near.map { String(format: "lag %.2f z %.2f", $0.lag, $0.z) } ?? "nil")
                + " → \(refused ? how + (how.hasSuffix("gate") ? " " + gate : "") : "NOT refused: " + describe(plan))")
    }
    /// The cache's int16 of `values` (`round(clamp(x, −1, 1)·32767)`).
    func int16(_ values: [Float]) -> [Int16] {
        values.map { Int16((min(1, max(-1, Double($0))) * 32767).rounded()) }
    }
    for (index, seeds) in [(131, 132), (133, 134), (135, 136), (137, 138)].enumerated() {
        let anchorSound = bursts(seconds: 30, seed: UInt64(seeds.0))
        let moverSound = bursts(seconds: 30, seed: UInt64(seeds.1))
        unrelatedAtPlacement(
            "bursts pair \(index + 1)",
            SyncFeatures.frames(anchorSound), SyncFeatures.frames(moverSound),
            (int16(anchorSound), int16(moverSound)))
    }
    unrelatedAtPlacement(
        "white noise", randomFrames(1500, seed: 139), randomFrames(1500, seed: 140),
        (int16(randomArray(1500 * SyncFeatures.hop, seed: 141).map { $0 * 0.3 }),
         int16(randomArray(1500 * SyncFeatures.hop, seed: 142).map { $0 * 0.3 })))
    row("P13", good, notes.joined(separator: "; "))
}

// MARK: - P14 speech-only matching

do {
    var good = true
    var notes: [String] = []
    let (T, F) = (true, false)
    // Frame f's centre is f·9,600 + 19,200 ticks; a chunk is 19,200: frames
    // 0 and 1 read chunk 1 (0.5, speech), 2 and 3 chunk 2 (0.49, not), 4 and
    // 5 chunk 3 (0.9), 6 and 7 past the end, the last chunk (0.9).
    let mask = AudioSyncMatch.speechMask([0.1, 0.5, 0.49, 0.9], frames: 8)
    let empty = AudioSyncMatch.speechMask([], frames: 5)
    let centre = AudioSyncMatch.frameCentreTicks
    if mask != [T, T, F, F, T, T, T, T] || empty != [Bool](repeating: false, count: 5)
        || centre != 19_200 {
        good = false
    }
    notes.append(
        "speechMask([0.1, 0.5, 0.49, 0.9], frames: 8) \(mask.map { $0 ? "T" : "F" }.joined()) "
            + "(want TTFFTTTT); of none \(empty.map { $0 ? "T" : "F" }.joined()) (want FFFFF); "
            + "frameCentreTicks \(centre) (want 19200)")

    var lcg = LCG(state: 141)
    let long = (0..<1000).map { _ in lcg.next() < 0.4 }
    let identity = AudioSyncMatch.resampledMask(long, speed: 1) == long
    let stretched = AudioSyncMatch.resampledMask(long, speed: 1.001).count
    let framesAt = AudioSyncMatch.resampledFrames(randomFrames(1000, seed: 142), speed: 1.001)
        .count / width
    if !identity || stretched != framesAt { good = false }
    notes.append(
        "resampledMask ×1 the identity \(identity); ×1.001 \(stretched) frames (resampledFrames "
            + "\(framesAt))")

    // 200 frames, 120 of them speech; the others sit 5 higher, so a mean
    // over every frame is not the speech frames' mean.
    let speech200 = (0..<200).map { ($0 * 7) % 10 < 6 }
    var stretch = randomFrames(200, seed: 143)
    for f in 0..<200 { for k in 0..<width {
        stretch[f * width + k] = stretch[f * width + k] * Float(1 + k % 3) + Float(k)
            + (speech200[f] ? 0 : 5)
    } }
    let masked = AudioSyncMatch.standardised(stretch, speech: speech200)
    var worstMean = 0.0
    var worstSD = 0.0
    var strayFrames = 0
    let spoken = (0..<200).filter { speech200[$0] }
    for k in 0..<width {
        let values = spoken.map { Double(masked[$0 * width + k]) }
        let mean = values.reduce(0, +) / Double(values.count)
        let sd = (values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count))
            .squareRoot()
        worstMean = max(worstMean, abs(mean))
        worstSD = max(worstSD, abs(sd - 1))
    }
    for f in 0..<200 where !speech200[f] {
        if (0..<width).contains(where: { masked[f * width + $0] != 0 }) { strayFrames += 1 }
    }
    if spoken.count != 120 || worstMean >= 1e-4 || worstSD >= 1e-3 || strayFrames != 0 {
        good = false
    }
    notes.append(
        "masked standardised over \(spoken.count) of 200: worst |mean| "
            + "\(String(format: "%.2e", worstMean)) (< 1e-4), worst |sd − 1| "
            + "\(String(format: "%.2e", worstSD)) (< 1e-3), non-speech frames not 0: "
            + "\(strayFrames)")

    // Planted: the mover's [100, 400) is the anchor's [300, 600) (lag +200),
    // marked speech in both; its [1000, 1400) is the anchor's [700, 1100)
    // (lag −300), longer and unmarked. On sound the longer wins; on speech
    // only the marked one can.
    let anchor = randomFrames(2000, seed: 144)
    var mover = randomFrames(2000, seed: 145)
    for f in 0..<300 { for k in 0..<width { mover[(100 + f) * width + k] = anchor[(300 + f) * width + k] } }
    for f in 0..<400 { for k in 0..<width { mover[(1000 + f) * width + k] = anchor[(700 + f) * width + k] } }
    let anchorSpeech = (0..<2000).map { (300..<600).contains($0) }
    func moverSpeech(_ count: Int) -> [Bool] { (0..<2000).map { (100..<(100 + count)).contains($0) } }
    func best(_ result: AudioSyncMatch.SearchResult?) -> String {
        guard let result, let first = result.candidates.first else { return "nil" }
        return String(format: "%.2f z %.2f on ", first.lag, first.z) + result.matchedOn.rawValue
    }
    let sound = AudioSyncMatch.search(
        anchor: anchor, mover: mover, anchorSpeech: nil, moverSpeech: nil, offset: 0,
        placementLag: 5000)
    let onSpeech = AudioSyncMatch.search(
        anchor: anchor, mover: mover, anchorSpeech: anchorSpeech, moverSpeech: moverSpeech(300),
        offset: 0, placementLag: 5000)
    let soundOK = sound.map {
        $0.matchedOn == .sound && abs(($0.candidates.first?.lag ?? 0) - -300) <= 0.5
    } ?? false
    let speechOK = onSpeech.map {
        $0.matchedOn == .speech && abs(($0.candidates.first?.lag ?? 0) - 200) <= 0.5
    } ?? false
    if !soundOK || !speechOK { good = false }
    notes.append(
        "planted +200 (speech) and −300 (longer, unmarked): unmasked best \(best(sound)) (want "
            + "−300 on sound); masked best \(best(onSpeech)) (want +200 ±0.5 on speech)")
    // The floor: 124 speech frames in the mover is on sound, 125 on speech.
    let under = AudioSyncMatch.search(
        anchor: anchor, mover: mover, anchorSpeech: anchorSpeech, moverSpeech: moverSpeech(124),
        offset: 0, placementLag: 5000)?.matchedOn
    let at = AudioSyncMatch.search(
        anchor: anchor, mover: mover, anchorSpeech: anchorSpeech, moverSpeech: moverSpeech(125),
        offset: 0, placementLag: 5000)?.matchedOn
    if under != .sound || at != .speech { good = false }
    notes.append(
        "mover speech 124 frames → \(under?.rawValue ?? "nil") (want sound), 125 → "
            + "\(at?.rawValue ?? "nil") (want speech)")
    row("P14", good, notes.joined(separator: "; "))
}

// MARK: - P15 the weak tier's words

do {
    var good = true
    var notes: [String] = []
    func synced(
        _ clip: UInt32, _ rule: AudioSync.ChosenBy, delta: Ticks, trimmed: Ticks, z: Double,
        correction: AudioSync.Correction = .leave(note: nil)
    ) -> AudioSync.Synced {
        AudioSync.Synced(
            clip: clip, media: clip + 100, lag: 0, coarseLag: 0, refinement: nil, delta: delta,
            start: 0, confidence: z,
            search: .played, chosenBy: rule, matchedOn: .speech, candidates: [],
            drift: .notMeasured("not measured"), speed: 1, duration: 600_000,
            correction: correction, trimmed: trimmed)
    }
    let confident = synced(2, .confidence, delta: -460_000, trimmed: 460_000, z: 12)
    let weak = synced(2, .placement, delta: -460_000, trimmed: 460_000, z: 7.92)
    let still = synced(2, .placement, delta: 0, trimmed: 0, z: 5)
    let moves = (AudioSync.weakMoves([confident]), AudioSync.weakMoves([weak]),
                 AudioSync.weakMoves([still]))
    if !(moves.0.isEmpty && moves.1 == [weak] && moves.2.isEmpty) { good = false }
    notes.append(
        "weakMoves: confident \(moves.0.count) (want 0), weak moving and trimming "
            + "\(moves.1.count) (want 1), weak in place \(moves.2.count) (want 0)")

    let names: [UInt32: String] = [1: "IMG_0018.MOV", 2: "record.aifc", 3: "lapel.wav"]
    let asked = AudioSync.weakQuestion([weak], anchor: 1, names: names)
    let message = "Weak match: move “record.aifc” 0.77 s earlier (trimming 0.77 s off its head)?"
    let detail = "Its sound matches “IMG_0018.MOV” with confidence 7.92: under the 10 a match "
        + "needs to apply on its own, and the best match within 3 s of where it sits now. Cancel "
        + "leaves everything as it is."
    let note = AudioSync.weakNote([weak])
    let wantNote = "Weak match, nothing moved: clip 2 would move by −0.77 s (trimming 0.77 s off "
        + "its head), confidence 7.92 — under the 10 a match needs to apply on its own, and the "
        + "best match within 3 s of where it sits now. Call sync_audio again with accept_weak: "
        + "true to apply it, once the person has agreed to that move."
    if asked.message != message || asked.detail != detail || note != wantNote { good = false }
    notes.append(
        "message \(asked.message == message ? "exact" : "WRONG: " + asked.message); detail "
            + "\(asked.detail == detail ? "exact" : "WRONG: " + asked.detail); note "
            + "\(note == wantNote ? "exact" : "WRONG: " + note)")

    let other = synced(3, .placement, delta: 300_000, trimmed: 0, z: 5.1)
    let two = AudioSync.weakQuestion([weak, other], anchor: 1, names: names)
    let twoMessage = "Weak match: move “record.aifc” 0.77 s earlier (trimming 0.77 s off its "
        + "head); move “lapel.wav” 0.50 s later?"
    let twoNote = AudioSync.weakNote([weak, other])
    let joined = two.message == twoMessage
        && two.detail.hasPrefix("Their sound matches “IMG_0018.MOV” with confidence 7.92, 5.10: ")
        && twoNote.contains("off its head), confidence 7.92; clip 3 would move by +0.50 s, "
            + "confidence 5.10 — ")
    if !joined { good = false }
    notes.append("two weak movers: \(two.message) | \(two.detail) | \(twoNote)")

    // A weak mover listed only because its drift correction applies: no
    // delta, no trim, worded as the speed Apply sets (AS-3's second review).
    let drifted = synced(3, .placement, delta: 0, trimmed: 0, z: 5.1,
                         correction: .apply(speed: 1.0004))
    let driftMoves = AudioSync.weakMoves([drifted])
    let driftMessage = AudioSync.weakQuestion([drifted], anchor: 1, names: names).message
    let driftNote = AudioSync.weakNote([drifted])
    let wantDriftMessage = "Weak match: play “lapel.wav” at ×1.0004, correcting its drift?"
    let wantDriftNote = "Weak match, nothing moved: clip 3 would play at ×1.0004, correcting its "
        + "drift, confidence 5.10 — under the 10 a match needs to apply on its own, and the best "
        + "match within 3 s of where it sits now. Call sync_audio again with accept_weak: true "
        + "to apply it, once the person has agreed to that move."
    if !(driftMoves == [drifted] && driftMessage == wantDriftMessage && driftNote == wantDriftNote) {
        good = false
    }
    notes.append(
        "speed-only weak mover: listed \(driftMoves.count) (want 1); message "
            + "\(driftMessage == wantDriftMessage ? "exact" : "WRONG: " + driftMessage); note "
            + "\(driftNote == wantDriftNote ? "exact" : "WRONG: " + driftNote)")
    row("P15", good, notes.joined(separator: "; "))
}

// MARK: - P16 the PHAT refinement

/// Seeded Gaussian pips: σ 4 ms (32 samples at 8 kHz), 400–3,000 Hz, one
/// every 10–100 ms. `sample` puts in sample n every pip at sample TIME
/// `n·k + c`, evaluated there, so a fractional delay or a drift is exact.
struct Pips {
    var at: [Double] = []
    var hertz: [Double] = []
    var amp: [Double] = []
    var phase: [Double] = []
    init(seed: UInt64, samples: Double) {
        var lcg = LCG(state: seed)
        var t = 0.0
        while t < samples {
            t += 80 + lcg.next() * 720
            at.append(t)
            hertz.append(400 + lcg.next() * 2600)
            amp.append(0.05 + lcg.next() * 0.15)
            phase.append(lcg.next() * 2 * Double.pi)
        }
    }
    func sample(count: Int, k: Double = 1, c: Double = 0) -> [Double] {
        var out = [Double](repeating: 0, count: count)
        let sigma = 32.0
        let reach = 6 * sigma
        let rate = Double(SyncFeatures.sampleRate)
        for index in at.indices {
            let centre = (at[index] - c) / k
            let low = max(0, Int((centre - reach / k).rounded(.up)))
            let high = min(count - 1, Int((centre + reach / k).rounded(.down)))
            guard low <= high else { continue }
            for n in low...high {
                let d = Double(n) * k + c - at[index]
                out[n] += amp[index] * exp(-d * d / (2 * sigma * sigma))
                    * sin(2 * Double.pi * hertz[index] * d / rate + phase[index])
            }
        }
        return out
    }
}

/// `values` scaled by `gain` with seeded uniform noise of `noise`, as the
/// cache's int16 (`round(clamp(x, −1, 1)·32767)`).
func pcm(_ values: [Double], gain: Double = 1, noise: Double, seed: UInt64) -> [Int16] {
    var lcg = LCG(state: seed)
    return values.map { value in
        let x = value * gain + Double(lcg.signed()) * noise
        return Int16((min(1, max(-1, x)) * 32767).rounded())
    }
}

/// What the extractor would be fed for `samples`.
func floats(_ samples: [Int16]) -> [Float] { samples.map { Float($0) / 32767 } }

func describe(_ refinement: AudioSyncPHAT.Refinement?) -> String {
    guard let r = refinement else { return "nil" }
    return "shift \(String(format: "%.3f", r.shift)) z \(String(format: "%.2f", r.z)) "
        + "clear \(r.clear)"
}

do {
    var good = true
    var notes: [String] = []
    // The correlation against a naive DFT: W_k = X_k·conj(Y_k)/|·| on the
    // band's bins 1..<n/2, r[L] = (2/n)·Σ_k Re(W_k·e^{2πikL/n}).
    let x = randomArray(256, seed: 161)
    let y = randomArray(200, seed: 162)
    let fast = AudioSyncPHAT.correlation(x, y)
    let n = 512
    var wr = [Double](repeating: 0, count: n / 2)
    var wi = [Double](repeating: 0, count: n / 2)
    for k in 1..<(n / 2) {
        let hertz = Double(k) * Double(SyncFeatures.sampleRate) / Double(n)
        guard hertz >= AudioSyncPHAT.lowHertz, hertz <= AudioSyncPHAT.highHertz else { continue }
        var xr = 0.0, xi = 0.0, yr = 0.0, yi = 0.0
        for j in 0..<x.count {
            let angle = -2 * Double.pi * Double(k * j) / Double(n)
            xr += Double(x[j]) * cos(angle)
            xi += Double(x[j]) * sin(angle)
        }
        for j in 0..<y.count {
            let angle = -2 * Double.pi * Double(k * j) / Double(n)
            yr += Double(y[j]) * cos(angle)
            yi += Double(y[j]) * sin(angle)
        }
        let re = xr * yr + xi * yi
        let im = xi * yr - xr * yi
        let magnitude = (re * re + im * im).squareRoot()
        guard magnitude >= 1e-20 else { continue }
        wr[k] = re / magnitude
        wi[k] = im / magnitude
    }
    var worst = 0.0
    var scale = 0.0
    var reference: [Double] = []
    for index in 0..<(x.count + y.count - 1) {
        let lag = index - (y.count - 1)
        var sum = 0.0
        for k in 1..<(n / 2) where wr[k] != 0 || wi[k] != 0 {
            let angle = 2 * Double.pi * Double(k * ((lag % n + n) % n)) / Double(n)
            sum += wr[k] * cos(angle) - wi[k] * sin(angle)
        }
        reference.append(2 * sum / Double(n))
    }
    for index in reference.indices {
        worst = max(worst, abs(reference[index] - (index < fast.count ? fast[index] : .nan)))
        scale = max(scale, abs(reference[index]))
    }
    let bruteOK = fast.count == 455 && worst <= 1e-4 * scale
    if !bruteOK { good = false }
    notes.append(
        "correlation vs a naive DFT over 455 lags: worst |Δ| \(String(format: "%.2e", worst)) "
            + "of scale \(String(format: "%.3f", scale)) (≤ 1e-4 of it)")

    // Planted 37.4 samples late: the anchor's sample n holds the pips at
    // time n − 37.4, the mover's at n (6 dB down), each with its own noise.
    let count = 32_000
    let line = AudioSyncPHAT.Line(intercept: 0, rate: 0)
    func refine(_ anchor: [Int16], _ mover: [Int16], region: Range<Int> = 0..<32_000)
        -> AudioSyncPHAT.Refinement? {
        AudioSyncPHAT.refine(
            anchor: anchor, anchorSpeed: 1, mover: mover, moverSpeed: 1, line: line,
            region: region)
    }
    let pips = Pips(seed: 163, samples: Double(count) + 1000)
    let mover = pcm(pips.sample(count: count), gain: 0.5, noise: 0.003, seed: 164)
    let late = pcm(pips.sample(count: count, c: -37.4), noise: 0.003, seed: 165)
    let planted = refine(late, mover)
    let plantedOK = planted.map { abs($0.shift - 37.4) <= 0.1 && $0.clear } ?? false
    if !plantedOK { good = false }
    notes.append("planted 37.4: \(describe(planted)) (want 37.4 ±0.1, clear)")

    let other = pcm(Pips(seed: 166, samples: Double(count) + 1000).sample(count: count),
                    gain: 0.5, noise: 0.003, seed: 167)
    let unrelated = refine(late, other)
    if unrelated == nil || unrelated!.clear { good = false }
    notes.append("unrelated pips: \(describe(unrelated)) (want not clear)")

    let reachLag = Double(AudioSyncPHAT.reachSamples)
    let atReach = refine(pcm(pips.sample(count: count, c: -reachLag), noise: 0.003, seed: 168),
                         mover)
    let reachControl = (atReach?.z ?? 0) >= AudioSyncPHAT.clearZ
    if atReach == nil || atReach!.clear { good = false }
    notes.append(
        "a true lag of exactly \(AudioSyncPHAT.reachSamples): \(describe(atReach)) (want not "
            + "clear; control z ≥ \(String(format: "%g", AudioSyncPHAT.clearZ)): \(reachControl))")

    // The decoy: anchor [2000, 22400) holds D(n − 2000) and the mover
    // [0, 20400) D(n) — 64% of the region at lag +2000 — beside the true
    // stretch [22400, 32000) at lag +20.
    let decoy = Pips(seed: 169, samples: Double(count)).sample(count: count)
    let truePips = Pips(seed: 170, samples: Double(count) + 1000)
    let trueAnchor = truePips.sample(count: count, c: -20)
    let trueMover = truePips.sample(count: count)
    var decoyAnchor = [Double](repeating: 0, count: count)
    var decoyMover = [Double](repeating: 0, count: count)
    for i in 2000..<22_400 { decoyAnchor[i] = decoy[i - 2000] }
    for i in 0..<20_400 { decoyMover[i] = decoy[i] }
    for i in 22_400..<count {
        decoyAnchor[i] = trueAnchor[i]
        decoyMover[i] = trueMover[i]
    }
    let shared = (pcm(decoyAnchor, noise: 0.003, seed: 171),
                  pcm(decoyMover, gain: 0.5, noise: 0.003, seed: 172))
    let decoyed = refine(shared.0, shared.1)
    let r = AudioSyncPHAT.correlation(floats(shared.0), floats(shared.1))
    let decoyR = r[2000 + count - 1]
    let trueR = r[20 + count - 1]
    let decoyControl = decoyR > trueR
    let decoyOK = decoyed.map { abs($0.shift - 20) <= 0.1 } ?? false
    if !decoyOK { good = false }
    notes.append(
        "decoy at +2000 beside the true +20: \(describe(decoyed)) (want 20 ±0.1); control: "
            + "r at +2000 \(String(format: "%.4f", decoyR)) above r at +20 "
            + "\(String(format: "%.4f", trueR)): \(decoyControl)")

    let tooShort = refine(late, mover, region: 0..<15_999)
    let silent = refine(late, [Int16](repeating: 0, count: count))
    if tooShort != nil || silent != nil { good = false }
    notes.append("a 15,999-sample region: \(describe(tooShort)); an all-zero mover: "
        + "\(describe(silent)) (want nil, nil)")
    row("P16", good, notes.joined(separator: "; "), instrument: !reachControl || !decoyControl)
}

// MARK: - P17 the refinement through plan

/// A reading whose samples are `samples` and whose features are
/// `SyncFeatures.frames` of them, playing its whole file from `start`.
func pipsReading(_ clip: UInt32, track: Int, start: Ticks, samples: [Int16], video: Bool = false)
    -> AudioSync.Reading {
    let end = start + Ticks(samples.count) * AudioSyncPHAT.sampleTicks
    return reading(
        clip, track: track, start: start, end: end, zero: start, video: video, samples: samples,
        features: SyncFeatures.frames(floats(samples)))
}

do {
    var good = true
    var notes: [String] = []
    var instrument = false
    // The anchor holds the pips 9,632 samples (1.204 s) after the mover:
    // lag +9,632 samples, 722,400 ticks, 36.12 frames — snapped to 36.
    let seconds = 30
    let delay = 9632.0
    let pips = Pips(seed: 173, samples: Double(seconds * 8000) + delay + 1000)
    let anchorPCM = pcm(pips.sample(count: seconds * 8000 + 9632, c: -delay), noise: 0.003,
                        seed: 174)
    let moverPCM = pcm(pips.sample(count: seconds * 8000), gain: 0.5, noise: 0.003, seed: 175)
    let truth = Ticks(delay) * AudioSyncPHAT.sampleTicks
    let plan = AudioSync.plan(
        AudioSync.Input(
            readings: [
                pipsReading(1, track: 0, start: 0, samples: anchorPCM, video: true),
                pipsReading(2, track: 1, start: 0, samples: moverPCM),
            ], problems: [], anchor: nil, fps: fps))
    if case .planned(_, let synced, _) = plan, let one = synced.first {
        let refinedOK = one.refinement?.clear == true && abs(one.lag - truth) <= 75
            && one.delta == ReelTime.snapToFrame(truth, fps: fps)
        let control = abs(one.coarseLag - truth) > 150
        if !control { instrument = true }
        if !refinedOK { good = false }
        notes.append(
            "1.204 s, no drift: offset \(one.lag) (want \(truth) ±75), coarse \(one.coarseLag) "
                + "(control: > 150 from the truth, \(control)), \(describe(one.refinement)), "
                + "delta \(one.delta) (want \(ReelTime.snapToFrame(truth, fps: fps))), "
                + "z \(String(format: "%.2f", one.confidence)) \(one.chosenBy.rawValue), "
                + "drift \(one.drift)")
    } else {
        good = false
        notes.append("1.204 s, no drift: \(describe(plan))")
    }

    // +200 ppm over 120 s: the mover's sample m holds the pips at time
    // m·k + 9,632.
    let k = 1 + 200e-6
    let long = Pips(seed: 176, samples: 120 * 8000 * k + delay + 1000)
    let longAnchor = pcm(long.sample(count: 120 * 8000), noise: 0.003, seed: 177)
    let longMover = pcm(long.sample(count: 120 * 8000, k: k, c: delay), gain: 0.5, noise: 0.003,
                        seed: 178)
    let want = (1 - 1 / k) * 1e6
    let drifted = AudioSync.plan(
        AudioSync.Input(
            readings: [
                pipsReading(1, track: 0, start: 0, samples: longAnchor, video: true),
                pipsReading(2, track: 1, start: 0, samples: longMover),
            ], problems: [], anchor: nil, fps: fps))
    if case .planned(_, let synced, let ops) = drifted, let one = synced.first,
       case .measured(let drift) = one.drift {
        let ok = drift.on == .phat && abs(drift.ppm - want) <= 1
        if !ok { good = false }
        notes.append(
            "+200 ppm over 120 s: \(String(format: "%.3f", drift.ppm)) ppm (want "
                + "\(String(format: "%.3f", want)) ±1) on \(drift.on.rawValue) over "
                + "\(drift.windows) windows, ±\(String(format: "%.3f", drift.errorMilliseconds)) "
                + "ms; \(describe(one.refinement)); ops \(opList(ops))")
    } else {
        good = false
        notes.append("+200 ppm over 120 s: \(describe(drifted))")
    }
    // The same +200 ppm pair with the mover's [40 s, 70 s) seeded noise.
    var gapped = longMover
    var gapNoise = LCG(state: 179)
    for n in (40 * 8000)..<(70 * 8000) {
        gapped[n] = Int16((Double(gapNoise.signed()) * 0.1 * 32767).rounded())
    }
    let gappedReading = pipsReading(2, track: 1, start: 0, samples: gapped)
    let longAnchorReading = pipsReading(1, track: 0, start: 0, samples: longAnchor, video: true)
    func strip(_ r: AudioSync.Reading) -> AudioSync.Reading {
        AudioSync.Reading(
            clip: r.clip, media: r.media, trackIndex: r.trackIndex, start: r.start, end: r.end,
            zero: r.zero, hasVideo: r.hasVideo, samples: [], features: r.features,
            speech: r.speech, neighbours: r.neighbours, speed: r.speed, sourceIn: r.sourceIn)
    }
    for (name, readings) in [
        ("features only", [strip(longAnchorReading), strip(gappedReading)]),
        ("with samples", [longAnchorReading, gappedReading]),
    ] {
        let gapPlan = AudioSync.plan(
            AudioSync.Input(readings: readings, problems: [], anchor: nil, fps: fps))
        guard case .planned(_, let synced, _) = gapPlan, let one = synced.first,
              case .measured(let drift) = one.drift
        else {
            good = false
            notes.append("+200 ppm, [40 s, 70 s) noise, \(name): \(describe(gapPlan))")
            continue
        }
        let on: AudioSyncMatch.DriftSource = name == "features only" ? .features : .phat
        let ok = drift.on == on && abs(drift.ppm - want) <= 5
        if !ok { good = false }
        var control = ""
        if on == .features {
            // The start rule's window count over the plan's own overlap: the
            // coarse delta's, in anchor frames (both readings start at 0).
            let coarse = ReelTime.snapToFrame(one.coarseLag, fps: fps)
            let anchorEnd = Ticks(longAnchor.count) * AudioSyncPHAT.sampleTicks
            let moverEnd = Ticks(gapped.count) * AudioSyncPHAT.sampleTicks
            let lower = Int(max(0, coarse) / SyncFeatures.frameTicks)
            let upper = Int(min(anchorEnd, moverEnd + coarse) / SyncFeatures.frameTicks)
            let length = max(0, upper - lower)
            let reach = length - AudioSyncMatch.driftWindowFrames
            let step = max(AudioSyncMatch.driftWindowStepFrames, (reach + 62) / 63)
            var count = reach >= 0 ? reach / step + 1 : 0
            if reach >= 0 && reach % step != 0 { count += 1 }
            if !(drift.windows < count) { instrument = true }
            control = " (control: \(drift.windows) fitted of \(count) windows, a gap window "
                + "skipped: \(drift.windows < count))"
        }
        notes.append(
            "+200 ppm, [40 s, 70 s) noise, \(name): \(String(format: "%.3f", drift.ppm)) ppm "
                + "(want \(String(format: "%.3f", want)) ±5 on \(on.rawValue)) on "
                + "\(drift.on.rawValue) over \(drift.windows) windows\(control)")
    }
    row("P17", good, notes.joined(separator: "; "), instrument: instrument)
}

// MARK: - P18 #300: a large drift over a long take

do {
    var good = true
    var notes: [String] = []
    for ppm in [1000.0, -1000.0] {
        let k = 1 + ppm * 1e-6
        let pips = Pips(seed: 181, samples: 160 * 8000 * 1.002 + 9000)
        let anchorPCM = pcm(pips.sample(count: 160 * 8000), noise: 0.003, seed: 182)
        let moverPCM = pcm(pips.sample(count: 160 * 8000, k: k, c: 8000), gain: 0.5,
                           noise: 0.003, seed: 183)
        let input = AudioSync.Input(
            readings: [
                pipsReading(1, track: 0, start: 0, samples: anchorPCM, video: true),
                pipsReading(2, track: 1, start: 0, samples: moverPCM),
            ], problems: [], anchor: nil, fps: fps)
        let began = Date()
        let plan = AudioSync.plan(input)
        let wall = Date().timeIntervalSince(began)
        let name = "\(ppm > 0 ? "+" : "−")\(Int(abs(ppm))) ppm over 160 s"
        guard case .planned(_, let synced, let ops) = plan, let one = synced.first,
              case .measured(let drift) = one.drift
        else {
            good = false
            notes.append("\(name): \(describe(plan)) (plan \(String(format: "%.2f", wall)) s)")
            continue
        }
        let rate = ops.first { $0.name == "set_speed" }?.args["rate"] as? Double ?? .nan
        let ok = one.chosenBy == .confidence && drift.on == .phat && abs(rate * k - 1) <= 5e-6
        if !ok { good = false }
        notes.append(
            "\(name): z \(String(format: "%.2f", one.confidence)) by "
                + "\(one.chosenBy.rawValue), drift \(String(format: "%.2f", drift.ppm)) ppm on "
                + "\(drift.on.rawValue) over \(drift.windows) windows, set_speed "
                + "\(String(format: "%.7f", rate)) (want 1/k \(String(format: "%.7f", 1 / k)) "
                + "±5 ppm); plan \(String(format: "%.2f", wall)) s")
    }
    row("P18", good, notes.joined(separator: "; "))
}

// MARK: - P20 the waveform gate (SY-29)

/// `count` frames whose frame m is `weight`·anchor[m + lag] (where that
/// exists, fresh noise elsewhere) plus seeded noise: the lag is planted, and
/// `weight` sets how strongly it matches.
func plantedFrames(_ anchor: [Float], lag: Int, count: Int, weight: Float, seed: UInt64)
    -> [Float] {
    let shifted = shiftedFrames(anchor, by: lag, count: count, seed: seed)
    let noise = randomFrames(count, seed: seed + 1)
    return zip(shifted, noise).map { weight * $0 + $1 }
}

/// What `plan` should answer for a chosen match the gate refuses, written
/// from the spec: `find`'s choice, the coarse delta snap(zeroA − zeroN +
/// lag·9600), the played overlap it gives in anchor frames (the files'
/// overlap at the lag, rounded outward, when that is under 2 s), its region
/// (the centre 30 s; with `byEvidence`, SY-32's `refinementRegion` of the
/// same overlap), `refine` along the coarse lag, then `incoherent` or
/// `unconfirmed`; and the region's size. nil when `find` chose nothing.
func gateAnswer(_ anchor: AudioSync.Reading, _ mover: AudioSync.Reading, byEvidence: Bool = false)
    -> (reason: String, region: Int, played: Int, found: AudioSync.Found)? {
    gateRegions(anchor, mover, byEvidence: byEvidence).map {
        ($0.reason, $0.region.count, $0.played, $0.found)
    }
}

/// `gateAnswer` with the region itself and the old centred one beside it.
func gateRegions(_ anchor: AudioSync.Reading, _ mover: AudioSync.Reading, byEvidence: Bool)
    -> (reason: String, region: Range<Int>, centred: Range<Int>, played: Int,
        found: AudioSync.Found, refinement: AudioSyncPHAT.Refinement?)? {
    guard case .found(let found) = AudioSync.find(
        anchor: anchor, anchorFrames: anchor.features, anchorSpeech: nil, mover: mover,
        moverFrames: mover.features, moverSpeech: nil, fps: fps)
    else { return nil }
    let hop = SyncFeatures.hop
    let lagTicks = Ticks((found.lag * Double(step)).rounded())
    let coarse = ReelTime.snapToFrame(anchor.zero - mover.zero + lagTicks, fps: fps)
    func frame(_ ticks: Ticks) -> Int { Int((Double(ticks) / Double(step)).rounded(.down)) }
    let lower = max(0, frame(max(anchor.start, mover.start + coarse) - anchor.zero))
    let upper = max(lower, frame(min(anchor.end, mover.end + coarse) - anchor.zero))
    func centred(_ low: Int, _ high: Int) -> Range<Int> {
        let cap = AudioSyncPHAT.maximumRegionSamples
        guard high - low > cap else { return low..<high }
        let start = (low + high) / 2 - cap / 2
        return start..<(start + cap)
    }
    let line = AudioSyncPHAT.Line(intercept: found.lag * Double(hop), rate: 0)
    func chosen(_ lo: Int, _ hi: Int) -> Range<Int> {
        guard byEvidence else { return centred(lo * hop, hi * hop) }
        return AudioSync.refinementRegion(
            overlap: lo..<hi, anchorFrames: anchor.features, moverFrames: mover.features,
            anchorSpeech: nil, moverSpeech: nil, matchedOn: found.matchedOn, line: line)
    }
    var region = chosen(lower, upper)
    var old = centred(lower * hop, upper * hop)
    let played = region.count
    if region.count < AudioSyncPHAT.minimumRegionSamples {
        let lo = max(0, Int(found.lag.rounded(.down)))
        let hi = max(lo, min(anchor.features.count / width,
                             mover.features.count / width + Int(found.lag.rounded(.up))))
        region = chosen(lo, hi)
        old = centred(lo * hop, hi * hop)
    }
    let refinement = AudioSyncPHAT.refine(
        anchor: anchor.samples, anchorSpeed: 1, mover: mover.samples, moverSpeed: 1,
        line: line, region: region)
    let reason = refinement.map {
        AudioSync.incoherent(
            anchor: anchor.clip, mover: mover.clip, delta: coarse, confidence: found.confidence,
            refinement: $0)
    } ?? AudioSync.unconfirmed(
        anchor: anchor.clip, mover: mover.clip, delta: coarse, confidence: found.confidence)
    return (reason, region, old, played, found, refinement)
}

/// `reading` with `samples` in place of its own.
func withSamples(_ r: AudioSync.Reading, _ samples: [Int16]) -> AudioSync.Reading {
    AudioSync.Reading(
        clip: r.clip, media: r.media, trackIndex: r.trackIndex, start: r.start, end: r.end,
        zero: r.zero, hasVideo: r.hasVideo, samples: samples, features: r.features,
        speech: r.speech, neighbours: r.neighbours, speed: r.speed, sourceIn: r.sourceIn)
}

do {
    var good = true
    var notes: [String] = []
    var instrument = false
    let head = "no matching sound found between clip 1 and clip 2: moving clip 2 by "
    func plan(_ readings: [AudioSync.Reading]) -> AudioSync.Plan {
        AudioSync.plan(AudioSync.Input(readings: readings, problems: [], anchor: nil, fps: fps))
    }
    /// The refused case: the plan's reason equals `gateAnswer`'s, starts
    /// with `head` and names `words`.
    func gated(_ name: String, _ readings: [AudioSync.Reading], _ words: String) {
        let answer = plan(readings)
        let said = refusal(answer) ?? ""
        let want = gateAnswer(readings[0], readings[1])
        let ok = said == want?.reason && said.hasPrefix(head) && said.contains(words)
        if !ok { good = false }
        // The sentence after `head`, from "matches", is the part that varies.
        let tail = said.range(of: "matches their sound").map { String(said[$0.lowerBound...]) }
        notes.append(
            ok ? "\(name): refused as written, …\((tail ?? said).prefix(118))…"
                : "\(name): \(describe(answer)) (want: \(want?.reason ?? "nil"))")
    }

    // (a)–(d), (g): 30 s each. The anchor's frame a is the mover's a − 300
    // (4.8 s); the mover sits 60 frames (0.96 s) from the truth, so the
    // planted peak is the near placement. Its features carry the lag at
    // weight 0.03, under the confident tier; the coherent samples are pips
    // with the anchor 300·128 + 37.4 samples late.
    let frames = 1875
    let lag = 300
    let anchorFeatures = randomFrames(frames, seed: 201)
    let weakFeatures = plantedFrames(
        anchorFeatures, lag: lag, count: frames, weight: 0.03, seed: 202)
    let strongFeatures = shiftedFrames(anchorFeatures, by: lag, count: frames, seed: 204)
    let count = frames * SyncFeatures.hop
    let delay = Double(lag * SyncFeatures.hop) + 37.4
    let pips = Pips(seed: 205, samples: Double(count) + delay + 1000)
    let anchorPCM = pcm(pips.sample(count: count, c: -delay), noise: 0.003, seed: 206)
    let moverPCM = pcm(pips.sample(count: count), gain: 0.5, noise: 0.003, seed: 207)
    let unrelatedPCM = pcm(Pips(seed: 208, samples: Double(count) + 1000).sample(count: count),
                           gain: 0.5, noise: 0.003, seed: 209)
    let zero = Ticks(lag + 60) * step
    let anchorReading = reading(
        1, track: 0, start: 0, end: Ticks(frames) * step, zero: 0, video: true,
        samples: anchorPCM, features: anchorFeatures)
    func mover(_ features: [Float], _ samples: [Int16]) -> AudioSync.Reading {
        reading(2, track: 1, start: zero, end: zero + Ticks(frames) * step, zero: zero,
                samples: samples, features: features)
    }
    let near = AudioSyncMatch.search(
        anchor: anchorFeatures, mover: weakFeatures, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: Double(lag + 60))
    let nearZ = near?.nearPlacement?.z ?? 0
    let nearLag = near?.nearPlacement?.lag ?? .nan
    let notConfident = near.map { AudioSync.choose($0)?.1 == .placement } ?? false
    let weakControl = nearZ >= AudioSyncMatch.plausibleZ && nearZ < AudioSyncMatch.confidentZ
        && abs(nearLag - Double(lag)) <= 0.5 && notConfident
    if !weakControl { instrument = true }
    notes.append(
        "control: weak features' near peak lag \(String(format: "%.2f", nearLag)) z "
            + "\(String(format: "%.2f", nearZ)) (\(lag) ±0.5, 4 ≤ z < 10, by placement): "
            + "\(weakControl)")

    // (a) weak features, coherent samples: offered, the refinement clear.
    let a = plan([anchorReading, mover(weakFeatures, moverPCM)])
    if case .planned(_, let synced, _) = a, let one = synced.first {
        let ok = one.chosenBy == .placement && one.refinement?.clear == true
            && !AudioSync.weakMoves(synced).isEmpty
        if !ok { good = false }
        notes.append("(a) weak, coherent: \(one.chosenBy.rawValue), delta \(one.delta), "
            + "\(describe(one.refinement)), asked \(!AudioSync.weakMoves(synced).isEmpty)")
    } else {
        good = false
        notes.append("(a) weak, coherent: \(describe(a)) (want weak and clear)")
    }
    // (b) the same features, unrelated samples: the gate refuses.
    gated("(b) weak, unrelated samples", [anchorReading, mover(weakFeatures, unrelatedPCM)],
          "but their waveforms do not line up there (GCC-PHAT confidence ")
    // (c) confident features, unrelated samples: the gate refuses the
    // confident tier too.
    let strongResult = AudioSyncMatch.search(
        anchor: anchorFeatures, mover: strongFeatures, anchorSpeech: nil, moverSpeech: nil,
        offset: 0, placementLag: Double(lag + 60))
    let strongControl = strongResult.flatMap { AudioSync.choose($0) }?.1 == .confidence
    if !strongControl { instrument = true }
    notes.append(
        "control: strong features by confidence (z "
            + "\(String(format: "%.2f", strongResult?.candidates.first?.z ?? 0))): \(strongControl)")
    gated("(c) confident, unrelated samples", [anchorReading, mover(strongFeatures, unrelatedPCM)],
          "but their waveforms do not line up there (GCC-PHAT confidence ")
    // (d) the weak features with no samples at all: the features' tier stands.
    let d = plan([withSamples(anchorReading, []), mover(weakFeatures, [])])
    if case .planned(_, let synced, _) = d, let one = synced.first {
        let ok = one.chosenBy == .placement && one.refinement == nil
            && !AudioSync.weakMoves(synced).isEmpty
        if !ok { good = false }
        notes.append("(d) weak, no samples: \(one.chosenBy.rawValue), refinement "
            + "\(describe(one.refinement)), asked \(!AudioSync.weakMoves(synced).isEmpty)")
    } else {
        good = false
        notes.append("(d) weak, no samples: \(describe(d)) (want weak, unrefined)")
    }
    // (g) the fail-closed ruling: samples, but the mover's all 0 — the
    // refinement cannot run, so the match is refused, not offered.
    gated("(g) weak, the mover's samples all 0",
          [anchorReading, mover(weakFeatures, [Int16](repeating: 0, count: count))],
          "but they share too little sound there to confirm it is one recording")

    // (e) a confident whole-file match whose played spans meet for 1 s once
    // moved: the anchor plays [0, 9 s) of its file, the mover [0, 6 s) of a
    // file whose frame m is the anchor's m + 500, sitting 5,000 frames away
    // so no peak is near its placement. The played windows share 62 frames
    // at the true lag, under a candidate's 125, so the whole files choose;
    // the refinement runs over the files' overlap.
    let eLag = 500
    let eAnchorFeatures = randomFrames(frames, seed: 211)
    let eMoverFeatures = shiftedFrames(eAnchorFeatures, by: eLag, count: frames, seed: 212)
    let eDelay = Double(eLag * SyncFeatures.hop) + 21.3
    let ePips = Pips(seed: 213, samples: Double(count) + eDelay + 1000)
    let eAnchorPCM = pcm(ePips.sample(count: count, c: -eDelay), noise: 0.003, seed: 214)
    let eMoverPCM = pcm(ePips.sample(count: count), gain: 0.5, noise: 0.003, seed: 215)
    let eZero = Ticks(5000) * step
    let eAnchor = reading(
        1, track: 0, start: 0, end: 9 * ReelTime.perSecond, zero: 0, video: true,
        samples: eAnchorPCM, features: eAnchorFeatures)
    let eMover = reading(
        2, track: 1, start: eZero, end: eZero + 6 * ReelTime.perSecond, zero: eZero,
        samples: eMoverPCM, features: eMoverFeatures)
    let eWant = gateAnswer(eAnchor, eMover)
    let eControl = eWant.map {
        $0.played < AudioSyncPHAT.minimumRegionSamples && $0.found.search == .whole
            && $0.found.chosenBy == .confidence
    } ?? false
    if !eControl { instrument = true }
    let e = plan([eAnchor, eMover])
    if case .planned(_, let synced, _) = e, let one = synced.first, let w = eWant {
        let ok = one.search == .whole && one.chosenBy == .confidence
            && one.refinement?.clear == true && w.region >= AudioSyncPHAT.minimumRegionSamples
        if !ok { good = false }
        notes.append(
            "(e) played spans meeting for 1 s: \(one.search.rawValue)/"
                + "\(one.chosenBy.rawValue) z \(String(format: "%.2f", one.confidence)), "
                + "\(describe(one.refinement)), region \(w.region) samples; control: played "
                + "\(w.played) < \(AudioSyncPHAT.minimumRegionSamples): \(eControl)")
    } else {
        good = false
        notes.append("(e) whole files, played spans meeting for 1 s: \(describe(e)) (want "
            + "planned, clear; control \(eControl))")
    }
    gated("(e) with unrelated samples",
          [eAnchor, withSamples(eMover, unrelatedPCM)],
          "but their waveforms do not line up there (GCC-PHAT confidence ")

    // (f) the outward rounding (02's objection 1): two whole 188-frame
    // files, the mover's frames [0, 125) the anchor's [63, 188) — the
    // outermost lag a search scores — and its zero chosen so the snapped
    // played overlap is under 2 s: the refinement runs over the files'
    // overlap (≥ 125 frames, ≥ 16,000 samples) and is clear.
    let fFrames = 188
    let fLag = 63
    let fAnchorFeatures = randomFrames(fFrames, seed: 221)
    let fMoverFeatures = shiftedFrames(fAnchorFeatures, by: fLag, count: fFrames, seed: 222)
    let fCount = fFrames * SyncFeatures.hop
    let fPips = Pips(seed: 223, samples: Double(fCount) + Double(fLag * SyncFeatures.hop) + 1000)
    let fAnchorPCM = pcm(fPips.sample(count: fCount, c: -Double(fLag * SyncFeatures.hop)),
                         noise: 0.003, seed: 224)
    let fMoverPCM = pcm(fPips.sample(count: fCount), gain: 0.5, noise: 0.003, seed: 225)
    let fAnchor = reading(
        1, track: 0, start: 0, end: Ticks(fFrames) * step, zero: 0, video: true,
        samples: fAnchorPCM, features: fAnchorFeatures)
    var fChosen: (zero: Ticks, want: (reason: String, region: Int, played: Int, found: AudioSync.Found))?
    for z in stride(from: Ticks(0), to: 20_000, by: 200) {
        let candidate = reading(
            2, track: 1, start: z, end: z + Ticks(fFrames) * step, zero: z,
            samples: fMoverPCM, features: fMoverFeatures)
        if let w = gateAnswer(fAnchor, candidate), w.played < AudioSyncPHAT.minimumRegionSamples {
            fChosen = (z, w)
            break
        }
    }
    if let chosen = fChosen {
        let (fZero, w) = (chosen.zero, chosen.want)
        let fMover = reading(
            2, track: 1, start: fZero, end: fZero + Ticks(fFrames) * step, zero: fZero,
            samples: fMoverPCM, features: fMoverFeatures)
        let f = plan([fAnchor, fMover])
        let outermost = abs(w.found.lag - Double(fLag)) <= 0.5
        if !outermost { instrument = true }
        var ok = w.region >= AudioSyncPHAT.minimumRegionSamples
        var refined = "nil"
        if case .planned(_, let synced, _) = f, let one = synced.first {
            ok = ok && one.refinement?.clear == true
            refined = describe(one.refinement)
        } else {
            ok = false
        }
        if !ok { good = false }
        var answered = "refused"
        if case .planned(_, let synced, _) = f, let one = synced.first {
            answered = "\(one.chosenBy.rawValue) z \(String(format: "%.2f", one.confidence))"
        }
        notes.append(
            "(f) 188-frame files, the mover at \(fZero) ticks: \(answered), \(refined), "
                + "played \(w.played), region \(w.region) samples; control: lag "
                + "\(String(format: "%.3f", w.found.lag)) (want \(fLag) ±0.5): \(outermost)")
    } else {
        instrument = true
        notes.append("(f) no mover zero in [0, 20,000) ticks left a played overlap under 2 s")
    }
    row("P20", good, notes.joined(separator: "; "), instrument: instrument)
}

// MARK: - P21 the region chosen by the features (SY-32)

do {
    var good = true
    var notes: [String] = []
    var instrument = false
    // P17's construction over 54 s: the anchor holds the pips 9,632 samples
    // (1.204 s) after the mover. The mover's [12 s, 42 s) is replaced, so
    // the overlap's centre 30 s is the gap and the shared sound lies only
    // either side of it; its features are `SyncFeatures.frames` of the
    // edited samples. Under 60 s of overlap, so no drift: the line is the
    // coarse lag.
    let seconds = 54
    let delay = 9632.0
    let pips = Pips(seed: 401, samples: Double(seconds * 8000) + delay + 1000)
    let anchorPCM = pcm(pips.sample(count: seconds * 8000 + 9632, c: -delay), noise: 0.003,
                        seed: 411)
    let moverPCM = pcm(pips.sample(count: seconds * 8000), gain: 0.5, noise: 0.003, seed: 412)
    let truth = Ticks(delay) * AudioSyncPHAT.sampleTicks
    func gapped(_ level: Double) -> [Int16] {
        var out = moverPCM
        var noise = LCG(state: 402)
        for n in (12 * 8000)..<(42 * 8000) {
            out[n] = Int16((Double(noise.signed()) * level * 32767).rounded())
        }
        return out
    }
    func span(_ r: Range<Int>) -> String {
        String(format: "[%.3f s, %.3f s)", Double(r.lowerBound) / 8000, Double(r.upperBound) / 8000)
    }
    let anchor = pipsReading(1, track: 0, start: 0, samples: anchorPCM, video: true)
    for (name, level) in [("(a) noise at 0.1", 0.1), ("(b) room tone at −60 dBFS", 0.001)] {
        let mover = pipsReading(2, track: 1, start: 0, samples: gapped(level))
        let plan = AudioSync.plan(
            AudioSync.Input(readings: [anchor, mover], problems: [], anchor: nil, fps: fps))
        let written = gateRegions(anchor, mover, byEvidence: true)
        // The control: PHAT over the old centred 30 s of the same overlap.
        let old = written.flatMap { w in
            AudioSyncPHAT.refine(
                anchor: anchorPCM, anchorSpeed: 1, mover: mover.samples, moverSpeed: 1,
                line: AudioSyncPHAT.Line(intercept: w.found.lag * Double(SyncFeatures.hop), rate: 0),
                region: w.centred)
        }
        let control = old.map { !$0.clear } ?? false
        if !control { instrument = true }
        let region = written.map { span($0.region) } ?? "nil"
        let centred = written.map { span($0.centred) } ?? "nil"
        if case .planned(_, let synced, _) = plan, let one = synced.first {
            let ok = one.chosenBy == .confidence && one.refinement?.clear == true
                && abs(one.lag - truth) <= 75
            if !ok { good = false }
            notes.append(
                "\(name): offset \(one.lag) (want \(truth) ±75), \(one.chosenBy.rawValue) z "
                    + "\(String(format: "%.2f", one.confidence)), \(describe(one.refinement)), "
                    + "region \(region) of the anchor timeline; control: the centred "
                    + "\(centred) \(describe(old)) (want not clear: \(control))")
        } else {
            good = false
            notes.append("\(name): \(describe(plan)) (want planned, clear); region \(region); "
                + "control: the centred \(centred) \(describe(old)) (\(control))")
        }
    }
    // (c) (a)'s features with the anchor's samples unrelated pips: the gate
    // refuses, exactly as the plan's own numbers write it.
    let unrelated = pcm(Pips(seed: 403, samples: Double(seconds * 8000) + delay + 1000)
        .sample(count: seconds * 8000 + 9632), noise: 0.003, seed: 413)
    let cAnchor = withSamples(anchor, unrelated)
    let cMover = pipsReading(2, track: 1, start: 0, samples: gapped(0.1))
    let said = refusal(
        AudioSync.plan(
            AudioSync.Input(readings: [cAnchor, cMover], problems: [], anchor: nil, fps: fps)))
        ?? ""
    let want = gateRegions(cAnchor, cMover, byEvidence: true)
    let cOK = !said.isEmpty && said == want?.reason
        && said.contains("but their waveforms do not line up there (GCC-PHAT confidence ")
    if !cOK { good = false }
    notes.append(
        "(c) unrelated anchor samples: \(cOK ? "refused as written" : "NOT as written"), "
            + "region \(want.map { span($0.region) } ?? "nil"), "
            + (said.range(of: "(GCC-PHAT").map { String(said[$0.lowerBound...]) } ?? said)
            + (cOK ? "" : " (want: \(want?.reason ?? "nil"))"))
    row("P21", good, notes.joined(separator: "; "), instrument: instrument)
}

// MARK: - P24 the sync pass's resampler (SY-34)

do {
    var good = true
    var notes: [String] = []
    /// `samples` through a resampler at `rate`, in pieces of `piece` (the
    /// whole at once when nil), and its `finish`.
    func resampled(_ samples: [Float], rate: Double, piece: Int? = nil) -> [Float] {
        let resampler = SyncResampler(inputRate: rate)
        var out: [Float] = []
        let size = piece ?? max(samples.count, 1)
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + size)
            out += samples[start..<end].withUnsafeBufferPointer { resampler.feed($0) }
            start = end
        }
        return out + resampler.finish()
    }
    func same(_ a: [Float], _ b: [Float]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.bitPattern == $1.bitPattern }
    }
    // 44,099.5 Hz: a rate that is not whole, its phase rounded (SY-34).
    for rate in [48_000.0, 44_100.0, 16_000.0, 44_099.5] {
        let count = Int(rate) * 2
        // An impulse at input j: it lands at output 8000·j/rate, read as
        // the response's first moment over ±20 output samples.
        var placed: [String] = []
        for fraction in [0.3137, 0.7311] {
            let j = Int(rate * 2 * fraction)
            var impulse = [Float](repeating: 0, count: count)
            impulse[j] = 1
            let y = resampled(impulse, rate: rate)
            let want = 8000 * Double(j) / rate
            let lo = max(0, Int(want) - 20)
            let hi = min(y.count - 1, Int(want) + 21)
            var sum = 0.0
            var moment = 0.0
            for n in lo...hi {
                sum += Double(y[n])
                moment += Double(n) * Double(y[n])
            }
            let at = sum != 0 ? moment / sum : .nan
            let ok = abs(at - want) <= 0.05
            if !ok { good = false }
            placed.append("input \(j) at \(String(format: "%.4f", at)) (want "
                + "\(String(format: "%.4f", want)) ±0.05)")
        }
        // The count, and whole against pieces of 1, 777 and 4,096 samples.
        let noise = randomArray(count + 123, seed: 241).map { $0 * 0.5 }
        let whole = resampled(noise, rate: rate)
        let wantCount = Int((Double(noise.count) * 8000 / rate).rounded(.up))
        let pieces = [1, 777, 4096].map { same(whole, resampled(noise, rate: rate, piece: $0)) }
        let ok = whole.count == wantCount && pieces.allSatisfy { $0 }
        if !ok { good = false }
        notes.append(
            "\(String(format: "%g", rate)) Hz: \(placed.joined(separator: ", ")); "
                + "\(noise.count) samples give \(whole.count) (want ⌈N·8000/rate⌉ \(wantCount)); "
                + "pieces of 1, 777, 4096 identical to the whole: \(pieces)")
    }
    let noise = randomArray(8000 * 3 + 5, seed: 242)
    let identity = resampled(noise, rate: 8000)
    let identical = same(identity, noise) && same(resampled(noise, rate: 8000, piece: 777), noise)
    if !identical { good = false }
    notes.append("8000 Hz: the identity, whole and in pieces of 777: \(identical)")
    row("P24", good, notes.joined(separator: "; "))
}

// MARK: - P23 a file under one frame (SY-31)

do {
    var good = true
    var notes: [String] = []
    var instrument = false
    let manager = FileManager.default
    let dir = manager.temporaryDirectory.appendingPathComponent(
        "framejob-sync-probe-\(getpid())", isDirectory: true)
    try? manager.removeItem(at: dir)
    defer { try? manager.removeItem(at: dir) }
    try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
    typealias Cached = (marker: Bool, features: [Float]?, samples: [Int16]?, current: Bool)
    /// A 1 kHz tone at −6 dBFS, 16 kHz mono 16-bit, `count` samples, written
    /// by `AVAudioFile` and passed through the product's `writeSyncFeatures`
    /// into `<dir>/<name>/cache`: what the cache then holds.
    func cached(_ name: String, count: Int, id: UInt32) -> Cached? {
        let url = dir.appendingPathComponent("\(name).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        do {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0]
            else { return nil }
            buffer.frameLength = AVAudioFrameCount(count)
            let amplitude = pow(10, -6.0 / 20)
            for n in 0..<count {
                channel[n] = Float(amplitude * sin(2 * Double.pi * 1000 * Double(n) / 16_000))
            }
            guard let file = try? AVAudioFile(forWriting: url, settings: settings),
                  (try? file.write(from: buffer)) != nil
            else { return nil }
        }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return nil }
        let media = MediaSnapshot(
            id: id, path: url.path, kind: .audio,
            duration: Ticks(count) * ReelTime.perSecond / 16_000, hasVideo: false, hasAudio: true)
        guard let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url) else { return nil }
        let cache = dir.appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        MediaImporter.writeSyncFeatures(
            for: media, asset: asset, track: track, stamp: stamp, into: cache, pass: nil)
        return (
            MediaImporter.readSyncFeaturesStamp(
                at: MediaImporter.syncFeaturesMarkerURL(for: id, in: cache)) != nil,
            MediaImporter.loadSyncFeatures(for: id, in: cache),
            MediaImporter.loadSyncSamples(for: id, in: cache),
            MediaImporter.syncFeaturesAreCurrent(for: media, stamp: stamp, in: cache))
    }
    func said(_ c: Cached?) -> String {
        guard let c else { return "the fixture could not be written or read" }
        let frames = c.features.map { "\($0.count / width)" } ?? "nil"
        let samples = c.samples.map {
            "\($0.count) (frameCount \(SyncFeatures.frameCount(samples: $0.count)))"
        } ?? "nil"
        return "marker \(c.marker), frames \(frames), samples \(samples), current \(c.current)"
    }
    let short = cached("short", count: 640, id: 1)
    var shortOK = false
    if let c = short, let samples = c.samples {
        shortOK = c.marker && c.features == [] && SyncFeatures.frameCount(samples: samples.count) == 0
            && c.current
    }
    if !shortOK { good = false }
    notes.append("40 ms of a 1 kHz tone at −6 dBFS: \(said(short)) (want marker, 0 frames, "
        + "samples of frameCount 0, current)")
    let long = cached("long", count: 16_000, id: 2)
    var control = false
    if let c = long, let features = c.features, let samples = c.samples {
        let frames = SyncFeatures.frameCount(samples: samples.count)
        control = c.marker && frames > 0 && features.count / width == frames && c.current
    }
    if !control { instrument = true }
    notes.append("control, 1 s of the same tone: \(said(long)) (want frameCount(samples) frames: "
        + "\(control))")
    row("P23", good, notes.joined(separator: "; "), instrument: instrument)
}

emit()
