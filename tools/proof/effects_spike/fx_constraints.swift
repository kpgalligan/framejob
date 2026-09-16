// fx_constraints.swift — q7: what breaks, what must be set, which formats the
// offline engine accepts, and the defaults that make an effect silently do
// nothing. Every test runs in its OWN child process (the program re-executes
// itself with `--test <name>`), because AVAudioEngine reports several misuses
// by raising an Objective-C exception, which Swift cannot catch — a crash in
// one test must be a scored line, not the end of the run.
//
// Build: xcrun swiftc -O -parse-as-library -target arm64-apple-macos15.0 \
//          fx_common.swift fx_constraints.swift -o ../work/effects_spike/fx_constraints
// Run:   ../work/effects_spike/fx_constraints            (all tests)
//        ../work/effects_spike/fx_constraints --test NAME (one, in-process)

import AVFoundation
import Foundation

let stereo48 = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

func say(_ s: String) { print(s); fflush(stdout) }

func sameAsDry(_ a: Audio, _ dry: Audio) -> String {
    if a.digest == dry.digest && a.frames == dry.frames { return "byte-identical to dry" }
    let d = compare(a, dry)
    return "differs from dry: max |d| \(fmtDB(db(d.maxAbs))) dBFS, \(d.differing) samples"
}

let tests: [(String, () throws -> Void)] = [
    ("dry-equals-input", {
        let url = fixture("speech48s.wav"); let input = try readAudio(url)
        let r = try render(.file(url), frames: input.frames) { [] }
        say("player(file) -> mainMixer -> output at 48k stereo: \(sameAsDry(r.audio, input)) (vs the file's own decoded samples)")
    }),
    ("mono-TimePitch", { try monoInto("TimePitch +700") { timePitch(700) } }),
    ("mono-Reverb", { try monoInto("Reverb mediumHall") { reverb(.mediumHall) } }),
    ("mono-Delay", { try monoInto("Delay 0.25") { delay() } }),
    ("mono-EQ", { try monoInto("EQ 3 bands") { eqThreeBand() } }),
    ("mono-Distortion", { try monoInto("Distortion radioTower") { distortion(.speechRadioTower) } }),
    ("mono-Reverb-player-upmix", {
        // The workaround if a unit refuses mono: connect the PLAYER at stereo and let it convert.
        let url = fixture("speech48m.wav"); let input = try readAudio(url)
        var o = RenderOptions(); o.connectFormat = stereo48
        let r = try render(.file(url), frames: input.frames + 48000, options: o) { [reverb(.mediumHall)] }
        let a = try render(.file(url), frames: input.frames + 48000, options: o) { [reverb(.mediumHall)] }
        say("mono file, player connected at 48k STEREO -> Reverb: renders, peak \(fmtDB(db(peak(r.audio)))) dBFS, L==R \(r.audio.channels[0] == r.audio.channels[1]), two runs identical \(r.audio.digest == a.audio.digest)")
        let dry = try render(.file(url), frames: input.frames, options: o) { [] }.audio
        say("   the player's own mono->stereo: L == mono input \(dry.channels[0] == input.channels[0]), R == L \(dry.channels[1] == dry.channels[0])")
    }),
    ("file-read-stress", {
        // Schedule-before-play under load: eight renders of the 60 s file at once, whole and windowed,
        // each compared with a plain AVAudioFile read. A race in the player's file reading would show here.
        let url = fixture("long60.wav"); let whole = try readAudio(url)
        var results = [String](repeating: "", count: 8)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            let line: String
            do {
                if i % 2 == 0 {
                    let r = try render(.file(url), frames: whole.frames) { [] }.audio
                    line = "whole: \(sameAsDry(r, whole))"
                } else {
                    let start = 48000 * (7 * i), count = 48000 * 5
                    let r = try render(.segment(url, start: AVAudioFramePosition(start), count: AVAudioFrameCount(count)), frames: count) { [] }.audio
                    line = "segment \(7 * i) s + 5 s: \(sameAsDry(r, whole.slice(start, count)))"
                }
            } catch { line = "THROWS \(error)" }
            lock.lock(); results[i] = line; lock.unlock()
        }
        for (i, l) in results.enumerated() { say("render \(i) \(l)") }
    }),
    ("file-at-22050", {
        let url = fixture("speech.aiff")
        let f = try AVAudioFile(forReading: url)
        let expect = Double(f.length) / f.processingFormat.sampleRate
        let a = try render(.file(url), frames: Int(expect * 48000) + 48000) { [timePitch(700)] }.audio
        let b = try render(.file(url), frames: Int(expect * 48000) + 48000) { [timePitch(700)] }.audio
        let end = Double(lastAbove(a, 1e-3)) / 48000
        say("22.05 kHz mono file, player->TimePitch at the FILE's format, mixer converts to 48k stereo: renders; content ends \(String(format: "%.3f", end)) s (file is \(String(format: "%.3f", expect)) s); two runs identical \(a.digest == b.digest)")
    }),
    ("connect-rate-mismatch", {
        // Player carrying a 22.05 kHz file connected to a unit at 48 kHz stereo.
        let url = fixture("speech.aiff")
        var o = RenderOptions(); o.connectFormat = stereo48
        let r = try render(.file(url), frames: 12 * 48000, options: o) { [timePitch(0)] }
        let proper = try render(.file(url), frames: 12 * 48000) { [timePitch(0)] }
        say("returned normally: statuses \(r.statuses), peak \(fmtDB(db(peak(r.audio)))) dBFS, content ends \(String(format: "%.3f", Double(lastAbove(r.audio, 1e-3)) / 48000)) s (file 10.389 s); vs connecting at the file's format: \(sameAsDry(r.audio, proper.audio))")
    }),
    ("render-format-int16", {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!
        let engine = AVAudioEngine()
        do { try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096); say("enableManualRenderingMode(int16 interleaved): accepted; manualRenderingFormat \(engine.manualRenderingFormat)") }
        catch { say("enableManualRenderingMode(int16 interleaved) THROWS: \(error)"); return }
        let p = AVAudioPlayerNode(); engine.attach(p)
        let f = try AVAudioFile(forReading: fixture("speech48s.wav"))
        engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
        p.scheduleFile(f, at: nil); try engine.start(); p.play()
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var maxAbs: Int16 = 0
        for _ in 0..<10 {
            do { let st = try engine.renderOffline(4096, to: buf)
                 if let d = buf.int16ChannelData { for i in 0..<Int(buf.frameLength) * 2 { maxAbs = max(maxAbs, d[0][i] == Int16.min ? Int16.max : abs(d[0][i])) } }
                 if st != .success { say("status \(st.rawValue)") } }
            catch { say("renderOffline into int16 THROWS: \(error)"); return }
        }
        say("10 int16 renders: max |sample| \(maxAbs) (\(fmtDB(db(Double(maxAbs) / 32768))) dBFS)")
    }),
    ("render-format-mono", {
        let url = fixture("speech48s.wav")
        var o = RenderOptions(); o.outFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let r = try render(.file(url), frames: 48000 * 3, options: o) { [reverb(.mediumHall)] }
        let input = try readAudio(url).slice(0, 48000 * 3)
        say("mono render format from a stereo file: channels \(r.audio.channels.count), peak \(fmtDB(db(peak(r.audio)))) dBFS vs input \(fmtDB(db(peak(input))))")
    }),
    ("render-format-44100", {
        let url = fixture("speech48s.wav"); let input = try readAudio(url)
        var o = RenderOptions(); o.outFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let n = Int(Double(input.frames) * 44100 / 48000) + 44100
        let a = try render(.file(url), frames: n, options: o) { [timePitch(700)] }.audio
        let b = try render(.file(url), frames: n, options: o) { [timePitch(700)] }.audio
        say("44.1 kHz render format from a 48 kHz file: rate \(a.rate), content ends \(String(format: "%.3f", Double(lastAbove(a, 1e-3)) / 44100)) s, runs identical \(a.digest == b.digest)")
    }),
    ("frames-over-max", {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
        let p = AVAudioPlayerNode(); engine.attach(p)
        let f = try AVAudioFile(forReading: fixture("speech48s.wav"))
        engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
        p.scheduleFile(f, at: nil); try engine.start(); p.play()
        let big = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 16384)!
        do { let s = try engine.renderOffline(8192, to: big); say("renderOffline(8192) with max 4096: status \(s.rawValue), frameLength \(big.frameLength)") }
        catch { say("renderOffline(8192) with max 4096 THROWS: \(error)") }
    }),
    ("buffer-format-mismatch", {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
        let p = AVAudioPlayerNode(); engine.attach(p)
        let f = try AVAudioFile(forReading: fixture("speech48s.wav"))
        engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
        p.scheduleFile(f, at: nil); try engine.start(); p.play()
        let wrong = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!, frameCapacity: 4096)!
        do { let s = try engine.renderOffline(4096, to: wrong); say("render into a 44.1k buffer: status \(s.rawValue), frameLength \(wrong.frameLength)") }
        catch { say("render into a 44.1k buffer THROWS: \(error)") }
    }),
    ("enable-while-running", {
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
        let p = AVAudioPlayerNode(); engine.attach(p)
        engine.connect(p, to: engine.mainMixerNode, format: stereo48)
        try engine.start()
        do { try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 1024); say("second enableManualRenderingMode while running: accepted, max now \(engine.manualRenderingMaximumFrameCount)") }
        catch { say("second enableManualRenderingMode while running THROWS: \(error)") }
    }),
    ("play-before-start", {
        func once() throws -> (Int, String) {
            let engine = AVAudioEngine()
            try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
            let p = AVAudioPlayerNode(); engine.attach(p)
            let f = try AVAudioFile(forReading: fixture("speech48s.wav"))
            engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
            p.scheduleFile(f, at: nil)
            p.play()
            try engine.start()
            var out = [Float]()
            let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            for _ in 0..<20 { _ = try engine.renderOffline(4096, to: buf); out += UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)) }
            return (out.firstIndex { $0 != 0 } ?? -1, Audio(channels: [out], rate: 48000).digest)
        }
        let a = try once(), b = try once()
        let input = try readAudio(fixture("speech48s.wav"))
        say("player.play() before engine.start(): no exception; first non-zero output frame \(a.0) (input's \(input.channels[0].firstIndex { $0 != 0 } ?? -1)); second run first non-zero \(b.0), identical \(a.1 == b.1)")
    }),
    ("never-play", {
        let url = fixture("speech48s.wav")
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
        let p = AVAudioPlayerNode(); engine.attach(p)
        let f = try AVAudioFile(forReading: url)
        engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
        p.scheduleFile(f, at: nil); try engine.start()
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var peakSeen: Float = 0
        for _ in 0..<50 { let s = try engine.renderOffline(4096, to: buf); precondition(s == .success); peakSeen = max(peakSeen, vDSP_max(buf, Int(buf.frameLength))) }
        say("scheduled but never play(): 50 renders succeed, peak \(fmtDB(db(Double(peakSeen)))) dBFS (silence)")
    }),
    ("schedule-after-play", {
        let url = fixture("speech48s.wav"); let input = try readAudio(url)
        func once(chunk: Int) throws -> Audio {
            let engine = AVAudioEngine()
            try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
            let p = AVAudioPlayerNode(); engine.attach(p)
            let f = try AVAudioFile(forReading: url)
            engine.connect(p, to: engine.mainMixerNode, format: f.processingFormat)
            try engine.start(); p.play()
            p.scheduleFile(f, at: nil)
            var out = [[Float]](repeating: [], count: 2)
            let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            while out[0].count < input.frames + 48000 { _ = try engine.renderOffline(AVAudioFrameCount(chunk), to: buf); for c in 0..<2 { out[c] += UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength)) } }
            return Audio(channels: out, rate: 48000)
        }
        let inLead = input.channels[0].firstIndex { $0 != 0 } ?? -1
        for chunk in [4096, 4096, 1024, 512] {
            let a = try once(chunk: chunk)
            say("chunk \(chunk): play() then scheduleFile(at: nil): first non-zero frame \(a.channels[0].firstIndex { $0 != 0 } ?? -1) (input's \(inLead)); digest \(a.digest)")
        }
    }),
    ("defaults", {
        let r = AVAudioUnitReverb(), d = AVAudioUnitDelay(), x = AVAudioUnitDistortion(), t = AVAudioUnitTimePitch(), e = AVAudioUnitEQ(numberOfBands: 1)
        say("AVAudioUnitReverb().wetDryMix \(r.wetDryMix) (header: no default stated)")
        say("AVAudioUnitDelay(): wetDryMix \(d.wetDryMix) (header says 100), delayTime \(d.delayTime), feedback \(d.feedback), lowPassCutoff \(d.lowPassCutoff)")
        say("AVAudioUnitDistortion(): wetDryMix \(x.wetDryMix) (header 50), preGain \(x.preGain) (header -6)")
        say("AVAudioUnitTimePitch(): pitch \(t.pitch) rate \(t.rate) overlap \(t.overlap)")
        let b = e.bands[0]
        say("AVAudioUnitEQ band 0: bypass \(b.bypass) filterType \(b.filterType.rawValue) frequency \(b.frequency) gain \(b.gain) bandwidth \(b.bandwidth); globalGain \(e.globalGain)")
        t.pitch = 5000; t.overlap = 100; d.delayTime = 9; x.wetDryMix = 500
        say("out-of-range writes read back: pitch=5000 -> \(t.pitch), overlap=100 -> \(t.overlap), delayTime=9 -> \(d.delayTime), distortion wet=500 -> \(x.wetDryMix)")
    }),
    ("silent-no-ops", {
        let url = fixture("speech48s.wav"); let input = try readAudio(url)
        let n = input.frames + 48000
        let dry = try render(.file(url), frames: n) { [] }.audio
        let eqUntouched: () -> [AVAudioNode] = { let u = AVAudioUnitEQ(numberOfBands: 1); u.bands[0].filterType = .lowShelf; u.bands[0].frequency = 200; u.bands[0].gain = 12; return [u] }
        say(pad("EQ +12 dB shelf, bypass left default", 44) + sameAsDry(try render(.file(url), frames: n, makeUnits: eqUntouched).audio, dry))
        let bypassed: [(String, () -> AVAudioUnit)] = [("TimePitch +700", { timePitch(700) }), ("Reverb cathedral", { reverb(.cathedral, wet: 100) }),
                                                        ("Delay", { delay() }), ("EQ 3 bands", { eqThreeBand() }), ("Distortion radioTower", { distortion(.speechRadioTower) })]
        for (name, make) in bypassed {
            let u = make(); (u as? AVAudioUnitEffect)?.bypass = true
            if let tp = u as? AVAudioUnitTimeEffect { tp.bypass = true }
            say(pad("\(name) with .bypass = true", 44) + sameAsDry(try render(.file(url), frames: n) { [u] }.audio, dry))
        }
        say(pad("TimePitch pitch 0 rate 1 (not bypassed)", 44) + sameAsDry(try render(.file(url), frames: n) { [timePitch(0)] }.audio, dry))
        say(pad("Reverb wetDryMix 0", 44) + sameAsDry(try render(.file(url), frames: n) { [reverb(.cathedral, wet: 0)] }.audio, dry))
        say(pad("Distortion wetDryMix 0", 44) + sameAsDry(try render(.file(url), frames: n) { [distortion(.speechRadioTower, wet: 0)] }.audio, dry))
        say(pad("Delay wetDryMix 0", 44) + sameAsDry(try render(.file(url), frames: n) { [delay(wet: 0)] }.audio, dry))
        say(pad("EQ bands un-bypassed at gain 0 (parametric)", 44) + sameAsDry(try render(.file(url), frames: n) { let u = AVAudioUnitEQ(numberOfBands: 2); u.bands.forEach { $0.bypass = false; $0.gain = 0 }; return [u] }.audio, dry))
    }),
    ("enable-after-connect", {
        let url = fixture("speech48s.wav"); let n = try readAudio(url).frames
        var o = RenderOptions(); o.enableFirst = false
        let late = try render(.file(url), frames: n, options: o) { [timePitch(700), reverb(.mediumHall)] }.audio
        let early = try render(.file(url), frames: n) { [timePitch(700), reverb(.mediumHall)] }.audio
        say("manual mode enabled AFTER attach/connect (mainMixerNode touched first): renders; identical to enable-first \(late.digest == early.digest)")
    }),
    ("engine-reuse", {
        let url = fixture("speech48s.wav"); let n = try readAudio(url).frames
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: stereo48, maximumFrameCount: 4096)
        let p = AVAudioPlayerNode(), u = reverb(.mediumHall), t = timePitch(700)
        [p, t, u].forEach { engine.attach($0) }
        let f = try AVAudioFile(forReading: url)
        engine.connect(p, to: t, format: f.processingFormat); engine.connect(t, to: u, format: f.processingFormat); engine.connect(u, to: engine.mainMixerNode, format: f.processingFormat)
        func pass() throws -> Audio {
            p.scheduleFile(f, at: nil); try engine.start(); p.play()
            var out = [[Float]](repeating: [], count: 2)
            let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
            while out[0].count < n { _ = try engine.renderOffline(AVAudioFrameCount(min(4096, n - out[0].count)), to: buf); for c in 0..<2 { out[c] += UnsafeBufferPointer(start: buf.floatChannelData![c], count: Int(buf.frameLength)) } }
            p.stop(); engine.stop()
            return Audio(channels: out, rate: 48000)
        }
        let a = try pass()
        engine.reset()
        let b = try pass()
        let fresh = try render(.file(url), frames: n) { [timePitch(700), reverb(.mediumHall)] }.audio
        say("one engine, stop + reset + reschedule: second pass identical to first \(a.digest == b.digest); first identical to a fresh engine \(a.digest == fresh.digest)")
        if a.digest != b.digest { let d = compare(a, b); say("   max |d| \(fmtDB(db(d.maxAbs))) dBFS, \(d.differing) samples") }
        let c = try pass()   // no reset this time
        say("third pass without reset identical to first \(a.digest == c.digest)" + (a.digest == c.digest ? "" : " (max |d| \(fmtDB(db(compare(a, c).maxAbs))) dBFS)"))
    }),
    ("background-thread", {
        let url = fixture("speech48s.wav"); let n = try readAudio(url).frames
        let main = try render(.file(url), frames: n) { [timePitch(700), reverb(.mediumHall)] }.audio
        var bg: Audio?; var err: Error?
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            do { bg = try render(.file(url), frames: n) { [timePitch(700), reverb(.mediumHall)] }.audio } catch { err = error }
            sem.signal()
        }
        sem.wait()
        say("render on a global queue with the main thread parked on a DispatchSemaphore: \(err.map { "THROWS \($0)" } ?? "ok, identical to main-thread render \(bg!.digest == main.digest)")")
    }),
    ("time-pitch-rate", {
        let url = fixture("speech48s.wav"); let input = try readAudio(url)
        for rate: Float in [0.5, 2] {
            let r = try render(.file(url), frames: Int(Double(input.frames) / Double(rate)) + 48000) { [timePitch(0, rate: rate)] }
            say("TimePitch rate \(rate): content ends \(String(format: "%.3f", Double(lastAbove(r.audio, 1e-3)) / 48000)) s (input content ends \(String(format: "%.3f", Double(lastAbove(input, 1e-3)) / 48000)) s); statuses \(r.statuses)")
        }
    }),
    ("movie-and-aac-files", {
        for path in ["../media/speech.mov", "../media/AV.mov", "../media/toneA.m4a"] {
            let url = URL(fileURLWithPath: path)
            do {
                let f = try AVAudioFile(forReading: url)
                let whole = try readAudio(url)
                let start = AVAudioFramePosition(48000), count = AVAudioFrameCount(96000)
                let seg = try render(.segment(url, start: start, count: count), frames: Int(count)) { [] }.audio
                let slice = whole.slice(Int(start), Int(count))
                let seg2 = try render(.segment(url, start: start, count: count), frames: Int(count)) { [] }.audio
                var o = RenderOptions(); o.chunk = 1000
                let seg3 = try render(.segment(url, start: start, count: count), frames: Int(count), options: o) { [] }.audio
                let whole2 = try render(.file(url), frames: Int(f.length)) { [] }.audio.slice(Int(start), Int(count))
                say(pad(path, 22) + "segment twice identical \(seg.digest == seg2.digest); segment at chunk 1000 identical \(seg.digest == seg3.digest); whole-file render sliced vs full read: \(sameAsDry(whole2, slice))")
                say(pad(path, 22) + "AVAudioFile opens: \(f.fileFormat.settings[AVFormatIDKey] ?? "?") \(f.processingFormat.sampleRate) Hz \(f.processingFormat.channelCount) ch, length \(f.length); scheduleSegment(1 s, 2 s) through the engine vs slice of a full read: \(sameAsDry(seg, slice))")
            } catch { say(pad(path, 22) + "AVAudioFile THROWS: \(error)") }
        }
    }),
]

func monoInto(_ name: String, _ make: @escaping () -> AVAudioNode) throws {
    let url = fixture("speech48m.wav"); let input = try readAudio(url)
    var fmtNote = ""
    let r = try render(.file(url), frames: input.frames + 48000, afterStart: { e in
        let u = e.attachedNodes.first { $0 is AVAudioUnit }!
        fmtNote = "unit in \(u.inputFormat(forBus: 0).channelCount) ch / out \(u.outputFormat(forBus: 0).channelCount) ch"
    }) { [make()] }
    say(pad(name, 24) + "mono connection OK; \(fmtNote); output 2 ch, L==R \(r.audio.channels[0] == r.audio.channels[1]), peak \(fmtDB(db(peak(r.audio)))) dBFS")
}

func vDSP_max(_ buf: AVAudioPCMBuffer, _ n: Int) -> Float {
    var m: Float = 0
    for c in 0..<Int(buf.format.channelCount) { if let p = buf.floatChannelData?[c] { for i in 0..<n { m = max(m, abs(p[i])) } } }
    return m
}

@main
struct Constraints {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "--test", let t = tests.first(where: { $0.0 == args[2] }) {
            try t.1()
            return
        }
        print(hostLine())
        for (name, _) in tests {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            proc.arguments = ["--test", name]
            let pipe = Pipe()
            proc.standardOutput = pipe; proc.standardError = pipe
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let how = proc.terminationReason == .uncaughtSignal ? "CRASHED (signal \(proc.terminationStatus))" : "exit \(proc.terminationStatus)"
            print("\n== \(name): \(how)")
            let text = String(decoding: data, as: UTF8.self)
            // Keep the child's lines, trimming Apple's long exception backtraces to their first lines.
            var kept: [String] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.contains("*** First throw call stack") { kept.append("   [call stack elided]"); break }
                kept.append("   " + line)
            }
            print(kept.joined(separator: "\n"))
        }
    }
}
