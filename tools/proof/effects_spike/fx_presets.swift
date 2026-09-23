// fx_presets.swift — q2: which presets exist, what each does to speech, and
// which ones map onto the effects list (rooms, hall, plate, cathedral;
// telephone; radio; bit-crush; robot). Also WHEN a factory preset must be
// loaded for it to take effect, which fx_determinism's identical reverb
// digests put in question.
//
// Build: xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 \
//          fx_common.swift fx_presets.swift -o ../work/effects_spike/fx_presets

import AVFoundation
import Foundation

func params(_ node: AVAudioNode, only: [String]? = nil) -> String {
    guard let au = (node as? AVAudioUnit)?.auAudioUnit, let all = au.parameterTree?.allParameters else { return "(no tree)" }
    return all.filter { only == nil || only!.contains($0.identifier) || only!.contains($0.displayName) }
        .map { "\($0.displayName)=\(String(format: "%g", $0.value))" }.joined(separator: " ")
}

func paramTree(_ node: AVAudioNode) -> String {
    guard let au = (node as? AVAudioUnit)?.auAudioUnit, let all = au.parameterTree?.allParameters else { return "  (no tree)" }
    return all.map { "  addr \($0.address) \(pad("\"\($0.displayName)\"", 26)) \(pad("[\(String(format: "%g", $0.minValue)) … \(String(format: "%g", $0.maxValue))]", 22)) value \(String(format: "%g", $0.value)) \($0.unitName ?? "")" }
        .joined(separator: "\n")
}

func setParam(_ node: AVAudioNode, _ name: String, _ v: Float) {
    guard let p = (node as? AVAudioUnit)?.auAudioUnit.parameterTree?.allParameters.first(where: { $0.displayName == name || $0.identifier == name }) else {
        print("  !! no parameter named \(name)"); return
    }
    p.value = v
}

@main
struct Presets {
    static let reverbNames = ["smallRoom", "mediumRoom", "largeRoom", "mediumHall", "largeHall", "plate", "mediumChamber",
                              "largeChamber", "cathedral", "largeRoom2", "mediumHall2", "mediumHall3", "largeHall2"]
    static let distortionNames = ["drumsBitBrush", "drumsBufferBeats", "drumsLoFi", "multiBrokenSpeaker", "multiCellphoneConcert",
                                  "multiDecimated1", "multiDecimated2", "multiDecimated3", "multiDecimated4", "multiDistortedFunk",
                                  "multiDistortedCubed", "multiDistortedSquared", "multiEcho1", "multiEcho2", "multiEchoTight1",
                                  "multiEchoTight2", "multiEverythingIsBroken", "speechAlienChatter", "speechCosmicInterference",
                                  "speechGoldenPi", "speechRadioTower", "speechWaves"]
    static let eqTypes = ["parametric", "lowPass", "highPass", "resonantLowPass", "resonantHighPass", "bandPass", "bandStop",
                          "lowShelf", "highShelf", "resonantLowShelf", "resonantHighShelf"]

    static func main() throws {
        print(hostLine())
        let url = fixture("speech48s.wav")
        let input = try readAudio(url)
        let tail = 15 * 48000
        let frames = input.frames + tail
        let dry = try render(.file(url), frames: frames) { [] }.audio
        let dryIn = dry.slice(0, input.frames)
        let drySpec = spectrum(dryIn.channels[0], rate: 48000)
        print("fixture speech48s.wav \(input.frames) frames; renders are input + 15 s. dry: peak \(fmtDB(db(peak(dryIn)))) dBFS, RMS \(fmtDB(db(rms(dryIn)))) dBFS, centroid \(Int(drySpec.centroidHz)) Hz, energy <300 \(String(format: "%.3f", drySpec.below300)) 300-3400 \(String(format: "%.3f", drySpec.band)) >3400 \(String(format: "%.3f", drySpec.above3400))")

        // --- The SDK enums, and what the components themselves list at runtime.
        print("\n== enumerations ==")
        print("AVAudioUnitReverbPreset (SDK, raw 0…12): " + reverbNames.enumerated().map { "\($0.offset)=\($0.element)" }.joined(separator: " "))
        print("AVAudioUnitDistortionPreset (SDK, raw 0…21): " + distortionNames.enumerated().map { "\($0.offset)=\($0.element)" }.joined(separator: " "))
        print("AVAudioUnitEQFilterType (SDK, raw 0…10): " + eqTypes.enumerated().map { "\($0.offset)=\($0.element)" }.joined(separator: " "))
        for (label, node) in [("AVAudioUnitReverb", AVAudioUnitReverb() as AVAudioUnit), ("AVAudioUnitDistortion", AVAudioUnitDistortion()),
                              ("AVAudioUnitDelay", AVAudioUnitDelay()), ("AVAudioUnitEQ(2)", AVAudioUnitEQ(numberOfBands: 2)),
                              ("AVAudioUnitTimePitch", AVAudioUnitTimePitch())] {
            let au = node.auAudioUnit
            let presets = au.factoryPresets ?? []
            print("\(label): component \"\(node.name)\" (\(au.componentName ?? "?")), latency \(au.latency) s, tailTime \(au.tailTime) s, factoryPresets \(presets.count): "
                  + presets.map { "\($0.number)=\($0.name)" }.joined(separator: ", "))
            print(paramTree(node))
        }
        // Do raw values past the SDK's last case do anything? (NS_ENUM accepts any raw value.)
        do {
            let r = AVAudioUnitReverb()
            let out = try render(.file(url), frames: frames, afterStart: { _ in r.loadFactoryPreset(AVAudioUnitReverbPreset(rawValue: 13)!) }) { [r] }
            let d = AVAudioUnitReverb()
            let def = try render(.file(url), frames: frames) { [d] }
            print("reverb raw 13 loaded after start: no crash; output == untouched unit: \(out.audio.digest == def.audio.digest); params after render \(params(r, only: ["Small/Large Mix", "Large Size", "Modulation Depth"]))")
        }

        // --- When does a preset take effect?
        print("\n== reverb preset load timing (wet 50 set after the load; digests of speech + 15 s) ==")
        let timing: [(String, Int)] = [("before attach", 0), ("after attach, before start", 1), ("after engine.start()", 2)]
        // Parameter snapshots taken from units that DID load (after start), for variant 4.
        var snapshots: [Int: [(UInt64, AUValue)]] = [:]
        for (label, when) in timing + [("auAudioUnit.currentPreset, before start", 3), ("snapshot params set before start", 4), ("snapshot params before attach", 5), ("auAudioUnit.currentPreset, before attach", 6)] {
            var digests: [String] = []
            var sample = ""
            for (i, name) in reverbNames.enumerated() where [0, 3, 5, 8].contains(i) {
                let preset = AVAudioUnitReverbPreset(rawValue: i)!
                let unit = AVAudioUnitReverb()
                func applySnapshot() {
                    for (addr, v) in snapshots[i] ?? [] { unit.auAudioUnit.parameterTree?.parameter(withAddress: addr)?.value = v }
                    unit.wetDryMix = 50
                }
                if when == 0 { unit.loadFactoryPreset(preset); unit.wetDryMix = 50 }
                if when == 5 { applySnapshot() }
                if when == 6 { unit.auAudioUnit.currentPreset = unit.auAudioUnit.factoryPresets?[i]; unit.wetDryMix = 50 }
                let r = try render(.file(url), frames: frames,
                                   configure: { _ in
                                       if when == 1 { unit.loadFactoryPreset(preset); unit.wetDryMix = 50 }
                                       if when == 3 { unit.auAudioUnit.currentPreset = unit.auAudioUnit.factoryPresets?[i]; unit.wetDryMix = 50 }
                                       if when == 4 { applySnapshot() } },
                                   afterStart: { _ in if when == 2 { unit.loadFactoryPreset(preset); unit.wetDryMix = 50 } }) { [unit] }
                if when == 2 { snapshots[i] = unit.auAudioUnit.parameterTree!.allParameters.map { ($0.address, $0.value) } }
                digests.append("\(name) \(r.audio.digest)")
                if i == 8 { sample = params(unit, only: ["Dry/Wet Mix", "Small/Large Mix", "Large Size", "Modulation Depth"]) }
            }
            print(pad(label, 42) + digests.joined(separator: "  ") + "\n" + String(repeating: " ", count: 42) + "cathedral params after render: \(sample)")
        }
        do {
            // Where does a load after start part company with currentPreset before start?
            let a = AVAudioUnitReverb(), b = AVAudioUnitReverb()
            let ra = try render(.file(url), frames: frames, afterStart: { _ in a.loadFactoryPreset(.cathedral); a.wetDryMix = 50 }) { [a] }.audio
            let rb = try render(.file(url), frames: frames, configure: { _ in b.auAudioUnit.currentPreset = b.auAudioUnit.factoryPresets?[8]; b.wetDryMix = 50 }) { [b] }.audio
            var first = -1
            outer: for i in 0..<ra.frames { for c in 0..<2 where ra.channels[c][i] != rb.channels[c][i] { first = i; break outer } }
            let d = compare(ra, rb)
            print("cathedral loaded after start vs currentPreset before start: first differing frame \(first) (\(String(format: "%.1f", Double(first) / 48)) ms), max |d| \(fmtDB(db(d.maxAbs))) dBFS, \(d.differing) samples differ")
        }
        print("\n== distortion preset load timing ==")
        for (label, when) in timing {
            var digests: [String] = []
            for i in [5, 17, 20] {
                let preset = AVAudioUnitDistortionPreset(rawValue: i)!
                let unit = AVAudioUnitDistortion()
                if when == 0 { unit.loadFactoryPreset(preset) }
                let r = try render(.file(url), frames: frames,
                                   configure: { _ in if when == 1 { unit.loadFactoryPreset(preset) } },
                                   afterStart: { _ in if when == 2 { unit.loadFactoryPreset(preset) } }) { [unit] }
                digests.append("\(distortionNames[i]) \(r.audio.digest)")
            }
            print(pad(label, 28) + digests.joined(separator: "  "))
        }

        func row(_ name: String, _ a: Audio, extra: String = "") -> String {
            let inSpan = a.slice(0, input.frames)
            let sp = spectrum(inSpan.channels[0], rate: 48000)
            let t60 = lastAbove(a, Float(pow(10, -60.0 / 20))) - input.frames
            let t90 = lastAbove(a, Float(pow(10, -90.0 / 20))) - input.frames
            return pad(name, 26)
                + pad(String(format: "%+.1f", db(peak(a)) - db(peak(dryIn))), 8)
                + pad(String(format: "%+.1f", db(rms(inSpan)) - db(rms(dryIn))), 8)
                + pad(t60 > 0 ? "\(t60 * 1000 / 48000)" : "-", 9)
                + pad(t90 > 0 ? "\(t90 * 1000 / 48000)" : "-", 9)
                + pad("\(Int(sp.centroidHz))", 9)
                + pad(String(format: "%.3f %.3f %.3f", sp.below300, sp.band, sp.above3400), 20)
                + pad(a.digest, 18) + extra
        }
        let header = pad("name", 26) + pad("dPeak", 8) + pad("dRMS", 8) + pad("tail60ms", 9) + pad("tail90ms", 9) + pad("centroid", 9)
            + pad("E<300 mid >3400", 20) + pad("digest", 18)
        print("\n== reverb presets on speech (auAudioUnit.currentPreset set before start). dPeak over the whole render, dRMS over the input span, both vs dry; tail = last sample above -60/-90 dBFS past the input end; output length is whatever is rendered: \(frames) frames ==")
        print("dry reference: \(row("dry", dry))")
        print(header + "params as loaded")
        for (i, name) in reverbNames.enumerated() {
            for wet: Float? in [nil, 50] {
                let unit = AVAudioUnitReverb()
                var loaded = ""
                let r = try render(.file(url), frames: frames, configure: { _ in
                    unit.auAudioUnit.currentPreset = unit.auAudioUnit.factoryPresets?[i]
                    loaded = "immediately: wetDryMix=\(unit.wetDryMix) LargeSize=\(params(unit, only: ["Large Size"]))"
                    if let w = wet { unit.wetDryMix = w }
                }) { [unit] }
                print(row(name + (wet == nil ? " (as loaded)" : " wet50"), r.audio, extra: wet == nil ? loaded + " | after render: wetDryMix=\(unit.wetDryMix) " + params(unit) : ""))
            }
        }

        print("\n== distortion presets on speech (loaded after start — same digests as before attach, wetDryMix/preGain as the preset leaves them) ==")
        print(header + "wetDryMix preGain | the preset's mixes")
        let mixNames = ["Delay", "Decay", "Delay Mix", "Decimation", "Decimation Mix", "Rounding", "Linear Term", "Squared Term", "Cubic Term", "Polynomial Mix", "Ring Mod Freq 1", "Ring Mod Freq 2", "Ring Mod Balance", "Ring Mod Mix", "Soft Clip Gain", "Wet/Dry Mix"]
        for (i, name) in distortionNames.enumerated() {
            let unit = AVAudioUnitDistortion()
            var loaded = ""
            let r = try render(.file(url), frames: frames, afterStart: { _ in
                unit.loadFactoryPreset(AVAudioUnitDistortionPreset(rawValue: i)!)
                loaded = "\(unit.wetDryMix) \(unit.preGain)"
            }) { [unit] }
            print(row(name, r.audio, extra: loaded + " | " + params(unit, only: mixNames)))
        }

        print("\n== hand-built candidates (parameters set before start through the AU parameter tree) ==")
        print(header)
        let hand: [(String, () -> [AVAudioNode], ((AVAudioEngine) -> Void)?)] = [
            ("delay defaults", { [AVAudioUnitDelay()] }, nil),
            ("delay 0.25 fb40 wet35", { [delay()] }, nil),
            ("EQ bass +6 lowShelf120", { let u = AVAudioUnitEQ(numberOfBands: 1); u.bands[0].filterType = .lowShelf; u.bands[0].frequency = 120; u.bands[0].gain = 6; u.bands[0].bypass = false; return [u] }, nil),
            ("EQ treble +6 hiShelf6k", { let u = AVAudioUnitEQ(numberOfBands: 1); u.bands[0].filterType = .highShelf; u.bands[0].frequency = 6000; u.bands[0].gain = 6; u.bands[0].bypass = false; return [u] }, nil),
            ("EQ bright +6 hiShelf3k", { let u = AVAudioUnitEQ(numberOfBands: 1); u.bands[0].filterType = .highShelf; u.bands[0].frequency = 3000; u.bands[0].gain = 6; u.bands[0].bypass = false; return [u] }, nil),
            ("EQ telephone HP300 LP3400", { [eqTelephone()] }, nil),
            ("EQ bandPass 1.5k bw2.5oct", { let u = AVAudioUnitEQ(numberOfBands: 1); u.bands[0].filterType = .bandPass; u.bands[0].frequency = 1500; u.bands[0].bandwidth = 2.5; u.bands[0].bypass = false; return [u] }, nil),
            ("radio: EQ HP500 LP4500 + RadioTower", { let e = AVAudioUnitEQ(numberOfBands: 2); e.bands[0].filterType = .highPass; e.bands[0].frequency = 500; e.bands[0].bypass = false; e.bands[1].filterType = .lowPass; e.bands[1].frequency = 4500; e.bands[1].bypass = false; return [e, distortion(.speechRadioTower)] }, nil),
        ]
        for (name, make, _) in hand {
            let r = try render(.file(url), frames: frames, makeUnits: make)
            print(row(name, r.audio))
        }
        // Robot and bit-crush out of AUDistortion's own terms, set by name.
        let robot = AVAudioUnitDistortion()
        let rr = try render(.file(url), frames: frames, configure: { _ in
            robot.loadFactoryPreset(.multiDistortedCubed)
            for (k, v) in [("Delay Mix", 0), ("Decimation Mix", 0), ("Polynomial Mix", 0), ("Ring Mod Freq 1", 50), ("Ring Mod Freq 2", 50),
                           ("Ring Mod Balance", 100), ("Ring Mod Mix", 100), ("Soft Clip Gain", 0)] as [(String, Float)] { setParam(robot, k, v) }
            robot.wetDryMix = 100; robot.preGain = 0
        }) { [robot] }
        print(row("robot: ringmod 50 Hz", rr.audio, extra: params(robot, only: mixNames)))
        let crush = AVAudioUnitDistortion()
        let cr = try render(.file(url), frames: frames, configure: { _ in
            crush.loadFactoryPreset(.multiDecimated1)
            for (k, v) in [("Delay Mix", 0), ("Ring Mod Mix", 0), ("Polynomial Mix", 0), ("Decimation", 75), ("Rounding", 60),
                           ("Decimation Mix", 100), ("Soft Clip Gain", 0)] as [(String, Float)] { setParam(crush, k, v) }
            crush.wetDryMix = 100; crush.preGain = 0
        }) { [crush] }
        print(row("bitcrush: decim75 round60", cr.audio, extra: params(crush, only: mixNames)))

        // Write a few outputs for anyone who wants to listen later.
        let dir = workDir()
        try writeAudio(rr.audio, to: dir.appendingPathComponent("robot.caf"), kind: .cafFloat)
        try writeAudio(cr.audio, to: dir.appendingPathComponent("bitcrush.caf"), kind: .cafFloat)
    }
}
