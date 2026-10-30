import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
p = 'main.swift'
s = open(p).read()
cmd = '''case "qtime":  // qtime <in.f32> <rate> <ch>: how long a whole-file query takes, and a direct pass
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let coeffs = KWeight.coefficients(rate: pcm.rate)
    for bps in [10, 100] {
        let (cache, _) = buildCache(pcm, blocksPerSecond: bps, coefficients: coeffs, floatPeak: true)
        var best = Double.infinity
        var answer: WindowAnswer! = nil
        for _ in 0..<5 {
            let t0 = secondsNow()
            answer = query(cache, fa: 0, fb: pcm.frames)
            best = min(best, secondsNow() - t0)
        }
        print(String(format: "query of the whole %.0f s from the %d ms cache: %.2f ms (I %@)", Double(pcm.frames) / pcm.rate, 1000 / bps, best * 1000, fmt(answer.lufs, 3)))
    }
    let t0 = secondsNow()
    let d = direct(pcm, fa: 0, fb: pcm.frames, coefficients: coeffs)
    print(String(format: "direct pass over memory (no decode): %.3f s (I %@)", secondsNow() - t0, fmt(d.lufs, 3)))

'''
s = s.replace('case "mirror":', cmd + 'case "mirror":', 1)
open(p, 'w').write(s)
print("patched")
