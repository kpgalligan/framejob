import sys

d = sys.argv[1]
p = d + '/src/Tap.swift'
s = open(p).read()
rep = [
    ("    var skipInvalid = false\n",
     "    var skipInvalid = false\n"
     "    /// Callback indices whose flags carried StartOfStream / EndOfStream (first 16).\n"
     "    var sosAt: [Int] = Array(repeating: -1, count: 16)\n"
     "    var sosCount = 0\n"),
    ("                guard st == noErr else { numberFramesOut.pointee = 0; return }\n",
     "                guard st == noErr else { numberFramesOut.pointee = 0; return }\n"
     "                if flagsOut.pointee & MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_StartOfStream) != 0, ctx.sosCount < 16 {\n"
     "                    ctx.sosAt[ctx.sosCount] = ctx.callbacks\n"
     "                    ctx.sosCount += 1\n"
     "                }\n"),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/src/main.swift'
s = open(p).read()
a = '        notes.forEach { print("   " + $0) }\n'
b = '        notes.forEach { print("   " + $0) }\n        print("   StartOfStream flag on callbacks \\(Array(ctx.sosAt.prefix(ctx.sosCount))) (callback 0 is the no-valid-time pre-roll)")\n'
assert a in s
s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
