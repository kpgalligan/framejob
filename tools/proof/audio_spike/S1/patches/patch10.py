import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
a = '        notes.forEach { print("   " + $0) }\n'
b = '''        notes.forEach { print("   " + $0) }
        writeF32(Array(UnsafeBufferPointer(start: ctx.capture!, count: ctx.captured)), OUT + "/preview_\\(key).f32")
        writeF32(exp.samples, OUT + "/preview_export_\\(key).f32")
        let table = (0..<n).map { "\\(ctx.starts[$0])\\t\\(ctx.sizes[$0])" }.joined(separator: "\\n")
        try? table.write(toFile: OUT + "/preview_\\(key)_callbacks.tsv", atomically: true, encoding: .utf8)
'''
assert a in s
s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
