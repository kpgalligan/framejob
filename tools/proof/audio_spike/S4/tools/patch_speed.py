import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
p = 'Core.swift'
s = open(p).read()
s = s.replace('''           alignEnd: Bool = false) -> WindowAnswer {''',
              '''           alignEnd: Bool = false, speed: Double = 1) -> WindowAnswer {''')
old = '''    let hop = dense ? 1 : bps / 10  // sub-blocks per hop (100 ms, or one sub-block when dense)
    let per = (bps / 10) * 4      // sub-blocks per 400 ms gating block'''
new = '''    // At a speed, a played 400 ms block reads 400*speed ms of source (time-scaled gating).
    let hop = dense ? 1 : max(1, Int((Double(bps / 10) * speed).rounded()))
    let per = max(1, Int((Double(bps / 10) * 4 * speed).rounded()))'''
assert old in s
s = s.replace(old, new)
open(p, 'w').write(s)

p = 'main.swift'
s = open(p).read()
cmd = '''case "speed":  // speed <in.f32> <rate> <ch> <windowsfile>: time-scaled gating at 10 ms grain
    let pcm = readRaw(arg(2), rate: Double(arg(3))!, channels: Int(arg(4))!)
    let (cache, _) = buildCache(pcm, blocksPerSecond: 100, coefficients: KWeight.coefficients(rate: pcm.rate))
    for (a, b) in readWindows(arg(5)) {
        let fa = Int((a * pcm.rate).rounded()), fb = min(pcm.frames, Int((b * pcm.rate).rounded()))
        var line = String(format: "%.3f %.3f", a, b)
        for sp in [1.0, 0.5, 0.8, 1.25, 2.0] {
            line += String(format: " x%.2f %@", sp, fmt(query(cache, fa: fa, fb: fb, speed: sp).lufs, 3))
        }
        print(line)
    }

'''
s = s.replace('case "mirror":', cmd + 'case "mirror":', 1)
open(p, 'w').write(s)
print("patched")
