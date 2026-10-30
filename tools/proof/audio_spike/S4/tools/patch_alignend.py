import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
p = 'Core.swift'
s = open(p).read()
s = s.replace('matrix: Matrix? = nil, dualMono: Bool = false, dense: Bool = false) -> WindowAnswer {',
              'matrix: Matrix? = nil, dualMono: Bool = false, dense: Bool = false,\n           alignEnd: Bool = false) -> WindowAnswer {')
old = '''    var blocks: [Double] = []
    var j = s
    while j + per <= e {'''
new = '''    var blocks: [Double] = []
    // Gating blocks start at the PLAYED start: the window's first block, or
    // for a reversed clip (alignEnd) its last, stepping backwards.
    var starts: [Int] = []
    if alignEnd {
        var j = e - per
        while j >= s { starts.append(j); j -= hop }
    } else {
        var j = s
        while j + per <= e { starts.append(j); j += hop }
    }
    for j in starts {'''
assert old in s
s = s.replace(old, new)
old2 = '''        blocks.append(z)
        j += hop
    }'''
assert old2 in s
s = s.replace(old2, '''        blocks.append(z)
    }''')
open(p, 'w').write(s)
p = 'main.swift'
s = open(p).read()
s = s.replace('let m = query(cache, fa: N - fb, fb: N - fa, snap: .nearest)',
              'let m = query(cache, fa: N - fb, fb: N - fa, snap: .nearest, alignEnd: true)')
open(p, 'w').write(s)
print("patched")
