import AVFoundation
import AudioToolbox
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
// Touch every lazily initialised static the armed regions use, so no
// swift_once (and its dlsym) runs while a region is armed.
_ = (RTCheck.armFn, RTCheck.disarmFn, RTCheck.countsFn, RTCheck.resetTracesFn, RTCheck.dumpFn, timebase)
let ROOT = "/private/tmp/claude-501/-Users-kevingalligan-devel-framejob/9bb0487d-a352-45e3-9da8-07b6f4762c27/scratchpad/ap0/S1"
let SIG = ROOT + "/sig"
let OUT = ROOT + "/out"
let RODE = "/Users/kevingalligan/devel/framejob/.claude/worktrees/audio-updates/samples/Rode-usb-mic.m4a"
try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)

// MARK: - The settings under test (shared by own and Apple)

let HP = EQBand(kind: .highPass, freq: 80)
let PEAK = EQBand(kind: .peaking, freq: 1000, q: 1.4142135623730951, gainDB: 9)
let LS = EQBand(kind: .lowShelf, freq: 200, gainDB: 6)
let HS = EQBand(kind: .highShelf, freq: 8000, gainDB: 6)
let NOTCH = EQBand(kind: .notch, freq: 60, q: 10)
let EQSETS: [(String, [EQBand])] = [
    ("hpf2", [HP]), ("hpf4", RBJ.butterworth4HighPass(80)), ("peak", [PEAK]),
    ("lowshelf", [LS]), ("highshelf", [HS]), ("notch", [NOTCH]),
]
let EQ6: [EQBand] = RBJ.butterworth4HighPass(80) + [NOTCH, LS, PEAK, HS]

// AUPeakLimiter: 0 attack, 1 decay, 2 pre-gain. AUDynamicsProcessor: 0 threshold,
// 1 headroom, 2 expansion ratio, 3 expansion threshold, 4 attack, 5 release, 6 gain.
func limiterCfg(attack: Float? = nil) -> UnitConfig {
    var c = UnitConfig(label: "AUPeakLimiter", desc: AppleUnit.peakLimiter)
    if let attack { c.params = [(0, attack)]; c.label += String(format: " attack %.3f", attack) }
    return c
}
let EXPANDER_P: [(AudioUnitParameterID, Float)] = [(0, 20), (1, 40), (2, 2), (3, -50), (4, 0.001), (5, 0.1)]
let COMPRESSOR_P: [(AudioUnitParameterID, Float)] = [(0, -18), (1, 5), (2, 1), (4, 0.005), (5, 0.1)]
let BOTH_P: [(AudioUnitParameterID, Float)] = [(0, -18), (1, 5), (2, 2), (3, -50), (4, 0.005), (5, 0.1)]
let expanderCfg = UnitConfig(label: "AUDynamicsProcessor (expander)", desc: AppleUnit.dynamics, params: EXPANDER_P)
let compressorCfg = UnitConfig(label: "AUDynamicsProcessor (compressor)", desc: AppleUnit.dynamics, params: COMPRESSOR_P)
let bothCfg = UnitConfig(label: "AUDynamicsProcessor (exp+comp)", desc: AppleUnit.dynamics, params: BOTH_P)

/// Every subject by key. A fresh instance per call.
func subject(_ key: String) -> Stage? {
    let parts = key.split(separator: ".").map(String.init)
    switch (parts[0], parts.count > 1 ? parts[1] : "") {
    case ("own", "expander"): return OwnExpanderStage()
    case ("own", "compressor"): return OwnCompressorStage()
    case ("own", "limiter"): return OwnTruePeakLimiter2()
    case ("own", "limiter12"): return OwnTruePeakLimiterStage()
    case ("own", "limiterS"): return OwnTruePeakLimiter2(vectorDetector: false)
    case ("own", "limiter48"): return OwnTruePeakLimiter2(taps: 48, beta: 9)
    case ("own", "limiter64"): return OwnTruePeakLimiter2(taps: 64, beta: 10)
    case ("own", "limiter64a"): return OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true)
    case ("own", "limiter64aS"): return OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true)
    case ("own", "limiter64aT"):
        let l = OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true)
        l.tapOuter = true
        return l
    case ("own", "chain8T"):
        let l = OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true)
        l.tapOuter = true
        return ChainStage("own chain8 (tap-outer limiter)", [
            OwnBiquadStage("hpf4", bands: RBJ.butterworth4HighPass(80)),
            OwnBiquadStage("notch", bands: [NOTCH]), OwnBiquadStage("ls", bands: [LS]),
            OwnBiquadStage("peak", bands: [PEAK]), OwnBiquadStage("hs", bands: [HS]),
            OwnExpanderStage(), OwnCompressorStage(), l,
        ])
    case ("own", "chain8S"):
        return ChainStage("own chain8 (scalar limiter)", [
            OwnBiquadStage("hpf4", bands: RBJ.butterworth4HighPass(80)),
            OwnBiquadStage("notch", bands: [NOTCH]), OwnBiquadStage("ls", bands: [LS]),
            OwnBiquadStage("peak", bands: [PEAK]), OwnBiquadStage("hs", bands: [HS]),
            OwnExpanderStage(), OwnCompressorStage(),
            OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true),
        ])
    case ("own", "eq6"): return OwnBiquadStage("own eq6", bands: EQ6)
    case ("own", "eq6vdsp"): return OwnVDSPBiquadStage("own eq6 (vDSP_biquad)", bands: EQ6)
    case ("own", "chain8"):
        return ChainStage("own chain8", [
            OwnBiquadStage("hpf4", bands: RBJ.butterworth4HighPass(80)),
            OwnBiquadStage("notch", bands: [NOTCH]), OwnBiquadStage("ls", bands: [LS]),
            OwnBiquadStage("peak", bands: [PEAK]), OwnBiquadStage("hs", bands: [HS]),
            OwnExpanderStage(), OwnCompressorStage(), OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true),
        ])
    case ("own", let k):
        if let set = EQSETS.first(where: { $0.0 == k }) { return OwnBiquadStage("own \(k)", bands: set.1) }
    case ("au", "limiter"):
        if parts.count > 2, let a = Float(parts[2]) { return V2Host(limiterCfg(attack: a / 1000)) }
        return V2Host(limiterCfg())
    case ("au", "expander"): return V2Host(expanderCfg)
    case ("au", "compressor"): return V2Host(compressorCfg)
    case ("au", "dyn"): return V2Host(bothCfg)
    case ("au", "eq6"): return V2Host(.eq("AUNBandEQ eq6", EQ6))
    case ("au", "chain3"):
        return ChainStage("AU chain3", [V2Host(.eq("eq6", EQ6)), V2Host(bothCfg), V2Host(limiterCfg())])
    case ("au", "chain8"):
        return ChainStage("AU chain8", [
            V2Host(.eq("hpf4", RBJ.butterworth4HighPass(80))), V2Host(.eq("notch", [NOTCH])),
            V2Host(.eq("ls", [LS])), V2Host(.eq("peak", [PEAK])), V2Host(.eq("hs", [HS])),
            V2Host(expanderCfg), V2Host(compressorCfg), V2Host(limiterCfg()),
        ])
    case ("au", let k):
        if let set = EQSETS.first(where: { $0.0 == k }) { return V2Host(.eq("AUNBandEQ \(k)", set.1)) }
    case ("aveq", "eq6"): return AVEQv2Host("AVAudioUnitEQ eq6 (v2)", bands: EQ6)
    case ("aveq", let k):
        if let set = EQSETS.first(where: { $0.0 == k }) { return AVEQv2Host("AVAudioUnitEQ \(k) (v2)", bands: set.1) }
    case ("v3b", "limiter"): return try? V3Host(limiterCfg(), blockTyped: true)
    case ("v3b", "dyn"): return try? V3Host(bothCfg, blockTyped: true)
    case ("v3b", "peak"): return try? V3Host(.eq("AUNBandEQ peak", [PEAK]), blockTyped: true)
    case ("v3", "limiter"): return try? V3Host(limiterCfg())
    case ("v3", "dyn"): return try? V3Host(bothCfg)
    case ("v3", "peak"): return try? V3Host(.eq("AUNBandEQ peak", [PEAK]))
    case ("eng", "limiter"): return EngineHost("engine: AUPeakLimiter", [limiterCfg()])
    case ("eng", "eq6"): return EngineHost("engine: AVAudioUnitEQ eq6", [.eq("eq6", EQ6)])
    case ("eng", "chain3"): return EngineHost("engine: eq6 + dyn + limiter", [.eq("eq6", EQ6), bothCfg, limiterCfg()])
    default: break
    }
    return nil
}

let OWN_KEYS = EQSETS.map { "own.\($0.0)" } + ["own.eq6", "own.eq6vdsp", "own.expander", "own.compressor", "own.limiter", "own.limiter12", "own.limiterS", "own.limiter64a", "own.limiter64aS", "own.limiter64aT", "own.chain8", "own.chain8S", "own.chain8T"]
let AU_KEYS = EQSETS.map { "au.\($0.0)" } + ["au.eq6", "au.expander", "au.compressor", "au.dyn", "au.limiter", "au.chain3", "au.chain8"]
let OTHER_KEYS = ["aveq.eq6", "v3.limiter", "v3.dyn", "v3.peak", "v3b.limiter", "v3b.dyn", "v3b.peak", "eng.limiter", "eng.eq6", "eng.chain3"]

// MARK: - Commands

func cmdParams() {
    for (label, d) in [("AUPeakLimiter", AppleUnit.peakLimiter), ("AUDynamicsProcessor", AppleUnit.dynamics), ("AUNBandEQ", AppleUnit.nBandEQ)] {
        var dd = d
        var u: AudioUnit?
        AudioComponentInstanceNew(AudioComponentFindNext(nil, &dd)!, &u)
        guard let unit = u else { continue }
        var size: UInt32 = 0
        AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &size, nil)
        var ids = [AudioUnitParameterID](repeating: 0, count: Int(size) / 4)
        AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterList, kAudioUnitScope_Global, 0, &ids, &size)
        if label == "AUNBandEQ" {
            var nb: UInt32 = 0, s4 = UInt32(4)
            AudioUnitGetProperty(unit, kAUNBandEQProperty_NumberOfBands, kAudioUnitScope_Global, 0, &nb, &s4)
            var mx: UInt32 = 0
            s4 = 4
            AudioUnitGetProperty(unit, kAUNBandEQProperty_MaxNumberOfBands, kAudioUnitScope_Global, 0, &mx, &s4)
            print("\(label): default bands \(nb), max \(mx), \(ids.count) parameters (first 6 shown)")
            ids = Array(ids.prefix(6))
        } else {
            print("\(label): \(ids.count) parameters")
        }
        for id in ids {
            var info = AudioUnitParameterInfo()
            var isz = UInt32(MemoryLayout<AudioUnitParameterInfo>.size)
            AudioUnitGetProperty(unit, kAudioUnitProperty_ParameterInfo, kAudioUnitScope_Global, id, &info, &isz)
            let name = info.cfNameString.map { $0.takeUnretainedValue() as String } ?? "?"
            print(String(format: "  %5d %-28@ min %9.4f max %9.4f default %9.4f unit %d", id, name as NSString, info.minValue, info.maxValue, info.defaultValue, info.unit.rawValue))
        }
        var lat = 0.0, ls = UInt32(8)
        AudioUnitGetProperty(unit, kAudioUnitProperty_Latency, kAudioUnitScope_Global, 0, &lat, &ls)
        print("  reported latency (uninitialised) \(lat) s")
        AudioComponentInstanceDispose(unit)
    }
}

/// 1. Feasibility: every subject through the tap on the export path, armed.
func cmdFeas() {
    print("rtcheck loaded: \(RTCheck.available)")
    for file in ["white.caf", "white_stereo.caf"] {
        let src = Source(SIG + "/" + file)
        print("\n== \(file) (\(src.channels) ch) ==")
        let dry = readThroughTap(src, stage: nil, armSource: true)
        print(String(format: "%-34@ %@", "dry (GetSourceAudio armed)" as NSString, "source: \(dry.ctx!.source)"))
        print("   " + dry.ctx!.sizeSummary + ", prepare calls \(dry.ctx!.prepareCalls), process threads \(dry.ctx!.processThreads), invalid times \(dry.ctx!.invalidTimes)")
        let dryOut = dry.samples
        for key in OWN_KEYS + AU_KEYS + OTHER_KEYS {
            guard let s = subject(key) else { print("\(key): no subject"); continue }
            RTCheck.resetTraces()
            let r = readThroughTap(src, stage: s)
            let c = r.ctx!
            let changed = r.samples != dryOut
            let us = Double(c.stageNanos) / 1000 / Double(max(1, c.callbacks))
            print(String(format: "%-14@ first: %@ | steady: %@ | err %d (last %d) | prep %@ | changed %@ | %.1f µs/cb",
                         key as NSString, c.first.description, c.steady.description, c.errors, c.lastStatus,
                         (c.prepareError ?? "ok") as NSString, changed ? "yes" : "NO", us))
            if !c.steady.clean { RTCheck.dump(key) }
            if r.samples.count != dryOut.count { print("   length \(r.samples.count) vs dry \(dryOut.count)") }
        }
    }
}

/// 2. Determinism: two reads, and block-size invariance offline.
func cmdDet() {
    let keys = OWN_KEYS + AU_KEYS + OTHER_KEYS
    var lines: [String] = []
    for file in [RODE, SIG + "/white_stereo.caf"] {
        let src = Source(file)
        let name = (file as NSString).lastPathComponent
        print("\n== reads of \(name) ==")
        let dryA = readThroughTap(src, stage: nil), dryB = readThroughTap(src, stage: nil)
        print("dry               \(dryA.sha) \(dryB.sha) \(dryA.sha == dryB.sha ? "same" : "DIFFER")")
        lines.append("\(name) dry \(dryA.sha)")
        for key in keys {
            guard let s1 = subject(key), let s2 = subject(key) else { continue }
            let a = readThroughTap(src, stage: s1), b = readThroughTap(src, stage: s2)
            var note = ""
            if a.sha != b.sha {
                let diffs = zip(a.samples, b.samples).filter { $0 != $1 }.count
                let maxd = zip(a.samples, b.samples).map { abs($0 - $1) }.max() ?? 0
                note = String(format: " %d samples differ, max |Δ| %.3g (%.1f dBFS)", diffs, maxd, 20 * log10(Double(max(maxd, 1e-30))))
            }
            print(String(format: "%-16@ %@ %@ %@%@", key as NSString, a.sha, b.sha, a.sha == b.sha ? "same" : "DIFFER", note))
            lines.append("\(name) \(key) \(a.sha) \(b.sha)")
        }
    }
    // Block-size invariance, offline, on the RØDE decode gained +20 dB.
    print("\n== block-size invariance (RØDE decode +20 dB, offline) ==")
    let rode = readThroughTap(Source(RODE), stage: nil).samples.map { $0 * 10 }
    let patterns: [(String, [Int])] = [("1024", [1024]), ("4096", [4096]), ("irregular", [1, 7, 333, 4096, 128, 999, 2048, 17, 512, 3000])]
    for key in keys {
        var hashes: [String] = []
        var outs: [[Float]] = []
        for (_, p) in patterns {
            guard let s = subject(key) else { continue }
            let o = runOffline(s, input: rode, channels: 1, pattern: p)
            outs.append(o)
            hashes.append(sha(o))
        }
        let same = Set(hashes).count == 1
        var note = ""
        if !same, outs.count == 3, !outs[0].isEmpty {
            for j in 1..<3 where hashes[j] != hashes[0] {
                let maxd = zip(outs[0], outs[j]).map { abs($0 - $1) }.max() ?? 0
                let first = zip(outs[0], outs[j]).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1
                note += String(format: " [%@ vs 1024: max |Δ| %.3g (%.1f dBFS), first at %d]", patterns[j].0, maxd, 20 * log10(Double(max(maxd, 1e-30))), first)
            }
        }
        print(String(format: "%-16@ %@ %@%@", key as NSString, hashes.joined(separator: " "), same ? "same" : "DIFFER", note))
        lines.append("blocks \(key) \(hashes.joined(separator: " "))")
    }
    try! lines.joined(separator: "\n").write(toFile: OUT + "/det_\(getpid()).txt", atomically: true, encoding: .utf8)
    print("wrote det_\(getpid()).txt")
}

/// 3. EQ response: the stepped sine through the tap.
func cmdResp() {
    let src = Source(SIG + "/stepped.caf")
    writeF32(readThroughTap(src, stage: nil).samples, OUT + "/resp_dry.f32")
    for (k, _) in EQSETS {
        for prefix in ["own", "au", "aveq"] {
            let key = "\(prefix).\(k)"
            guard let s = subject(key) else { continue }
            let r = readThroughTap(src, stage: s)
            writeF32(r.samples, OUT + "/resp_\(key).f32")
            print("\(key): \(r.samples.count) samples, prep \(r.ctx!.prepareError ?? "ok"), err \(r.ctx!.errors)")
        }
    }
    // Coefficients for the analysis.
    var json: [String: Any] = [:]
    for (k, bands) in EQSETS {
        json[k] = bands.map { b -> [String: Any] in
            let s = RBJ.design(b, fs: 48000)
            return ["kind": b.kind.rawValue, "freq": b.freq, "q": b.q, "gain": b.gainDB, "octaves": b.octaves(fs: 48000),
                    "coef": [s.b0, s.b1, s.b2, s.a1, s.a2]]
        }
    }
    try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: OUT + "/resp_coeffs.json"))
}

/// 3b. Limiter: the RØDE file +28 dB and the crest signal.
func cmdLim() {
    let rode = Source(RODE), crest = Source(SIG + "/crest.caf")
    let cases: [(String, () -> Stage)] = [
        ("dry", { GainStage(db: 0) }),
        ("own", { OwnTruePeakLimiter2() }),
        ("own12", { OwnTruePeakLimiterStage() }),
        ("own48", { OwnTruePeakLimiter2(taps: 48, beta: 9) }),
        ("own64", { OwnTruePeakLimiter2(taps: 64, beta: 10) }),
        ("own64a", { OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true) }),
        ("au", { V2Host(limiterCfg()) }),
        ("au_trim", { ChainStage("au+trim", [V2Host(limiterCfg()), GainStage(db: -1)]) }),
        ("au_a1", { V2Host(limiterCfg(attack: 0.001)) }),
        ("au_a30", { V2Host(limiterCfg(attack: 0.03)) }),
    ]
    for (label, make) in cases {
        let a = readThroughTap(rode, stage: ChainStage("g", [GainStage(db: 28), make()]))
        writeF32(a.samples, OUT + "/lim_rode_\(label).f32")
        let b = readThroughTap(crest, stage: make())
        writeF32(b.samples, OUT + "/lim_crest_\(label).f32")
        print("\(label): rode \(a.samples.count) (\(a.ctx!.prepareError ?? "ok"), err \(a.ctx!.errors)), crest \(b.samples.count)")
    }
}

/// 4. Latency: white noise (EQs), quiet white noise (dynamics).
func cmdLat() {
    let white = Source(SIG + "/white.caf"), quiet = Source(SIG + "/white_quiet.caf")
    writeF32(readThroughTap(white, stage: nil).samples, OUT + "/lat_white_dry.f32")
    writeF32(readThroughTap(quiet, stage: nil).samples, OUT + "/lat_quiet_dry.f32")
    var report: [String] = []
    for key in OWN_KEYS + AU_KEYS + ["au.limiter.1", "au.limiter.30", "aveq.eq6", "v3.limiter", "eng.limiter", "eng.chain3"] {
        let dynamic = key.contains("limiter") || key.contains("expander") || key.contains("compressor") || key.contains("dyn") || key.contains("chain")
        for run in 1...2 {
            guard let s = subject(key) else { continue }
            let src = dynamic ? quiet : white
            let r = readThroughTap(src, stage: s)
            writeF32(r.samples, OUT + "/lat_\(dynamic ? "quiet" : "white")_\(key)_r\(run).f32")
            if run == 1 {
                var rep = ""
                if let v = s as? V2Host { rep = String(format: "%.6f s (%d samples)", v.reportedLatency, v.latency) }
                else if let c = s as? ChainStage {
                    rep = c.stages.map { st -> String in
                        if let v = st as? V2Host { return String(format: "%.6f", v.reportedLatency) }
                        return "\(st.latency)"
                    }.joined(separator: "+")
                } else { rep = "\(s.latency) samples (own claim)" }
                report.append("\(key)\t\(dynamic ? "quiet" : "white")\treported \(rep)")
            }
        }
    }
    try! report.joined(separator: "\n").write(toFile: OUT + "/lat_reported.txt", atomically: true, encoding: .utf8)
    print(report.joined(separator: "\n"))
}

/// 5. CPU: µs per 1024-frame buffer, offline, min of `runs`.
func cmdCPU(runs: Int, buffers: Int, only: String? = nil) {
    let rodeMono = readThroughTap(Source(RODE), stage: nil).samples.map { $0 * 10 }
    let stereo = readThroughTap(Source(SIG + "/white_stereo.caf"), stage: nil).samples
    let keys = (OWN_KEYS + AU_KEYS + ["aveq.eq6", "v3.limiter", "eng.limiter", "eng.chain3", "eng.eq6"]).filter { only == nil || $0.contains(only!) }
    var rows: [String] = []
    for channels in [1, 2] {
        let input = channels == 1 ? rodeMono : stereo
        let frames = input.count / channels
        let buf = PlanarBuffers(channels: channels, capacity: 4096)
        // Baseline: the copy-in alone.
        func copyIn(_ b: Int) {
            let start = (b * 1024) % (frames - 1024)
            buf.setFrames(1024)
            for c in 0..<channels {
                let d = buf.data[c]
                for i in 0..<1024 { d[i] = input[(start + i) * channels + c] }
            }
        }
        var baseline = Double.infinity
        for _ in 0..<3 {
            let t0 = nowNanos()
            for b in 0..<buffers { copyIn(b) }
            baseline = min(baseline, Double(nowNanos() - t0) / Double(buffers) / 1000)
        }
        print(String(format: "\n== %d ch, 1024 frames, %d buffers/run, copy baseline %.2f µs ==", channels, buffers, baseline))
        for key in keys {
            var best = Double.infinity
            var loads: [String] = []
            var failed: String?
            for _ in 0..<runs {
                guard let s = subject(key) else { failed = "no subject"; break }
                if let e = s.prepare(channels: channels, sampleRate: 48000, maxFrames: 4096) { failed = e; break }
                loads.append(loadAverage())
                // Warm-up.
                for b in 0..<50 { copyIn(b); _ = s.process(buf.abl, frames: 1024) }
                let t0 = nowNanos()
                for b in 0..<buffers {
                    copyIn(b)
                    let st = s.process(buf.abl, frames: 1024)
                    if st != 0 { failed = "status \(st)"; break }
                }
                let per = Double(nowNanos() - t0) / Double(buffers) / 1000 - baseline
                best = min(best, per)
            }
            if let failed { print("\(key): FAILED \(failed)"); continue }
            let pct = best / (1024.0 / 48000 * 1e6) * 100
            let line = String(format: "%-14@ %8.2f µs  %6.3f %% RT   load %@", key as NSString, best, pct, loads.joined(separator: " | ") as NSString)
            print(line)
            rows.append("\(channels)\t\(key)\t\(String(format: "%.3f", best))\t\(loads.joined(separator: " | "))")
        }
    }
    try! rows.joined(separator: "\n").write(toFile: OUT + "/cpu_\(getpid()).tsv", atomically: true, encoding: .utf8)
}

/// 6. Limits: formats, and a parameter step on a 1 kHz tone.
func cmdLimits() {
    print("== formats accepted at initialisation ==")
    for rate in [44100.0, 48000, 96000, 192000] {
        for ch in [1, 2, 6, 8] {
            var row = String(format: "%6.0f Hz %d ch:", rate, ch)
            for (label, make) in [("NBandEQ", { V2Host(.eq("eq", [PEAK])) as Stage }), ("PeakLimiter", { V2Host(limiterCfg()) }),
                                  ("Dynamics", { V2Host(bothCfg) }), ("own limiter", { OwnTruePeakLimiter2() }),
                                  ("own eq6", { OwnBiquadStage("eq6", bands: EQ6) })] {
                let s = make()
                let e = s.prepare(channels: ch, sampleRate: rate, maxFrames: 4096)
                var extra = ""
                if e == nil {
                    // Render one block of noise to prove it runs, and check it is finite.
                    let buf = PlanarBuffers(channels: ch, capacity: 4096)
                    buf.setFrames(1024)
                    for c in 0..<ch { for i in 0..<1024 { buf.data[c][i] = Float.random(in: -0.1...0.1) } }
                    let st = s.process(buf.abl, frames: 1024)
                    let finite = (0..<ch).allSatisfy { c in (0..<1024).allSatisfy { buf.abl[c].mData!.assumingMemoryBound(to: Float.self)[$0].isFinite } }
                    extra = st == 0 ? (finite ? "" : " NaN") : " render \(st)"
                    if let v = s as? V2Host { extra += String(format: " lat %.4f", v.reportedLatency) }
                }
                row += " \(label) \(e == nil ? "ok" : "FAIL(\(e!))")\(extra);"
            }
            print(row)
        }
    }

    print("\n== parameter step: 2 kHz peaking 0 → +12 dB at 2.000 s under a 1 kHz tone, 512-frame blocks ==")
    let tone = readThroughTap(Source(SIG + "/tone1k.caf"), stage: nil).samples
    let stepAt = 96256  // 188 × 512: a block boundary
    func run(_ label: String, _ s: Stage, step: (Stage) -> Void, smooth: Bool = false) {
        _ = s.prepare(channels: 1, sampleRate: 48000, maxFrames: 4096)
        let buf = PlanarBuffers(channels: 1, capacity: 4096)
        var out = [Float](repeating: 0, count: tone.count)
        var pos = 0
        while pos < tone.count {
            let n = min(512, tone.count - pos)
            if pos == stepAt { step(s) }
            buf.setFrames(n)
            for i in 0..<n { buf.data[0][i] = tone[pos + i] }
            _ = s.process(buf.abl, frames: n)
            for i in 0..<n { out[pos + i] = buf.abl[0].mData!.assumingMemoryBound(to: Float.self)[i] }
            pos += n
        }
        writeF32(out, OUT + "/zip_\(label).f32")
        print("wrote zip_\(label).f32")
    }
    let band0 = EQBand(kind: .peaking, freq: 2000, q: 1.4142135623730951, gainDB: 0)
    var band12 = band0
    band12.gainDB = 12
    run("none", OwnBiquadStage("p", bands: [band0])) { _ in }
    run("own_abrupt", OwnBiquadStage("p", bands: [band0])) { s in
        (s as! OwnBiquadStage).setSections([RBJ.design(band12, fs: 48000)])
    }
    run("own_smoothed", OwnSmoothedPeakingStage(band: band0, glideSeconds: 0.005)) { s in
        (s as! OwnSmoothedPeakingStage).targetDB = 12
    }
    run("au_abrupt", V2Host(.eq("p", [band0]))) { s in
        (s as! V2Host).setParameter(AudioUnitParameterID(kAUNBandEQParam_Gain), 12)
    }
    run("au_none", V2Host(.eq("p", [band0]))) { _ in }
    // The limiter's attack parameter changed mid-stream (a cut between two
    // clips with different settings): does the latency jump?
    let quiet = readThroughTap(Source(SIG + "/white_quiet.caf"), stage: nil).samples
    for (label, make) in [("au_limiter_attack_step", { V2Host(limiterCfg(attack: 0.001)) as Stage })] {
        let s = make()
        _ = s.prepare(channels: 1, sampleRate: 48000, maxFrames: 4096)
        let buf = PlanarBuffers(channels: 1, capacity: 4096)
        var out = [Float](repeating: 0, count: quiet.count)
        var pos = 0
        while pos < quiet.count {
            let n = min(512, quiet.count - pos)
            if pos == 144_384 { (s as! V2Host).setParameter(0, 0.03) }
            buf.setFrames(n)
            for i in 0..<n { buf.data[0][i] = quiet[pos + i] }
            _ = s.process(buf.abl, frames: n)
            for i in 0..<n { out[pos + i] = buf.abl[0].mData!.assumingMemoryBound(to: Float.self)[i] }
            pos += n
        }
        writeF32(out, OUT + "/zip_\(label).f32")
        writeF32(quiet, OUT + "/zip_quiet_dry.f32")
        print("wrote zip_\(label).f32 (attack 1 ms → 30 ms at sample 144384)")
    }
}

/// The instrument's positive control: things that MUST be counted.
func cmdControl() {
    let b = UnsafeMutablePointer<Int>.allocate(capacity: 5), a = UnsafeMutablePointer<Int>.allocate(capacity: 5)
    func probe(_ label: String, _ body: () -> Void) {
        var c = RTCounts()
        RTCheck.read(b); RTCheck.arm(); body(); RTCheck.disarm(); RTCheck.read(a)
        c.add(before: b, after: a)
        print(String(format: "%-34@ %@", label as NSString, c.description))
    }
    let lock = NSLock()
    var unfair = os_unfair_lock()
    let sem = DispatchSemaphore(value: 1)
    let q = DispatchQueue(label: "q")
    probe("nothing") {}
    probe("[Int](repeating:count: 1000)") { let x = [Int](repeating: 1, count: 1000); _ = x.count }
    probe("NSLock lock/unlock") { lock.lock(); lock.unlock() }
    probe("os_unfair_lock") { os_unfair_lock_lock(&unfair); os_unfair_lock_unlock(&unfair) }
    probe("DispatchSemaphore wait/signal") { sem.wait(); sem.signal() }
    probe("DispatchQueue.sync") { q.sync {} }
    probe("String interpolation") { let s = "x\(Int.random(in: 0...1000))y"; _ = s.count }
}

/// vDSP_biquad against the Double cascade under block patterns.
func cmdVDSP() {
    let rode = readThroughTap(Source(RODE), stage: nil).samples.map { $0 * 10 }
    let ref = runOffline(OwnVDSPBiquadStage("v", bands: [PEAK]), input: rode, channels: 1, pattern: [1024])
    for p in [[4096], [1, 1023], [2, 1022], [3, 1021], [4, 1020], [5, 1019], [7, 1017], [8, 1016], [16, 1008], [333, 691]] {
        let o = runOffline(OwnVDSPBiquadStage("v", bands: [PEAK]), input: rode, channels: 1, pattern: p)
        let maxd = zip(ref, o).map { abs($0 - $1) }.max() ?? 0
        let first = zip(ref, o).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1
        print("vDSP_biquad 1 section, pattern \(p): \(sha(o) == sha(ref) ? "same as [1024]" : String(format: "max |Δ| %.3g (%.1f dBFS) first at %d", maxd, 20 * log10(Double(max(maxd, 1e-30))), first))")
    }
}

/// The preview's path: the same composition and tap under a MUTED AVPlayer,
/// the tap's output captured, compared with the export path's output.
func cmdPreview(keys: [String], file: String, seconds: Double, skipInvalid: Bool = false, resetOnStart: Bool = false) {
    let src = Source(file)
    for key in keys {
        let stage: Stage? = key == "dry" ? nil : subject(key)
        let (comp, track) = src.composition()
        let ctx = TapCtx(stage: stage)
        ctx.skipInvalid = skipInvalid
        ctx.resetOnStart = resetOnStart
        let cap = Int((seconds + 2) * 48000) * src.channels
        ctx.capture = .allocate(capacity: cap)
        ctx.captureCap = cap
        let p = AVMutableAudioMixInputParameters(track: track)
        p.audioTapProcessor = TapFactory.make(ctx)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [p]
        let item = AVPlayerItem(asset: comp)
        item.audioMix = mix
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.play()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        player.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let n = min(ctx.callbacks, 100_000)
        var firstNumeric = -1, before = 0
        for i in 0..<n where ctx.starts[i] >= 0 { firstNumeric = i; break }
        if firstNumeric > 0 { for i in 0..<firstNumeric { before += Int(ctx.sizes[i]) } }
        let start0 = firstNumeric >= 0 ? Int(ctx.starts[firstNumeric]) - before : 0
        var contiguous = true
        var expect = Int64(start0)
        for i in 0..<n {
            if ctx.starts[i] >= 0, ctx.starts[i] != expect { contiguous = false }
            expect += Int64(ctx.sizes[i])
        }
        print("\n[\(key)] preview: \(ctx.sizeSummary), invalid times \(ctx.invalidTimes), first callback starts at sample \(start0), contiguous \(contiguous), threads \(ctx.processThreads), first \(ctx.first), steady \(ctx.steady), prep \(ctx.prepareError ?? "ok")")
        let exp = readThroughTap(src, stage: key == "dry" ? nil : subject(key))
        let ch = src.channels
        // Per callback: its own start (where valid) against the export path.
        var off = 0
        var compared = 0, diffs = 0
        var maxd: Float = 0
        var firstDiff = -1
        var notes: [String] = []
        for i in 0..<n {
            let frames = Int(ctx.sizes[i])
            defer { off += frames * ch }
            guard off + frames * ch <= ctx.captured else { break }
            if ctx.starts[i] < 0 {
                // The invalid-time callback: which export frames, if any, does it hold?
                var match = -1
                for cand in stride(from: 0, through: min(exp.samples.count / ch - frames, 48000), by: 1) {
                    if (0..<min(frames, 64)).allSatisfy({ ctx.capture![off + $0 * ch] == exp.samples[(cand + $0) * ch] }) { match = cand; break }
                }
                let silent = (0..<frames * ch).allSatisfy { ctx.capture![off + $0] == 0 }
                notes.append("callback \(i) (no valid time, \(frames) frames): \(silent ? "silent" : match >= 0 ? "equals export frames \(match)…" : "matches no export position (processed audio from a state the export never had)")")
                continue
            }
            let s0 = Int(ctx.starts[i])
            guard (s0 + frames) * ch <= exp.samples.count, s0 + frames <= 188_416 else { continue }
            for k in 0..<frames * ch {
                let dd = abs(ctx.capture![off + k] - exp.samples[s0 * ch + k])
                if dd != 0 { diffs += 1; if firstDiff < 0 { firstDiff = s0 + k / ch } }
                maxd = max(maxd, dd)
            }
            compared += frames * ch
        }
        notes.forEach { print("   " + $0) }
        print("   StartOfStream flag on callbacks \(Array(ctx.sosAt.prefix(ctx.sosCount))) (callback 0 is the no-valid-time pre-roll)")
        writeF32(Array(UnsafeBufferPointer(start: ctx.capture!, count: ctx.captured)), OUT + "/preview_\(key).f32")
        writeF32(exp.samples, OUT + "/preview_export_\(key).f32")
        let table = (0..<n).map { "\(ctx.starts[$0])\t\(ctx.sizes[$0])" }.joined(separator: "\n")
        try? table.write(toFile: OUT + "/preview_\(key)_callbacks.tsv", atomically: true, encoding: .utf8)
        print(String(format: "   compared %d samples (valid-time callbacks) with the export path: %d differ, max |Δ| %.3g (%.1f dBFS), first at frame %d", compared, diffs, maxd, 20 * log10(Double(max(maxd, 1e-30))), firstDiff))
    }
}

/// Is a stage's reset() (AudioUnitReset for the Apple hosts) real-time safe?
/// AudioTap calls reset on the render thread at StartOfStream and on a seek.
func cmdResetRT() {
    let b = UnsafeMutablePointer<Int>.allocate(capacity: 5), a = UnsafeMutablePointer<Int>.allocate(capacity: 5)
    for key in ["own.eq6", "own.expander", "own.compressor", "own.limiter64aT", "own.chain8T", "au.eq6", "au.dyn", "au.limiter", "au.chain3", "v3b.limiter", "eng.chain3"] {
        guard let s = subject(key) else { continue }
        _ = s.prepare(channels: 2, sampleRate: 48000, maxFrames: 4096)
        let buf = PlanarBuffers(channels: 2, capacity: 4096)
        buf.setFrames(512)
        for c in 0..<2 { for i in 0..<512 { buf.data[c][i] = Float.random(in: -0.5...0.5) } }
        _ = s.process(buf.abl, frames: 512)
        var first = RTCounts(), later = RTCounts()
        for round in 0..<5 {
            RTCheck.read(b); RTCheck.arm(); s.reset(); RTCheck.disarm(); RTCheck.read(a)
            if round == 0 { first.add(before: b, after: a) } else { later.add(before: b, after: a) }
            buf.setFrames(512)
            _ = s.process(buf.abl, frames: 512)
        }
        print(String(format: "%-16@ reset first: %@ | next 4: %@", key as NSString, first.description, later.description))
    }
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "params": cmdParams()
case "control": cmdControl()
case "resetrt": cmdResetRT()
case "preview": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6)
case "preview-reset": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6, resetOnStart: true)
case "preview-skip": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6, skipInvalid: true)
case "vdsp": cmdVDSP()
case "feas": cmdFeas()
case "det": cmdDet()
case "resp": cmdResp()
case "lim": cmdLim()
case "lat": cmdLat()
case "cpu": cmdCPU(runs: 3, buffers: args.count > 2 ? Int(args[2])! : 2000, only: args.count > 3 ? args[3] : nil)
case "limits": cmdLimits()
default: print("usage: s1 params|feas|det|resp|lim|lat|cpu [buffers]|limits")
}
