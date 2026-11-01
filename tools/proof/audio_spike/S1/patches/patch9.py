import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
a_start = s.index('        let exp = readThroughTap(src, stage: key == "dry" ? nil : subject(key))')
a_end = s.index('let args = CommandLine.arguments')
new = '''        let exp = readThroughTap(src, stage: key == "dry" ? nil : subject(key))
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
                notes.append("callback \\(i) (no valid time, \\(frames) frames): \\(silent ? "silent" : match >= 0 ? "equals export frames \\(match)…" : "matches no export position (processed audio from a state the export never had)")")
                continue
            }
            let s0 = Int(ctx.starts[i])
            guard (s0 + frames) * ch <= exp.samples.count else { continue }
            for k in 0..<frames * ch {
                let dd = abs(ctx.capture![off + k] - exp.samples[s0 * ch + k])
                if dd != 0 { diffs += 1; if firstDiff < 0 { firstDiff = s0 + k / ch } }
                maxd = max(maxd, dd)
            }
            compared += frames * ch
        }
        notes.forEach { print("   " + $0) }
        print(String(format: "   compared %d samples (valid-time callbacks) with the export path: %d differ, max |Δ| %.3g (%.1f dBFS), first at frame %d", compared, diffs, maxd, 20 * log10(Double(max(maxd, 1e-30))), firstDiff))
    }
}

'''
s = s[:a_start] + new + s[a_end:]
# remove the old guard/compare block remnants (they were between exp and the end; replaced above)
open(p, 'w').write(s)
print("patched")
