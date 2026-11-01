// tools/proof/audio_ap10b_probe.swift — the in-process instrument behind
// `audio_ap10b_proof.py --probe` (road map "audio" AP10 part 2a, spec §11
// AU-108). Compiled with every file in `app/Sources` but `main.swift` through
// `swift_build.py`'s line, copied in as `main.swift`.
//
//     audio_ap10b_probe <work-dir>
//
// One line per row, `ok <ID> — <detail>` or `FAIL <ID> — <detail>`; no app is
// launched.
//
//  B1  `ExportAudioMaster(limits: false)`, a stem's master: two float buffers
//      whose samples run past the −1 dBTP ceiling and past full scale, at 24
//      bits, come out as `round(clip(input × 2²³))` frame for frame — the
//      first stamp 0, every frame where it went in, nothing dropped for a
//      latency — and `finish()` answers no tail. The same input through the
//      default master (`limits` true) is changed by the limiter (the control).
//  B2  `ExportStemsPipeline`'s names: `url(for:mix:)` beside the mix with the
//      mix's extension; `summary` "", " and 1 stem", " and 3 stems"; and
//      `collision` answers an exact match, a match differing only in case, and
//      a stem path that is a symlink to a source, and nil when no stem path is
//      a source.
import AVFoundation
import AppKit

_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.prohibited)

func row(_ id: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "ok" : "FAIL") \(id) — \(detail)")
    fflush(stdout)
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

guard CommandLine.arguments.count == 2 else {
    row("B1", false, "usage: audio_ap10b_probe <work-dir>")
    exit(0)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

// MARK: - B1

/// Input sample k of buffer b, left channel: swinging to ±1.25 so some samples
/// pass the ceiling and some full scale, on the 24-bit grid, and off it by a
/// quarter step under 2²⁰ steps, where a `Float` still holds the quarter (so
/// rounding has no ties). The right channel is its negative.
func value(buffer: Int, index: Int) -> Float {
    let phase = Double(buffer * 4096 + index) * 2 * Double.pi * 440 / 48_000
    let whole = (sin(phase) * 1.25 * 8_388_608).rounded(.down)
    let step = abs(whole) < 1_048_576 ? whole + 0.25 : whole
    return Float(step / 8_388_608)
}

func expected(_ v: Float) -> Int32 {
    let scaled = min(max(v * 8_388_608, -8_388_608), 8_388_607)
    return Int32(scaled.rounded())
}

func floatBuffer(buffer: Int, frames: Int, at frame: Int) throws -> CMSampleBuffer {
    var samples = [Float](repeating: 0, count: frames * 2)
    for k in 0..<frames {
        samples[2 * k] = value(buffer: buffer, index: k)
        samples[2 * k + 1] = -value(buffer: buffer, index: k)
    }
    var asbd = AudioStreamBasicDescription(
        mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2,
        mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil,
        formatDescriptionOut: &format) == noErr, let format
    else { throw ProbeError(description: "no float format") }
    let bytes = samples.count * 4
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
        dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
        blockBufferOut: &block) == kCMBlockBufferNoErr, let block
    else { throw ProbeError(description: "no block") }
    let copied = samples.withUnsafeBytes { raw -> OSStatus in
        guard let base = raw.baseAddress else { return -1 }
        return CMBlockBufferReplaceDataBytes(
            with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
    }
    guard copied == kCMBlockBufferNoErr else { throw ProbeError(description: "no copy") }
    var sample: CMSampleBuffer?
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
        sampleCount: frames,
        presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 48000),
        packetDescriptions: nil, sampleBufferOut: &sample) == noErr, let sample
    else { throw ProbeError(description: "no sample") }
    return sample
}

/// One output buffer: its stamp in frames and both channels' 24-bit integers.
struct Out {
    let frame: Int
    let left: [Int32]
    let right: [Int32]
}

func read(_ sample: CMSampleBuffer) throws -> Out {
    let stamp = CMTimeConvertScale(
        CMSampleBufferGetPresentationTimeStamp(sample), timescale: 48000,
        method: .roundHalfAwayFromZero
    ).value
    let frames = CMSampleBufferGetNumSamples(sample)
    guard let block = CMSampleBufferGetDataBuffer(sample) else {
        throw ProbeError(description: "an output buffer with no data")
    }
    var bytes = [UInt8](repeating: 0, count: frames * 6)
    guard CMBlockBufferGetDataLength(block) == bytes.count,
        CMBlockBufferCopyDataBytes(
            block, atOffset: 0, dataLength: bytes.count, destination: &bytes)
            == kCMBlockBufferNoErr
    else { throw ProbeError(description: "an output buffer of the wrong length") }
    func at(_ offset: Int) -> Int32 {
        let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
        return Int32(bitPattern: raw << 8) >> 8
    }
    return Out(
        frame: Int(stamp), left: (0..<frames).map { at(6 * $0) },
        right: (0..<frames).map { at(6 * $0 + 3) })
}

/// The master over two 4,096-frame buffers at 0 and 4,096, then `finish()`:
/// the outputs, and whether `finish()` answered a tail.
func run(limits: Bool) throws -> (outs: [Out], tail: Bool) {
    let master = ExportAudioMaster(bits: 24, ceilingDBTP: -1, origin: .zero, limits: limits)
    var outs: [Out] = []
    for (buffer, at) in [(0, 0), (1, 4096)] {
        if let made = try master.apply(to: try floatBuffer(buffer: buffer, frames: 4096, at: at)) {
            outs.append(try read(made))
        }
    }
    let tail = try master.finish()
    if let tail { outs.append(try read(tail)) }
    return (outs, tail != nil)
}

do {
    let wantLeft = (0..<2).flatMap { b in (0..<4096).map { expected(value(buffer: b, index: $0)) } }
    let wantRight = (0..<2).flatMap { b in
        (0..<4096).map { expected(-value(buffer: b, index: $0)) }
    }
    let (outs, tail) = try run(limits: false)
    var contiguous = true
    var next = 0
    for out in outs {
        if out.frame != next { contiguous = false }
        next = out.frame + out.left.count
    }
    let left = outs.flatMap(\.left)
    let right = outs.flatMap(\.right)
    let firstDiff = zip(left, wantLeft).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        ?? zip(right, wantRight).enumerated().first { $0.element.0 != $0.element.1 }?.offset
    let over = wantLeft.filter { abs(Double($0)) > 0.891 * 8_388_608 }.count
    let control = try run(limits: true).outs.flatMap(\.left)
    let limited = control.count == wantLeft.count && control != wantLeft
    row("B1", outs.first?.frame == 0 && contiguous && left.count == 8192 && right.count == 8192
        && firstDiff == nil && !tail && over > 0 && limited,
        "limits false: first stamp \(outs.first.map { String($0.frame) } ?? "none") (want 0), "
            + "contiguous \(contiguous), \(left.count) frames (want 8192), first differing frame "
            + "\(firstDiff.map(String.init) ?? "none"), tail \(tail) (want none); \(over) input "
            + "frames above −1 dBTP; the default master changes them: \(limited)")
} catch {
    row("B1", false, "\(error)")
}

// MARK: - B2

func settings(stems count: Int) -> ExportSettings? {
    let stems = (0..<count).map { ["name": "S\($0)", "tracks": [$0 + 1]] as [String: Any] }
    guard let data = try? JSONSerialization.data(withJSONObject: ["stems": stems]) else {
        return nil
    }
    return try? JSONDecoder().decode(ExportSettings.self, from: data)
}

do {
    let fm = FileManager.default
    let scratch = work.appendingPathComponent("b2", isDirectory: true)
    try? fm.removeItem(at: scratch)
    let real = scratch.appendingPathComponent("real", isDirectory: true)
    let linked = scratch.appendingPathComponent("linked", isDirectory: true)
    try fm.createDirectory(at: real, withIntermediateDirectories: true)
    try fm.createDirectory(at: linked, withIntermediateDirectories: true)

    let dialogue = ExportStem(name: "Dialogue", tracks: [2])
    let music = ExportStem(name: "Music", tracks: [3])
    let mix = real.appendingPathComponent("Mix.wav")
    let named = ExportStemsPipeline.url(for: dialogue, mix: mix)
    let bare = ExportStemsPipeline.url(for: dialogue, mix: real.appendingPathComponent("Mix"))
    let names = named.path == real.appendingPathComponent("Mix - Dialogue.wav").path
        && bare.lastPathComponent == "Mix - Dialogue"

    let summaries = [0, 1, 3].map { settings(stems: $0).map(ExportStemsPipeline.summary) }
    let summaryOK = summaries == ["", " and 1 stem", " and 3 stems"]

    // The sources: a media file at the Dialogue stem's path, and one the Music
    // stem's path in `linked` is a symlink to.
    let source = real.appendingPathComponent("Mix - Dialogue.wav")
    try Data([1, 2, 3]).write(to: source)
    let target = real.appendingPathComponent("music source.wav")
    try Data([4, 5, 6]).write(to: target)
    try fm.createSymbolicLink(
        at: linked.appendingPathComponent("Mix - Music.wav"), withDestinationURL: target)
    let other = real.appendingPathComponent("unrelated.wav")

    let exact = ExportStemsPipeline.collision(stems: [music, dialogue], mix: mix, sources: [source])
    let cased = ExportStemsPipeline.collision(
        stems: [dialogue], mix: mix,
        sources: [real.appendingPathComponent("MIX - DIALOGUE.WAV")])
    let symlinked = ExportStemsPipeline.collision(
        stems: [dialogue, music], mix: linked.appendingPathComponent("Mix.wav"), sources: [target])
    let none = ExportStemsPipeline.collision(
        stems: [dialogue, music], mix: mix, sources: [other, target])
    let collisions = exact?.lastPathComponent == "Mix - Dialogue.wav"
        && cased?.lastPathComponent == "Mix - Dialogue.wav"
        && symlinked?.lastPathComponent == "Mix - Music.wav" && none == nil
    let sentence = ExportStemsPipeline.SourceCollision(url: source).localizedDescription
    let sentenceOK = sentence
        == "The stem “Mix - Dialogue.wav” would replace media this project uses; "
        + "export under another name."
    row("B2", names && summaryOK && collisions && sentenceOK,
        "url \(named.lastPathComponent), no extension \(bare.lastPathComponent); summaries "
            + "\(summaries.map { $0.map { "\"\($0)\"" } ?? "nil" }); collision exact "
            + "\(exact?.lastPathComponent ?? "nil"), case-only \(cased?.lastPathComponent ?? "nil"), "
            + "symlink \(symlinked?.lastPathComponent ?? "nil"), none \(none?.path ?? "nil"); "
            + "sentence \"\(sentence)\"")
} catch {
    row("B2", false, "\(error)")
}
