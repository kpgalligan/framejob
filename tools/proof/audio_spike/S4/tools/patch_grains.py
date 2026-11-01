import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
p = 'main.swift'
s = open(p).read()
cmd = '''case "grains":  // grains <in.f32> <rate> <ch> <count> <minS> <maxS> <seed>: |cache - direct| per grain, exact count
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let count = Int(arg(5))!, minS = Double(arg(6))!, maxS = Double(arg(7))!
    var rng = UInt64(arg(8))!
    func rnd() -> Double { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Double(rng >> 11) / Double(1 << 53) }
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    let grains = [10, 20, 40, 100, 200, 1000]
    let caches = grains.map { buildCache(pcm, blocksPerSecond: $0, coefficients: coeffs, floatPeak: true).0 }
    let T = Double(pcm.frames) / pcm.rate
    var errs = Array(repeating: [Double](), count: grains.count)
    var tpUnder = 0
    for _ in 0..<count {
        let d = minS + (maxS - minS) * rnd()
        let a = (T - d) * rnd()
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int(((a + d) * pcm.rate).rounded()))
        let dir = direct(pcm, fa: fa, fb: fb, coefficients: coeffs)
        for (i, c) in caches.enumerated() {
            let q = query(c, fa: fa, fb: fb, exactCount: true)
            errs[i].append(abs((q.lufs ?? .nan) - (dir.lufs ?? .nan)))
            if i == 0 && q.truePeakDB < dir.truePeakDB - 1e-9 { tpUnder += 1 }
        }
    }
    print("| grain | median | p95 | max | share > 0.1 LU |")
    print("|---|---|---|---|---|")
    for (i, g) in grains.enumerated() {
        let e = errs[i].sorted()
        let med = e[e.count / 2], p95 = e[Int(Double(e.count - 1) * 0.95)], mx = e.last!
        let share = Double(e.filter { $0 > 0.1 }.count) / Double(e.count) * 100
        print(String(format: "| %g ms | %.3f | %.3f | %.3f | %.1f %% |", 1000.0 / Double(g), med, p95, mx, share))
    }
    print("windows where the 100 ms cache's true peak read under DIRECT's: \\(tpUnder) of \\(count)")

'''
s = s.replace('case "mirror":', cmd + 'case "mirror":', 1)
open(p, 'w').write(s)
print("patched")
