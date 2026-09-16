// fx_alignment.swift — q4 (is the wet signal sample-aligned with the dry, is it
// the same length, where do tails go, what latency does each unit report) and
// q5 (TimePitch at ±12 semitones and beyond, and what `overlap` changes).
//
// Build: xcrun swiftc -O -parse-as-library -target arm64-apple-macos15.0 \
//          fx_common.swift fx_alignment.swift -o ../work/effects_spike/fx_alignment

import AVFoundation
import Accelerate
import Foundation

/// Burst k's onset in bursts.wav / clicks.wav: 0.25 s + k × 0.5 s.
func burstOnset(_ k: Int) -> Int { 12000 + 24000 * k }

/// Per burst: the first frame whose |x| exceeds 25 % of that burst window's
/// peak, and the energy centroid over [onset − 50 ms, onset + 150 ms).
func burstTimes(_ x: [Float]) -> [(onset: Double, centroid: Double)] {
    var out: [(Double, Double)] = []
    for k in 0..<20 {
        let a = burstOnset(k) - 2400, b = burstOnset(k) + 7200
        guard b <= x.count else { break }
        let w = Array(x[a..<b])
        let pk = vDSP.maximumMagnitude(w)
        guard pk > 0 else { out.append((.nan, .nan)); continue }
        let onset = w.firstIndex { abs($0) >= 0.25 * pk }!
        var e = 0.0, te = 0.0
        for (i, v) in w.enumerated() { let p = Double(v * v); e += p; te += Double(i) * p }
        out.append((Double(a + onset), Double(a) + te / e))
    }
    return out
}

func median(_ v: [Double]) -> Double {
    let s = v.filter { !$0.isNaN }.sorted()
    return s.isEmpty ? .nan : s[s.count / 2]
}

func leadingQuiet(_ a: Audio, _ threshold: Float = 1e-4) -> Int {
    a.channels.map { $0.firstIndex { abs($0) > threshold } ?? $0.count }.min() ?? 0
}

@main
struct Alignment {
    static func main() throws {
        print(hostLine())
        let bursts = fixture("bursts.wav"), clicks = fixture("clicks.wav"), speech = fixture("speech48s.wav"), tone = fixture("tone220.wav")
        let burstIn = try readAudio(bursts), speechIn = try readAudio(speech)
        let extra = 3 * 48000

        // --- Reported latency and tail, before and after the engine starts.
        print("\n== reported latency / tailTime (AVAudioNode.latency, AUAudioUnit.latency, AUAudioUnit.tailTime; s) ==")
        let reportCases: [(String, () -> AVAudioUnit)] = [
            ("TimePitch +700", { timePitch(700) }), ("TimePitch +1200 overlap 32", { timePitch(1200, overlap: 32) }),
            ("Reverb mediumHall", { reverb(.mediumHall) }), ("Reverb cathedral", { reverb(.cathedral) }),
            ("Delay 0.25", { delay() }), ("EQ 3 bands", { eqThreeBand() }), ("Distortion speechRadioTower", { distortion(.speechRadioTower) }),
        ]
        for (name, make) in reportCases {
            let u = make()
            let before = "node \(u.latency) au \(u.auAudioUnit.latency) tail \(u.auAudioUnit.tailTime)"
            var during = ""
            _ = try render(.file(speech), frames: 4096, afterStart: { _ in
                during = "node \(u.latency) au \(u.auAudioUnit.latency) tail \(u.auAudioUnit.tailTime)"
            }) { [u] }
            print(pad(name, 30) + "unattached: \(before)   |   running: \(during)")
        }

        // --- Alignment.
        let cases: [(String, () -> [AVAudioNode])] = [
            ("dry", { [] }),
            ("TimePitch 0 c rate 1", { [timePitch(0)] }),
            ("TimePitch +700", { [timePitch(700)] }),
            ("TimePitch -700", { [timePitch(-700)] }),
            ("TimePitch +1200", { [timePitch(1200)] }),
            ("TimePitch -1200", { [timePitch(-1200)] }),
            ("TimePitch +1200 then -1200", { [timePitch(1200), timePitch(-1200)] }),
            ("TimePitch +700 then -700", { [timePitch(700), timePitch(-700)] }),
            ("TimePitch +700 overlap 32", { [timePitch(700, overlap: 32)] }),
            ("TimePitch +700 overlap 3", { [timePitch(700, overlap: 3)] }),
            ("Reverb mediumHall wet0", { [reverb(.mediumHall, wet: 0)] }),
            ("Reverb mediumHall wet50", { [reverb(.mediumHall)] }),
            ("Reverb cathedral wet100", { [reverb(.cathedral, wet: 100)] }),
            ("Delay 0.25 fb40 wet0", { [delay(wet: 0)] }),
            ("Delay 0.25 fb40 wet35", { [delay()] }),
            ("EQ 3 bands", { [eqThreeBand()] }),
            ("Distortion multiDistortedCubed", { [distortion(.multiDistortedCubed)] }),
            ("Distortion speechRadioTower", { [distortion(.speechRadioTower)] }),
            ("chain TP->EQ->Dist->Reverb", { [timePitch(700), eqThreeBand(), distortion(.speechRadioTower), reverb(.mediumHall)] }),
        ]
        let dryBursts = burstTimes(burstIn.channels[0])
        let dryClickPeaks = (0..<20).map { burstOnset($0) }
        let drySpeech = try render(.file(speech), frames: speechIn.frames + extra) { [] }.audio
        let dryEnv = envelope(drySpeech.channels[0])
        let dryEnd60 = lastAbove(drySpeech, Float(pow(10, -60.0 / 20)))
        print("\n== q4 alignment: lags in FRAMES at 48 kHz, positive = wet LATE ==")
        print("   burst onset/centroid: median over 20 Hann bursts (10 ms of 1 kHz); click peak: median lag of the largest |sample| near each impulse;")
        print("   speech xcorr: waveform over 1–3 s, ch0, ±4800; envelope: 1 ms |x| box, same span; lead: frames before |x|>1e-4 (dry \(leadingQuiet(drySpeech)));")
        print("   end: last sample above −60 dBFS minus the dry's (\(dryEnd60)), in ms; renders are input + 3 s, length = frames asked for")
        print(pad("case", 32) + pad("onset", 7) + pad("centroid", 9) + pad("click", 7) + pad("xcorr (r)", 16) + pad("env (r)", 16) + pad("lead", 7) + pad("end ms", 8) + pad("frames out", 11) + pad("identical to dry?", 30) + "per-burst centroid lag min…max")
        for (name, make) in cases {
            let wb = try render(.file(bursts), frames: burstIn.frames + extra, makeUnits: make).audio
            let bt = burstTimes(wb.channels[0])
            let onsetLag = median(zip(bt, dryBursts).map { $0.0.onset - $0.1.onset })
            let centroidLags = zip(bt, dryBursts).map { $0.0.centroid - $0.1.centroid }
            let centroidLag = median(centroidLags)
            let spread = String(format: "%.1f…%.1f", centroidLags.min() ?? .nan, centroidLags.max() ?? .nan)
            let wc = try render(.file(clicks), frames: burstIn.frames + extra, makeUnits: make).audio
            let clickLag = median(dryClickPeaks.map { p -> Double in
                let w = wc.channels[0][(p - 2400)..<(p + 4800)]
                var bi = 0; var bv: Float = -1
                for (i, v) in w.enumerated() where abs(v) > bv { bv = abs(v); bi = i }
                return Double(bi - 2400)
            })
            let ws = try render(.file(speech), frames: speechIn.frames + extra, makeUnits: make).audio
            let xc = xcorrLag(drySpeech.channels[0], ws.channels[0], from: 48000, len: 96000, maxLag: 4800)
            let ec = xcorrLag(dryEnv, envelope(ws.channels[0]), from: 48000, len: 96000, maxLag: 4800)
            let end60 = lastAbove(ws, Float(pow(10, -60.0 / 20)))
            let same = ws.digest == drySpeech.digest ? "yes" : String(format: "no (max |d| %@ dBFS)", fmtDB(db(compare(ws, drySpeech).maxAbs)))
            print(pad(name, 32) + pad(String(format: "%.0f", onsetLag), 7) + pad(String(format: "%.1f", centroidLag), 9) + pad(String(format: "%.0f", clickLag), 7)
                  + pad(String(format: "%d (%.2f)", xc.lag, xc.r), 16) + pad(String(format: "%d (%.2f)", ec.lag, ec.r), 16)
                  + pad("\(leadingQuiet(ws))", 7) + pad(String(format: "%.0f", Double(end60 - dryEnd60) * 1000 / 48000), 8)
                  + pad("\(ws.frames)", 11) + pad(same, 30) + spread)
        }

        // --- Tails: keep rendering after the player has run out.
        print("\n== q4 tails: speech (input ends at frame \(speechIn.frames)), rendered input + 25 s; energy past the end ==")
        for (name, make) in [("Reverb cathedral wet100", { [reverb(.cathedral, wet: 100)] as [AVAudioNode] }),
                             ("Reverb mediumHall wet50", { [reverb(.mediumHall)] as [AVAudioNode] }),
                             ("Reverb smallRoom wet50", { [reverb(.smallRoom)] as [AVAudioNode] }),
                             ("Delay defaults (1 s, fb 50, wet 100)", { [AVAudioUnitDelay()] as [AVAudioNode] }),
                             ("Delay 0.25 fb40 wet35", { [delay()] as [AVAudioNode] }),
                             ("Delay 0.5 fb90 wet50", { [delay(time: 0.5, feedback: 90, wet: 50)] as [AVAudioNode] })] {
            let r = try render(.file(speech), frames: speechIn.frames + 25 * 48000, makeUnits: make)
            let a = r.audio
            let past = a.slice(speechIn.frames, a.frames - speechIn.frames)
            var marks: [String] = []
            for t in [-40.0, -60.0, -90.0, -120.0] {
                let i = lastAbove(past, Float(pow(10, t / 20)))
                marks.append("\(Int(t)) dBFS until +\(i < 0 ? "0" : String(format: "%.2f", Double(i) / 48000)) s")
            }
            let exactZeroFrom = (0..<past.frames).reversed().first { i in past.channels.contains { $0[i] != 0 } }.map { $0 + 1 } ?? 0
            print(pad(name, 38) + marks.joined(separator: ", ") + String(format: "; last non-zero sample +%.2f s; reported tailTime %.2f s; statuses %@",
                  Double(exactZeroFrom) / 48000, (r.units.first as? AVAudioUnit)?.auAudioUnit.tailTime ?? -1, "\(r.statuses)"))
        }

        // --- q5: pitch accuracy on a 220 Hz tone, and what overlap does.
        print("\n== q5 TimePitch on tone220.wav (5 s): dominant frequency of 65536 frames from 1.0 s ==")
        print(pad("pitch c", 9) + pad("readback", 10) + pad("expect Hz", 11) + "overlap 3 | 8 | 32: measured Hz (error cents), dRMS dB, render ms")
        let toneIn = try readAudio(tone)
        for cents: Float in [-2400, -1200, -700, 0, 700, 1200, 2400, 3000, -3000] {
            var cols: [String] = []
            var readback: Float = 0
            for ov: Float in [3, 8, 32] {
                let u = timePitch(cents, overlap: ov); readback = u.pitch
                let r = try render(.file(tone), frames: toneIn.frames, makeUnits: { [u] })
                let hz = dominantHz(r.audio.channels[0], rate: 48000, from: 48000)
                let expect = 220 * pow(2, Double(max(-2400, min(2400, cents))) / 1200)
                let err = 1200 * log2(hz / expect)
                cols.append(String(format: "%.2f (%+.1f), %+.2f, %.0f", hz, err, db(rms(r.audio.slice(48000, 96000))) - db(rms(toneIn.slice(48000, 96000))), r.renderSeconds * 1000))
            }
            print(pad(String(format: "%.0f", cents), 9) + pad(String(format: "%.0f", readback), 10)
                  + pad(String(format: "%.2f", 220 * pow(2, Double(max(-2400, min(2400, cents))) / 1200)), 11) + cols.joined(separator: " | "))
        }

        print("\n== q5 TimePitch on speech: spectral centroid, RMS, and how far apart the overlap settings are ==")
        let drySp = spectrum(speechIn.channels[0], rate: 48000)
        print(String(format: "dry: centroid %.0f Hz, RMS %.2f dBFS", drySp.centroidHz, db(rms(speechIn))))
        for cents: Float in [-1200, 1200, -2400, 2400] {
            var outs: [(Float, Audio, Double)] = []
            for ov: Float in [3, 8, 32] {
                let r = try render(.file(speech), frames: speechIn.frames, makeUnits: { [timePitch(cents, overlap: ov)] })
                outs.append((ov, r.audio, r.renderSeconds))
            }
            let base = outs[1].1
            let line = outs.map { o -> String in
                let sp = spectrum(o.1.channels[0], rate: 48000)
                let d = compare(o.1, base)
                return String(format: "ov %.0f: centroid %.0f Hz (x%.2f), RMS %+.2f dB, vs ov8 max |d| %@ dBFS / RMS diff %@ dBFS, %.0f ms",
                              o.0, sp.centroidHz, sp.centroidHz / drySp.centroidHz, db(rms(o.1)) - db(rms(speechIn)), fmtDB(db(d.maxAbs)),
                              fmtDB(db(rms(Audio(channels: zip(o.1.channels, base.channels).map { vDSP.subtract($0.0, $0.1) }, rate: 48000)))), o.2 * 1000)
            }
            print(String(format: "%+.0f c: ", cents) + line.joined(separator: "\n        "))
        }
        // The two TimePitch parameters AVAudioUnitTimePitch does not surface.
        print("\n== q5 the hidden TimePitch parameters (Spectral Coherence, Preserve Transients) on speech +1200 ==")
        let ref = try render(.file(speech), frames: speechIn.frames, makeUnits: { [timePitch(1200)] }).audio
        for (label, addr, v) in [("Spectral Coherence = 0", UInt64(6), AUValue(0)), ("Preserve Transients = 0", UInt64(7), AUValue(0))] {
            let u = timePitch(1200)
            u.auAudioUnit.parameterTree?.parameter(withAddress: addr)?.value = v
            let r = try render(.file(speech), frames: speechIn.frames, makeUnits: { [u] }).audio
            let d = compare(r, ref)
            print(pad(label, 26) + String(format: "differs from default: %@ (max |d| %@ dBFS); centroid %.0f Hz", d.differing > 0 ? "yes" : "no", fmtDB(db(d.maxAbs)), spectrum(r.channels[0], rate: 48000).centroidHz))
        }
        let dir = workDir()
        for c: Float in [-1200, 1200] {
            let r = try render(.file(speech), frames: speechIn.frames, makeUnits: { [timePitch(c)] }).audio
            try writeAudio(r, to: dir.appendingPathComponent("speech_pitch\(Int(c)).caf"), kind: .cafFloat)
        }
    }
}
