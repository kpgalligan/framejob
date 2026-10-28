// Road map "codec-export" C3, fix pass 1 — the `av1_webm` row's sound before the file: the
// Opus encoder's FIFO fed by byte count (`ExportOpusEncoder.encode`), and the sound placed at
// its stamps (`ExportAudioEnd.align`), spec §11 CX-15 (5). `webm_export_proof.py` builds and
// runs it (its P rows).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// module `FrameJob`, against `libframejob_core.a`, on `swift_build.py`'s line. No window, no
// app; AudioToolbox's own Opus encoder.
//
//   webm_audio_probe [answer.json]
//
// One JSON object out (to the answer path, else stdout): `rows`, each a name, ok and detail.
//
//   P1  three buffers of 4,096, 4,096 and 37 frames (a short last one) encode with no throw;
//       `framesFed` 8,229, then `finish()`: packets × 960 ≥ pre-skip + 8,229, and every
//       packet the converter answered was returned
//   P2  a 4,096-frame buffer cut to 1,000 by `ExportAudioEnd.fit` (a range's end) encodes
//       1,000 frames
//   P3  a buffer whose 404 bytes outrun its 100 samples is fed by its bytes: 101 frames
//   P4  a buffer whose 396 bytes fall short of its 100 samples is fed by its bytes: 99
//   P5  a buffer of 402 bytes (not a whole 4-byte frame) throws `.failed` naming 402 and
//       "not a whole number of 16-bit stereo frames"
//   A1–A5  `ExportAudioEnd.align`, each on its own instance with `lead` frames fitted:
//   A1  nothing written, a buffer at frame 500: 500 frames of zeros, then the buffer itself
//   A2  1,500 written, a 300-frame buffer at frame 1,400: one buffer of 200 frames whose
//       first frame is the original's frame 100 (the covered head cut)
//   A3  1,500 written, a 300-frame buffer at frame 1,000 (covered whole): nothing
//   A4  1,500 written, a buffer at frame 1,500 (no gap): the buffer itself
//   A5  a 2,000-frame target, 1,500 written, a buffer at frame 5,000: the gap's zeros stop
//       at the target (500 frames)
import AVFoundation

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

/// A 48 kHz 16-bit buffer of `channels` channels: `samples` samples over `bytes` bytes, each
/// stereo frame's left sample its own index (so a cut can be read back), stamped at `at`.
func buffer(samples: Int, bytes: Int? = nil, channels: UInt32 = 2, at: Int = 0)
    -> CMSampleBuffer?
{
    let frameBytes = Int(channels) * 2
    let length = bytes ?? samples * frameBytes
    var description = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: UInt32(frameBytes), mFramesPerPacket: 1,
        mBytesPerFrame: UInt32(frameBytes), mChannelsPerFrame: channels, mBitsPerChannel: 16,
        mReserved: 0)
    var format: CMAudioFormatDescription?
    guard CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        == noErr, let format
    else { return nil }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
        dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        == kCMBlockBufferNoErr, let block
    else { return nil }
    var values = [Int16](repeating: 0, count: length / 2)
    for i in stride(from: 0, to: values.count, by: Int(channels)) {
        values[i] = Int16(truncatingIfNeeded: i / Int(channels))
    }
    let copied = values.withUnsafeBytes {
        CMBlockBufferReplaceDataBytes(
            with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
            dataLength: length - length % 2)
    }
    guard copied == kCMBlockBufferNoErr else { return nil }
    var sample: CMSampleBuffer?
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
        sampleCount: samples, presentationTimeStamp: CMTime(value: CMTimeValue(at), timescale: 48_000),
        packetDescriptions: nil, sampleBufferOut: &sample) == noErr
    else { return nil }
    return sample
}

/// The first left sample of `sample` (the source frame index a fixture wrote there).
func firstLeft(_ sample: CMSampleBuffer) -> Int? {
    guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
    var value: Int16 = 0
    guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 2, destination: &value)
        == kCMBlockBufferNoErr
    else { return nil }
    return Int(value)
}

/// Every sample in `sample` is zero.
func silent(_ sample: CMSampleBuffer) -> Bool {
    guard let block = CMSampleBufferGetDataBuffer(sample) else { return false }
    let length = CMBlockBufferGetDataLength(block)
    var bytes = [UInt8](repeating: 1, count: length)
    guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)
        == kCMBlockBufferNoErr
    else { return false }
    return bytes.allSatisfy { $0 == 0 }
}

func frames(_ samples: [CMSampleBuffer]) -> [Int] { samples.map(CMSampleBufferGetNumSamples) }

func range(frames: Int) -> CMTimeRange {
    CMTimeRange(start: .zero, duration: CMTime(value: CMTimeValue(frames), timescale: 48_000))
}

/// (frames fed, the error's text) for one buffer into a fresh encoder.
func feed(_ sample: CMSampleBuffer?) -> (fed: Int?, error: String?) {
    guard let sample else { return (nil, "the fixture could not be made") }
    do {
        let opus = try ExportOpusEncoder(bitRate: ExportOpusEncoder.defaultBitRate)
        _ = try opus.encode(sample)
        return (opus.framesFed, nil)
    } catch Exporter.ExportError.failed(let text) {
        return (nil, text)
    } catch {
        return (nil, "\(error)")
    }
}

// P1 — a short last buffer.
do {
    let opus = try ExportOpusEncoder(bitRate: ExportOpusEncoder.defaultBitRate)
    var packets = 0
    for count in [4_096, 4_096, 37] {
        guard let sample = buffer(samples: count) else { throw Exporter.ExportError.cancelled }
        packets += try opus.encode(sample).count
    }
    let fed = opus.framesFed
    packets += try opus.finish().count
    let covered = packets * ExportOpusEncoder.framesPerPacket
    check("P1 4,096 + 4,096 + 37 frames (a short last buffer) encode and finish",
          fed == 8_229 && covered >= opus.preSkip + 8_229 && packets == opus.packetsOut,
          "framesFed \(fed) before finish (want 8229); \(packets) packets × 960 = \(covered) "
            + "(want ≥ pre-skip \(opus.preSkip) + 8229); packetsOut \(opus.packetsOut)")
} catch {
    check("P1 4,096 + 4,096 + 37 frames (a short last buffer) encode and finish", false,
          "threw \(error)")
}

// P2 — a buffer cut at the range's end by `fit`.
do {
    let end = ExportAudioEnd(range: range(frames: 1_000))
    let cut = buffer(samples: 4_096).flatMap { end.fit($0) }
    let got = feed(cut)
    check("P2 a 4,096-frame buffer cut to 1,000 by fit encodes 1,000 frames",
          got.fed == 1_000, "fed \(got.fed.map(String.init) ?? "nil"), error \(got.error ?? "nil")")
}

// P3–P5 — the frames are the bytes'.
let p3 = feed(buffer(samples: 100, bytes: 404))
check("P3 404 bytes over 100 samples are fed as 101 frames", p3.fed == 101,
      "fed \(p3.fed.map(String.init) ?? "nil"), error \(p3.error ?? "nil")")
let p4 = feed(buffer(samples: 100, bytes: 396))
check("P4 396 bytes under 100 samples are fed as 99 frames", p4.fed == 99,
      "fed \(p4.fed.map(String.init) ?? "nil"), error \(p4.error ?? "nil")")
let p5 = feed(buffer(samples: 100, bytes: 402))
check("P5 402 bytes throw .failed naming 402 and \"not a whole number of 16-bit stereo frames\"",
      p5.fed == nil && p5.error?.contains("402 bytes") == true
        && p5.error?.contains("not a whole number of 16-bit stereo frames") == true,
      "fed \(p5.fed.map(String.init) ?? "nil"), error \(p5.error ?? "nil")")

// A1–A5 — placed at the stamps, each on its own `ExportAudioEnd` (`lead` frames already
// handed on through `fit`, so `written` is where the stream stands).
func audioEnd(target: Int = 48_000, lead: Int) -> ExportAudioEnd {
    let end = ExportAudioEnd(range: range(frames: target))
    if lead > 0, let sample = buffer(samples: lead) { _ = end.fit(sample) }
    return end
}

let a1End = audioEnd(lead: 0)
let a1Sample = buffer(samples: 1_000, at: 500)
let a1 = a1Sample.map { a1End.align($0, at: 500) } ?? []
check("A1 a buffer at frame 500 with nothing written: 500 frames of zeros, then the buffer",
      frames(a1) == [500, 1_000] && silent(a1[0]) && a1[1] === a1Sample,
      "placed \(frames(a1)), the first silent \(a1.first.map(silent) ?? false), the second the "
        + "buffer itself \(a1.count == 2 && a1[1] === a1Sample)")

let a2End = audioEnd(lead: 1_500)
let a2 = buffer(samples: 300, at: 1_400).map { a2End.align($0, at: 1_400) } ?? []
let a2First = a2.first.flatMap(firstLeft)
check("A2 1,500 written, a 300-frame buffer at frame 1,400: its last 200, from its frame 100",
      a2End.written == 1_500 && frames(a2) == [200] && a2First == 100,
      "written \(a2End.written); placed \(frames(a2)), first left sample "
        + "\(a2First.map(String.init) ?? "nil") (want 100)")

let a3End = audioEnd(lead: 1_500)
let a3 = buffer(samples: 300, at: 1_000).map { a3End.align($0, at: 1_000) } ?? [CMSampleBuffer]()
check("A3 1,500 written, a 300-frame buffer at frame 1,000 (covered whole): nothing",
      a3End.written == 1_500 && a3.isEmpty, "placed \(frames(a3))")

let a4End = audioEnd(lead: 1_500)
let a4Sample = buffer(samples: 300, at: 1_500)
let a4 = a4Sample.map { a4End.align($0, at: 1_500) } ?? []
check("A4 1,500 written, a buffer at frame 1,500 (no gap): the buffer itself",
      frames(a4) == [300] && a4.first === a4Sample, "placed \(frames(a4))")

let a5End = audioEnd(target: 2_000, lead: 1_500)
let a5 = buffer(samples: 100, at: 5_000).map { a5End.align($0, at: 5_000) } ?? []
let a5Zeros = a5.dropLast().reduce(0) { $0 + CMSampleBufferGetNumSamples($1) }
check("A5 a 2,000-frame target, 1,500 written, a buffer at frame 5,000: 500 frames of zeros",
      a5End.written == 1_500 && a5Zeros == 500 && a5.dropLast().allSatisfy(silent),
      "written \(a5End.written); placed \(frames(a5)), zeros \(a5Zeros) (want 500)")

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.prettyPrinted])
if CommandLine.arguments.count > 1 {
    try answer.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} else {
    FileHandle.standardOutput.write(answer)
}
exit(0)
