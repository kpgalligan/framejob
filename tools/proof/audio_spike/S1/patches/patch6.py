import sys

d = sys.argv[1]
p = d + '/src/OwnLimiter2.swift'
s = open(p).read()
a = """                for ph in 0..<4 {
                    vDSP_conv(h + H - 6, 1, annex + ph * 12, 1, tmp, 1, len, 12)
                    vDSP_vabs(tmp, 1, tmp, 1, len)"""
b = """                for ph in 0..<4 {
                    let row = annex + ph * 12
                    if vectorDetector {
                        vDSP_conv(h + H - 6, 1, row, 1, tmp, 1, len, 12)
                    } else {
                        let base = h + H - 6
                        for i in 0..<frames {
                            var acc: Float = 0
                            for k in 0..<12 { acc += row[k] * base[i + k] }
                            tmp[i] = acc
                        }
                    }
                    vDSP_vabs(tmp, 1, tmp, 1, len)"""
assert a in s
s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ('    case ("own", "limiter64a"): return OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true)',
     '    case ("own", "limiter64a"): return OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true)\n'
     '    case ("own", "limiter64aS"): return OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true)\n'
     '    case ("own", "chain8S"):\n'
     '        return ChainStage("own chain8 (scalar limiter)", [\n'
     '            OwnBiquadStage("hpf4", bands: RBJ.butterworth4HighPass(80)),\n'
     '            OwnBiquadStage("notch", bands: [NOTCH]), OwnBiquadStage("ls", bands: [LS]),\n'
     '            OwnBiquadStage("peak", bands: [PEAK]), OwnBiquadStage("hs", bands: [HS]),\n'
     '            OwnExpanderStage(), OwnCompressorStage(),\n'
     '            OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true),\n'
     '        ])'),
    ('"own.limiter64a", "own.chain8"]', '"own.limiter64a", "own.limiter64aS", "own.chain8", "own.chain8S"]'),
    ('let args = CommandLine.arguments',
     '''/// vDSP_biquad against the Double cascade under block patterns.
func cmdVDSP() {
    let rode = readThroughTap(Source(RODE), stage: nil).samples.map { $0 * 10 }
    let ref = runOffline(OwnVDSPBiquadStage("v", bands: [PEAK]), input: rode, channels: 1, pattern: [1024])
    for p in [[4096], [1, 1023], [2, 1022], [3, 1021], [4, 1020], [5, 1019], [7, 1017], [8, 1016], [16, 1008], [333, 691]] {
        let o = runOffline(OwnVDSPBiquadStage("v", bands: [PEAK]), input: rode, channels: 1, pattern: p)
        let maxd = zip(ref, o).map { abs($0 - $1) }.max() ?? 0
        let first = zip(ref, o).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1
        print("vDSP_biquad 1 section, pattern \\(p): \\(sha(o) == sha(ref) ? "same as [1024]" : String(format: "max |Δ| %.3g (%.1f dBFS) first at %d", maxd, 20 * log10(Double(max(maxd, 1e-30))), first))")
    }
}

let args = CommandLine.arguments'''),
    ('case "control": cmdControl()', 'case "control": cmdControl()\ncase "vdsp": cmdVDSP()'),
]
for a, b in rep:
    assert a in s, a[:50]
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
