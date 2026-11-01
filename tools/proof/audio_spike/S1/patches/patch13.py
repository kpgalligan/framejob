import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
a = 'let args = CommandLine.arguments'
b = '''/// Is a stage's reset() (AudioUnitReset for the Apple hosts) real-time safe?
/// AudioTap calls reset on the render thread at StartOfStream and on a seek.
func cmdResetRT() {
    let b = UnsafeMutablePointer<Int>.allocate(capacity: 5), a = UnsafeMutablePointer<Int>.allocate(capacity: 5)
    for key in ["own.eq6", "own.expander", "own.compressor", "own.limiter64aT", "own.chain8T", "au.eq6", "au.dyn", "au.limiter", "au.chain3", "v3b.limiter", "eng.chain3"] {
        guard let s = subject(key) else { continue }
        _ = s.prepare(channels: 2, sampleRate: 48000, maxFrames: 4096)
        let buf = PlanarBuffers(channels: 2, capacity: 4096)
        buf.setFrames(512)
        for c in 0..<2 { for i in 0..<512 { buf.data[c][i] = Float.random(in: -0.5...0.5) } }
        _ = s.process(buf.abl, frames: 512)
        var first = RTCounts(), later = RTCounts()
        for round in 0..<5 {
            RTCheck.read(b); RTCheck.arm(); s.reset(); RTCheck.disarm(); RTCheck.read(a)
            if round == 0 { first.add(before: b, after: a) } else { later.add(before: b, after: a) }
            buf.setFrames(512)
            _ = s.process(buf.abl, frames: 512)
        }
        print(String(format: "%-16@ reset first: %@ | next 4: %@", key as NSString, first.description, later.description))
    }
}

let args = CommandLine.arguments'''
assert a in s
s = s.replace(a, b, 1)
a = 'case "control": cmdControl()'
b = 'case "control": cmdControl()\ncase "resetrt": cmdResetRT()'
s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
