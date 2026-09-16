// fx_throughput.swift — q1 (synchronous offline render, × realtime per unit and
// for a four-unit chain) and q6 (the cost of re-rendering a 10 s window 30 s in).
//
// Build: xcrun swiftc -O -parse-as-library -target arm64-apple-macos15.0 \
//          fx_common.swift fx_throughput.swift -o ../work/effects_spike/fx_throughput
// Run from this directory (fixtures default to ../work/effects_spike/fx).

import AVFoundation
import Foundation

@main
struct Throughput {
    static func main() throws {
        print(hostLine())
        print("thread: main=\(Thread.isMainThread); no RunLoop is ever run; no async")
        let url = fixture("long60.wav")
        let file = try AVAudioFile(forReading: url)
        let frames = Int(file.length)
        let seconds = Double(frames) / file.processingFormat.sampleRate
        print("fixture long60.wav: \(frames) frames, \(file.processingFormat.channelCount) ch, \(file.processingFormat.sampleRate) Hz, \(seconds) s")

        let cases: [(String, () -> [AVAudioNode])] = [
            ("dry (player -> mixer)", { [] }),
            ("TimePitch +700", { [timePitch(700)] }),
            ("TimePitch -1200", { [timePitch(-1200)] }),
            ("TimePitch +1200 overlap 32", { [timePitch(1200, overlap: 32)] }),
            ("Reverb mediumHall wet50", { [reverb(.mediumHall)] }),
            ("Reverb cathedral wet50", { [reverb(.cathedral)] }),
            ("Delay 0.25s fb40 wet35", { [delay()] }),
            ("EQ 3 bands", { [eqThreeBand()] }),
            ("Distortion speechRadioTower", { [distortion(.speechRadioTower)] }),
            ("chain TimePitch->EQ->Distortion->Reverb", { [timePitch(700), eqThreeBand(), distortion(.speechRadioTower), reverb(.mediumHall)] }),
        ]

        print("\n== q1: 60 s file through scheduleFile, 4096-frame renderOffline calls, 3 runs each ==")
        print(pad("case", 42) + "setup ms   render s (3 runs)          x realtime (best)  statuses")
        for (name, make) in cases {
            var times: [Double] = []; var setup = 0.0; var st: [String: Int] = [:]; var len = 0
            for _ in 0..<3 {
                let r = try render(.file(url), frames: frames, makeUnits: make)
                times.append(r.renderSeconds); setup = r.setupSeconds; st = r.statuses; len = r.audio.frames
            }
            precondition(len == frames)
            let best = times.min()!
            print(pad(name, 42) + pad(String(format: "%.1f", setup * 1000), 11)
                  + pad(times.map { String(format: "%.3f", $0) }.joined(separator: " "), 27)
                  + pad(String(format: "%.0fx", seconds / best), 19) + "\(st)")
        }

        // The same chain from the other two sources, and with the file write a
        // cache would do (CAF float) included in the time.
        print("\n== q1: the chain from other sources, and including the file write ==")
        let mem = try readAudio(url)
        let chain = { [timePitch(700), eqThreeBand(), distortion(.speechRadioTower), reverb(.mediumHall)] as [AVAudioNode] }
        for (name, src) in [("scheduleBuffer", Source.buffer(mem)), ("AVAudioSourceNode", Source.sourceNode(mem))] {
            let r = try render(src, frames: frames, makeUnits: chain)
            print(pad(name, 22) + String(format: "render %.3f s  %.0fx realtime  %@", r.renderSeconds, seconds / r.renderSeconds, "\(r.statuses)"))
        }
        let t0 = now()
        let r = try render(.file(url), frames: frames, makeUnits: chain)
        let t1 = now()
        try writeAudio(r.audio, to: workDir().appendingPathComponent("chain60.caf"), kind: .cafFloat)
        let t2 = now()
        print(String(format: "file->chain->CAF float: engine+render %.3f s, write %.3f s, total %.0fx realtime", t1 - t0, t2 - t1, seconds / (t2 - t0)))

        // q6: a 10 s window 30 s in, cold (fresh engine, file opened) each time.
        print("\n== q6: 10 s window starting at 30 s via scheduleSegment, fresh engine each run ==")
        let start = AVAudioFramePosition(30 * 48000), count = AVAudioFrameCount(10 * 48000)
        let windows: [(String, () -> [AVAudioNode], Int)] = [
            ("TimePitch +700", { [timePitch(700)] }, 0),
            ("Reverb mediumHall + 3 s tail", { [reverb(.mediumHall)] }, 3 * 48000),
            ("chain (4 units) + 3 s tail", chain, 3 * 48000),
        ]
        for (name, make, tail) in windows {
            var rows: [String] = []
            for _ in 0..<5 {
                let a = now()
                let r = try render(.segment(url, start: start, count: count), frames: Int(count) + tail, makeUnits: make)
                let b = now()
                try writeAudio(r.audio, to: workDir().appendingPathComponent("window.caf"), kind: .cafFloat)
                let c = now()
                rows.append(String(format: "%.0f+%.0f+%.0f=%.0f", r.setupSeconds * 1000, r.renderSeconds * 1000, (c - b) * 1000, (c - a) * 1000))
            }
            print(pad(name, 30) + "setup+render+write ms: " + rows.joined(separator: "  "))
        }

        // Does the window equal the same span cut from a whole-file render?
        print("\n== q6: window render vs the same span of a whole-file render ==")
        for (name, make, st) in [("dry", { [] as [AVAudioNode] }, start), ("EQ 3 bands", { [eqThreeBand()] as [AVAudioNode] }, start),
                             ("TimePitch +700", { [timePitch(700)] as [AVAudioNode] }, start),
                             ("TimePitch +700 @4096k", { [timePitch(700)] as [AVAudioNode] }, AVAudioFramePosition(4096 * 352)),
                             ("TimePitch +700 @1024k", { [timePitch(700)] as [AVAudioNode] }, AVAudioFramePosition(1024 * 1407)),
                             ("Reverb mediumHall", { [reverb(.mediumHall)] as [AVAudioNode] }, start)] {
            let whole = try render(.file(url), frames: frames, makeUnits: make).audio.slice(Int(st), Int(count))
            let win = try render(.segment(url, start: st, count: count), frames: Int(count), makeUnits: make).audio
            let all = compare(whole, win)
            // After the first 0.5 s, when a stateful unit should have settled.
            let settled = compare(whole.slice(24000, Int(count) - 24000), win.slice(24000, Int(count) - 24000))
            print(pad(name + " from \(st)", 38) + "all: max |d| \(fmtDB(db(all.maxAbs))) dBFS, \(all.differing)/\(all.total) differ;  after 0.5 s: max |d| \(fmtDB(db(settled.maxAbs))) dBFS, \(settled.differing) differ")
        }
    }
}
