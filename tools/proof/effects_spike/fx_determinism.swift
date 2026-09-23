// fx_determinism.swift — q3: is an offline render byte-reproducible?
//
// Per unit: two fresh engines in one process; the render chunk size; the three
// ways of feeding the engine; four renders at once on four threads; and the
// bytes of the cache file a render would be written to (CAF float, WAV 16-bit,
// M4A AAC), written twice. Every digest is printed so a SECOND RUN of the
// program can be diffed against the first — the cross-process half.
//
// Build: xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
//          fx_common.swift fx_determinism.swift -o ../work/effects_spike/fx_determinism

import AVFoundation
import Foundation

@main
struct Determinism {
    static func main() throws {
        print(hostLine())
        let url = fixture("speech48s.wav")
        let mem = try readAudio(url)
        let frames = mem.frames + 2 * 48000   // two seconds of tail
        print("fixture speech48s.wav: \(mem.frames) frames; rendering \(frames) (input + 2 s)")

        let cases: [(String, () -> [AVAudioNode])] = [
            ("dry", { [] }),
            ("TimePitch +700", { [timePitch(700)] }),
            ("TimePitch -1200 overlap 32", { [timePitch(-1200, overlap: 32)] }),
            ("Reverb mediumHall wet50", { [reverb(.mediumHall)] }),
            ("Reverb cathedral wet50", { [reverb(.cathedral)] }),
            ("Reverb plate wet50", { [reverb(.plate)] }),
            ("Delay 0.25s fb40 wet35", { [delay()] }),
            ("Delay defaults", { [AVAudioUnitDelay()] }),
            ("EQ 3 bands", { [eqThreeBand()] }),
            ("Distortion speechRadioTower", { [distortion(.speechRadioTower)] }),
            ("Distortion multiDecimated4", { [distortion(.multiDecimated4)] }),
            ("Distortion speechAlienChatter", { [distortion(.speechAlienChatter)] }),
            ("chain TP->EQ->Dist->Reverb", { [timePitch(700), eqThreeBand(), distortion(.speechRadioTower), reverb(.mediumHall)] }),
        ]

        print("\n" + pad("case", 32) + pad("digest A", 18) + pad("B==A", 6) + pad("chunk1024", 10) + pad("chunk333", 9)
              + pad("buffer", 8) + pad("srcNode", 9) + pad("4threads", 9) + "worst |d| if any")
        for (name, make) in cases {
            let a = try render(.file(url), frames: frames, makeUnits: make).audio
            let b = try render(.file(url), frames: frames, makeUnits: make).audio
            var o1 = RenderOptions(); o1.chunk = 1024
            var o2 = RenderOptions(); o2.chunk = 333
            let c1 = try render(.file(url), frames: frames, options: o1, makeUnits: make).audio
            let c2 = try render(.file(url), frames: frames, options: o2, makeUnits: make).audio
            let bu = try render(.buffer(mem), frames: frames, makeUnits: make).audio
            let sn = try render(.sourceNode(mem), frames: frames, makeUnits: make).audio
            // Four at once.
            var par = [Audio?](repeating: nil, count: 4)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: 4) { i in
                let r = try? render(.file(url), frames: frames, makeUnits: make).audio
                lock.lock(); par[i] = r; lock.unlock()
            }
            func mark(_ x: Audio) -> String { x.digest == a.digest && x.frames == a.frames ? "yes" : "NO" }
            var worst = 0.0
            var notes: [String] = []
            for (label, x) in [("B", b), ("1024", c1), ("333", c2), ("buffer", bu), ("srcNode", sn)] + par.enumerated().map { ("t\($0.offset)", $0.element ?? Audio(channels: [[]], rate: 0)) } {
                if x.digest != a.digest {
                    let d = compare(a, x)
                    worst = max(worst, d.maxAbs)
                    var first = -1
                    outer: for i in 0..<min(a.frames, x.frames) { for c in 0..<a.channels.count where a.channels[c][i] != x.channels[c][i] { first = i; break outer } }
                    // Differences confined to the tail (past the input's end)?
                    let inSpan = compare(a.slice(0, mem.frames), x.slice(0, mem.frames))
                    notes.append("\(label): \(fmtDB(db(d.maxAbs))) dBFS, \(d.differing) samples, first frame \(first), within input span \(inSpan.differing)")
                }
            }
            let parOK = par.allSatisfy { $0.map(mark) == "yes" }
            print(pad(name, 32) + pad(a.digest, 18) + pad(mark(b), 6) + pad(mark(c1), 10) + pad(mark(c2), 9)
                  + pad(mark(bu), 8) + pad(mark(sn), 9) + pad(parOK ? "yes" : "NO", 9) + (notes.isEmpty ? "" : notes.joined(separator: "; ")))
        }

        // The cache file's bytes: the same render written twice per container.
        print("\n== the written file, twice (chain render) ==")
        let chain = try render(.file(url), frames: frames, makeUnits: cases.last!.1).audio
        let dir = workDir()
        for (kind, ext) in [(FileKind.cafFloat, "caf"), (.wavInt16, "wav"), (.m4aAAC, "m4a")] {
            let u1 = dir.appendingPathComponent("det1.\(ext)"), u2 = dir.appendingPathComponent("det2.\(ext)")
            try writeAudio(chain, to: u1, kind: kind)
            Thread.sleep(forTimeInterval: 1.1)   // so a timestamp in a header would change
            try writeAudio(chain, to: u2, kind: kind)
            let d1 = try Data(contentsOf: u1), d2 = try Data(contentsOf: u2)
            var firstDiff = -1
            if d1 != d2 { for i in 0..<min(d1.count, d2.count) where d1[i] != d2[i] { firstDiff = i; break } }
            let r1 = try readAudio(u1), r2 = try readAudio(u2)
            let samplesSame = r1.digest == r2.digest
            print(pad(ext, 5) + "bytes \(d1.count)/\(d2.count) identical=\(d1 == d2)" + (firstDiff >= 0 ? " (first differing byte \(firstDiff))" : "")
                  + "; decoded frames \(r1.frames)/\(r2.frames) identical=\(samplesSame)"
                  + (ext == "caf" ? "; decoded==render \(r1.digest == chain.digest)" : ""))
        }
    }
}
