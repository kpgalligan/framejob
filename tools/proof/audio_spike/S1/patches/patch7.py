import sys

d = sys.argv[1]
p = d + '/src/OwnLimiter2.swift'
s = open(p).read()
rep = [
    ("    let annexToo: Bool\n",
     "    let annexToo: Bool\n"
     "    /// Scalar arithmetic in a fixed order per output (tap 0 first), with\n"
     "    /// the TAP loop outermost so the compiler vectorises across samples:\n"
     "    /// bit-identical to the scalar loop, and invariant to block size.\n"
     "    var tapOuter = false\n"),
    ("""                if vectorDetector {
                    vDSP_conv(h, 1, row, 1, tmp, 1, len, vDSP_Length(taps))
                } else {""",
     """                if tapOuter {
                    tmp.update(repeating: 0, count: frames)
                    for k in 0..<taps {
                        let c = row[k]
                        let src = h + k
                        for i in 0..<frames { tmp[i] += c * src[i] }
                    }
                } else if vectorDetector {
                    vDSP_conv(h, 1, row, 1, tmp, 1, len, vDSP_Length(taps))
                } else {"""),
    ("""                    if vectorDetector {
                        vDSP_conv(h + H - 6, 1, row, 1, tmp, 1, len, 12)
                    } else {""",
     """                    if tapOuter {
                        let base = h + H - 6
                        tmp.update(repeating: 0, count: frames)
                        for k in 0..<12 {
                            let c = row[k]
                            let src = base + k
                            for i in 0..<frames { tmp[i] += c * src[i] }
                        }
                    } else if vectorDetector {
                        vDSP_conv(h + H - 6, 1, row, 1, tmp, 1, len, 12)
                    } else {"""),
]
for a, b in rep:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ('    case ("own", "chain8S"):',
     '    case ("own", "limiter64aT"):\n'
     '        let l = OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true)\n'
     '        l.tapOuter = true\n'
     '        return l\n'
     '    case ("own", "chain8T"):\n'
     '        let l = OwnTruePeakLimiter2(taps: 64, beta: 10, vectorDetector: false, annexToo: true)\n'
     '        l.tapOuter = true\n'
     '        return ChainStage("own chain8 (tap-outer limiter)", [\n'
     '            OwnBiquadStage("hpf4", bands: RBJ.butterworth4HighPass(80)),\n'
     '            OwnBiquadStage("notch", bands: [NOTCH]), OwnBiquadStage("ls", bands: [LS]),\n'
     '            OwnBiquadStage("peak", bands: [PEAK]), OwnBiquadStage("hs", bands: [HS]),\n'
     '            OwnExpanderStage(), OwnCompressorStage(), l,\n'
     '        ])\n'
     '    case ("own", "chain8S"):'),
    ('"own.limiter64a", "own.limiter64aS", "own.chain8", "own.chain8S"]',
     '"own.limiter64a", "own.limiter64aS", "own.limiter64aT", "own.chain8", "own.chain8S", "own.chain8T"]'),
    ('func cmdCPU(runs: Int, buffers: Int) {', 'func cmdCPU(runs: Int, buffers: Int, only: String? = nil) {'),
    ('    let keys = OWN_KEYS + AU_KEYS + ["aveq.eq6", "v3.limiter", "eng.limiter", "eng.chain3", "eng.eq6"]\n    var rows',
     '    let keys = (OWN_KEYS + AU_KEYS + ["aveq.eq6", "v3.limiter", "eng.limiter", "eng.chain3", "eng.eq6"]).filter { only == nil || $0.contains(only!) }\n    var rows'),
    ('case "cpu": cmdCPU(runs: 3, buffers: args.count > 2 ? Int(args[2])! : 2000)',
     'case "cpu": cmdCPU(runs: 3, buffers: args.count > 2 ? Int(args[2])! : 2000, only: args.count > 3 ? args[3] : nil)'),
]
for a, b in rep:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
