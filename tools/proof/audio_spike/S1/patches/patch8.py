import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
a = 'let args = CommandLine.arguments'
b = '''/// The preview's path: the same composition and tap under a MUTED AVPlayer,
/// the tap's output captured, compared with the export path's output.
func cmdPreview(keys: [String], file: String, seconds: Double) {
    let src = Source(file)
    for key in keys {
        let stage: Stage? = key == "dry" ? nil : subject(key)
        let (comp, track) = src.composition()
        let ctx = TapCtx(stage: stage)
        let cap = Int((seconds + 2) * 48000) * src.channels
        ctx.capture = .allocate(capacity: cap)
        ctx.captureCap = cap
        let p = AVMutableAudioMixInputParameters(track: track)
        p.audioTapProcessor = TapFactory.make(ctx)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [p]
        let item = AVPlayerItem(asset: comp)
        item.audioMix = mix
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.play()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        player.pause()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let n = min(ctx.callbacks, 100_000)
        var firstNumeric = -1, before = 0
        for i in 0..<n where ctx.starts[i] >= 0 { firstNumeric = i; break }
        if firstNumeric > 0 { for i in 0..<firstNumeric { before += Int(ctx.sizes[i]) } }
        let start0 = firstNumeric >= 0 ? Int(ctx.starts[firstNumeric]) - before : 0
        var contiguous = true
        var expect = Int64(start0)
        for i in 0..<n {
            if ctx.starts[i] >= 0, ctx.starts[i] != expect { contiguous = false }
            expect += Int64(ctx.sizes[i])
        }
        print("\\n[\\(key)] preview: \\(ctx.sizeSummary), invalid times \\(ctx.invalidTimes), first callback starts at sample \\(start0), contiguous \\(contiguous), threads \\(ctx.processThreads), first \\(ctx.first), steady \\(ctx.steady), prep \\(ctx.prepareError ?? "ok")")
        let exp = readThroughTap(src, stage: key == "dry" ? nil : subject(key))
        let got = ctx.captured
        let ch = src.channels
        guard start0 >= 0, start0 * ch + got <= exp.samples.count else { print("   cannot align"); continue }
        var diffs = 0
        var maxd: Float = 0
        var firstDiff = -1
        for i in 0..<got {
            let d = abs(ctx.capture![i] - exp.samples[start0 * ch + i])
            if d != 0 { diffs += 1; if firstDiff < 0 { firstDiff = i / ch } }
            maxd = max(maxd, d)
        }
        print(String(format: "   compared %d samples with the export path: %d differ, max |Δ| %.3g (%.1f dBFS), first at frame %d", got, diffs, maxd, 20 * log10(Double(max(maxd, 1e-30))), firstDiff))
    }
}

let args = CommandLine.arguments'''
assert a in s
s = s.replace(a, b, 1)
a = 'case "control": cmdControl()'
b = '''case "control": cmdControl()
case "preview": cmdPreview(keys: Array(args.dropFirst(3)), file: args[2] == "rode" ? RODE : SIG + "/" + args[2], seconds: 6)'''
assert a in s
s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
