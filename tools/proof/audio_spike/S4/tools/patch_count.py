import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
p = 'Core.swift'
s = open(p).read()
s = s.replace('''           alignEnd: Bool = false, speed: Double = 1) -> WindowAnswer {''',
              '''           alignEnd: Bool = false, speed: Double = 1, exactCount: Bool = false) -> WindowAnswer {''')
old = '''    var starts: [Int] = []
    if alignEnd {
        var j = e - per
        while j >= s { starts.append(j); j -= hop }
    } else {
        var j = s
        while j + per <= e { starts.append(j); j += hop }
    }'''
new = '''    var starts: [Int] = []
    if exactCount {
        // As many gating blocks as the EXACT window holds (an export of it
        // keeps a block only if it ends inside the window), laid from the
        // snapped played start: only the grid's offset is approximated.
        let length = Double(fb - fa) / cache.rate / speed
        let n = length >= 0.4 ? Int(((length - 0.4) / 0.1 + 1e-9).rounded(.down)) + 1 : 0
        for k in 0..<n {
            let j = alignEnd ? e - per - k * hop : s + k * hop
            if j >= 0 && j + per <= cache.blockCount { starts.append(j) }
        }
    } else if alignEnd {
        var j = e - per
        while j >= s { starts.append(j); j -= hop }
    } else {
        var j = s
        while j + per <= e { starts.append(j); j += hop }
    }'''
assert old in s
s = s.replace(old, new)
open(p, 'w').write(s)

p = 'main.swift'
s = open(p).read()
old = '''        let q100 = query(c100, fa: fa, fb: fb).lufs ?? .nan
        let q25 = query(c25, fa: fa, fb: fb).lufs ?? .nan
        let q10 = query(c10, fa: fa, fb: fb).lufs ?? .nan
        let q10d = query(c10, fa: fa, fb: fb, dense: true).lufs ?? .nan'''
new = '''        let ex = CommandLine.arguments.contains("--exact-count")
        let q100 = query(c100, fa: fa, fb: fb, exactCount: ex).lufs ?? .nan
        let q25 = query(c25, fa: fa, fb: fb, exactCount: ex).lufs ?? .nan
        let q10 = query(c10, fa: fa, fb: fb, exactCount: ex).lufs ?? .nan
        let q10d = query(c10, fa: fa, fb: fb, dense: true).lufs ?? .nan'''
assert old in s
s = s.replace(old, new)
# windows command: add exact-count columns via flag
old = '''        let n = query(cache, fa: fa, fb: fb, snap: .nearest)
        let o = query(cache, fa: fa, fb: fb, snap: .outward)
        let i = query(cache, fa: fa, fb: fb, snap: .inward)'''
new = '''        let ex = CommandLine.arguments.contains("--exact-count")
        let n = query(cache, fa: fa, fb: fb, snap: .nearest, exactCount: ex)
        let o = query(cache, fa: fa, fb: fb, snap: .outward, exactCount: ex)
        let i = query(cache, fa: fa, fb: fb, snap: .inward, exactCount: ex)'''
assert old in s
s = s.replace(old, new)
old = '''        let m = query(cache, fa: N - fb, fb: N - fa, snap: .nearest, alignEnd: true)'''
new = '''        let m = query(cache, fa: N - fb, fb: N - fa, snap: .nearest, alignEnd: true,
                      exactCount: CommandLine.arguments.contains("--exact-count"))'''
assert old in s
s = s.replace(old, new)
open(p, 'w').write(s)
print("patched")
