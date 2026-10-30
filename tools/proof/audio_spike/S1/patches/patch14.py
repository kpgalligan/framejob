import sys

d = sys.argv[1]
p = d + '/src/Tap.swift'
s = open(p).read()
rep = [
    ("    var skipInvalid = false\n",
     "    var skipInvalid = false\n"
     "    /// Reset the stage when a callback carries StartOfStream, as AudioTap does.\n"
     "    var resetOnStart = false\n"
     "    var pendingReset = false\n"),
    ("                    ctx.sosAt[ctx.sosCount] = ctx.callbacks\n",
     "                    ctx.sosAt[ctx.sosCount] = ctx.callbacks\n"
     "                    ctx.pendingReset = ctx.resetOnStart\n"),
    ("        if let stage, prepared, frames > 0, !(skipInvalid && start < 0) {\n",
     "        if pendingReset, let stage { stage.reset(); pendingReset = false }\n"
     "        if let stage, prepared, frames > 0, !(skipInvalid && start < 0) {\n"),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ("func cmdPreview(keys: [String], file: String, seconds: Double, skipInvalid: Bool = false) {",
     "func cmdPreview(keys: [String], file: String, seconds: Double, skipInvalid: Bool = false, resetOnStart: Bool = false) {"),
    ("        ctx.skipInvalid = skipInvalid\n",
     "        ctx.skipInvalid = skipInvalid\n        ctx.resetOnStart = resetOnStart\n"),
    ('case "preview-skip":',
     'case "preview-reset": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6, resetOnStart: true)\ncase "preview-skip":'),
]
for a, b in rep:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
