import AVFoundation
import AudioToolbox
import Foundation

// Spike S2: AUSoundIsolation ('aufx' 'vois' 'appl') driven offline the way
// RampAudioRenderer+TimePitch.swift drives AVAudioUnitTimePitch:
// AVAudioSourceNode -> the unit -> the main mixer, AVAudioEngine manual
// rendering (.offline). Writes raw interleaved float32 (.f32) and prints one
// JSON line of what it saw.
//
// isolate --in x.wav --out y.f32 [--type 0|1] [--mix pct] [--block N]
//         [--maxframes N] [--raw] [--start s --preroll s --length s]
//         [--repeat N]
//   --raw      write every rendered frame (no latency discard), plus 1 s pad
//   default    discard the unit's reported latency L and feed L zeros at the end

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains(name) }

func cpuSeconds() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec) + Double(u.ru_utime.tv_usec) / 1e6
        + Double(u.ru_stime.tv_sec) + Double(u.ru_stime.tv_usec) / 1e6
}
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

let inPath = arg("--in")!
let outPath = arg("--out")!
let soundType = Float(arg("--type") ?? "1")!
let mix = Float(arg("--mix") ?? "100")!
let block = Int(arg("--block") ?? "4096")!
let maxFrames = Int(arg("--maxframes") ?? "4096")!
let raw = flag("--raw")
let repeats = Int(arg("--repeat") ?? "1")!
let zeroPre = flag("--zeropre")  // feed the pre-roll as digital silence, not the media

// Read the whole file as deinterleaved float.
let file = try AVAudioFile(forReading: URL(fileURLWithPath: inPath), commonFormat: .pcmFormatFloat32, interleaved: false)
let sr = file.processingFormat.sampleRate
let channels = Int(file.processingFormat.channelCount)
let total = Int(file.length)
let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(total))!
try file.read(into: inBuf)
var source: [[Float]] = (0..<channels).map { c in Array(UnsafeBufferPointer(start: inBuf.floatChannelData![c], count: total)) }

// Optional window: from `start` with `preroll` seconds fed first and discarded.
var firstFrame = 0
var keepFrames = total
var prerollFrames = 0
if let s = arg("--start") {
    let start = Int((Double(s)! * sr).rounded())
    prerollFrames = Int((Double(arg("--preroll") ?? "0")! * sr).rounded())
    firstFrame = start - prerollFrames
    keepFrames = Int((Double(arg("--length") ?? "5")! * sr).rounded())
}
// --leadzeros N: N frames of digital silence fed BEFORE the pre-roll (and discarded).
let leadZeros = Int(arg("--leadzeros") ?? "0")!
firstFrame -= leadZeros
prerollFrames += leadZeros

struct Result {
    var out: [Float]
    var report: [String: Any]
}

func render() throws -> Result {
    var report: [String: Any] = [:]
    let t0 = now(), c0 = cpuSeconds()
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: AVAudioChannelCount(channels)) else {
        fatalError("no format")
    }
    let desc = AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_AUSoundIsolation,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    let unit = AVAudioUnitEffect(audioComponentDescription: desc)
    var st = AudioUnitSetParameter(unit.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_SoundToIsolate), kAudioUnitScope_Global, 0, soundType, 0)
    report["set_type_status"] = Int(st)
    st = AudioUnitSetParameter(unit.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_WetDryMixPercent), kAudioUnitScope_Global, 0, mix, 0)
    report["set_mix_status"] = Int(st)

    var next = firstFrame
    var fedReal = 0
    let node = AVAudioSourceNode(format: format) { _, _, count, list in
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for (c, b) in buffers.enumerated() {
            let d = b.mData!.assumingMemoryBound(to: Float.self)
            let ch = source[min(c, channels - 1)]
            for i in 0..<Int(count) {
                let f = next + i
                let silent = (zeroPre && f < firstFrame + prerollFrames) || f < firstFrame + leadZeros
                d[i] = (!silent && f >= 0 && f < total) ? ch[f] : 0
            }
        }
        next += Int(count)
        fedReal += Int(count)
        return noErr
    }
    let engine = AVAudioEngine()
    engine.attach(node)
    engine.attach(unit)
    engine.connect(node, to: unit, format: format)
    engine.connect(unit, to: engine.mainMixerNode, format: format)
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: AVAudioFrameCount(maxFrames))
    try engine.start()
    let t1 = now()
    report["setup_s"] = t1 - t0

    var readType: AudioUnitParameterValue = -1, readMix: AudioUnitParameterValue = -1
    AudioUnitGetParameter(unit.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_SoundToIsolate), kAudioUnitScope_Global, 0, &readType)
    AudioUnitGetParameter(unit.audioUnit, AudioUnitParameterID(kAUSoundIsolationParam_WetDryMixPercent), kAudioUnitScope_Global, 0, &readMix)
    report["type_read"] = Double(readType)
    report["mix_read"] = Double(readMix)
    report["latency_s"] = unit.latency
    report["au_latency_s"] = unit.auAudioUnit.latency
    report["tail_s"] = unit.auAudioUnit.tailTime
    let latency = Int((unit.latency * sr).rounded())
    report["latency_frames"] = latency
    report["manual_format"] = "\(engine.manualRenderingFormat)"

    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: AVAudioFrameCount(maxFrames))!
    let discard = raw ? 0 : prerollFrames + latency
    let want = raw ? (total - firstFrame + Int(sr)) : keepFrames
    var out = [Float](); out.reserveCapacity(want * channels)
    var rendered = 0
    var firstCall: Double = -1
    var calls = 0
    while out.count < want * channels {
        let tc = now()
        let status = try engine.renderOffline(AVAudioFrameCount(block), to: buffer)
        if firstCall < 0 { firstCall = now() - tc }
        calls += 1
        guard status == .success else { fatalError("status \(status.rawValue)") }
        let got = Int(buffer.frameLength)
        let data = buffer.floatChannelData!
        let from = max(0, discard - rendered)
        for i in min(from, got)..<got {
            if out.count >= want * channels { break }
            for c in 0..<channels { out.append(data[c][i]) }
        }
        rendered += got
        if got == 0 { fatalError("no frames") }
    }
    engine.stop()
    let t2 = now(), c2 = cpuSeconds()
    report["first_call_s"] = firstCall
    report["calls"] = calls
    report["render_s"] = t2 - t1
    report["wall_s"] = t2 - t0
    report["cpu_s"] = c2 - c0
    report["frames_out"] = out.count / channels
    report["rendered"] = rendered
    report["sr"] = sr
    report["channels"] = channels
    report["xrt"] = Double(want) / sr / (t2 - t0)
    return Result(out: out, report: report)
}

var first: [Float] = []
var reports: [[String: Any]] = []
for r in 0..<repeats {
    let res = try render()
    var rep = res.report
    if r == 0 {
        first = res.out
        let data = res.out.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: URL(fileURLWithPath: outPath))
    } else {
        rep["identical_to_first"] = (res.out == first)
        var maxd: Float = 0
        for i in 0..<min(first.count, res.out.count) { maxd = max(maxd, abs(first[i] - res.out[i])) }
        rep["max_abs_diff_to_first"] = Double(maxd)
    }
    reports.append(rep)
}
let json = try JSONSerialization.data(withJSONObject: ["in": inPath, "type": Double(soundType), "mix": Double(mix), "block": block, "runs": reports], options: [.sortedKeys])
print(String(data: json, encoding: .utf8)!)
