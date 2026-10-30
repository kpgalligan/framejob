import sys

d = sys.argv[1]
p = d + '/src/Tap.swift'
s = open(p).read()
rep = [
    ("    let armSource: Bool\n", "    let armSource: Bool\n    /// Pass a callback with no valid time through untouched (no stage runs).\n    var skipInvalid = false\n"),
    ("        if let stage, prepared, frames > 0 {", "        if let stage, prepared, frames > 0, !(skipInvalid && start < 0) {"),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ("func cmdPreview(keys: [String], file: String, seconds: Double) {",
     "func cmdPreview(keys: [String], file: String, seconds: Double, skipInvalid: Bool = false) {"),
    ("        let ctx = TapCtx(stage: stage)\n        let cap = Int((seconds + 2) * 48000) * src.channels",
     "        let ctx = TapCtx(stage: stage)\n        ctx.skipInvalid = skipInvalid\n        let cap = Int((seconds + 2) * 48000) * src.channels"),
    ('case "preview": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6)',
     'case "preview": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6)\n'
     'case "preview-skip": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6, skipInvalid: true)'),
]
for a, b in rep:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
