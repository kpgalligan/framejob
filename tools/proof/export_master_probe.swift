// The export master's placement by stamp (road map "audio" AP2 part 2, spec §11 AU-27),
// driven with synthetic float buffers through the product's own `ExportAudioMaster`.
// Compiled with app/Sources by `export_master_proof.py --probe` (swift_build).
//
// Every row: 24-bit, gain 1, the default −1 dBTP ceiling, origin 0, a signal far under the
// ceiling (so the limiter's gain is exactly 1 and the master is an exact, compensated
// delay). Input sample k of buffer b is a value no other sample has, a multiple of 2⁻¹⁵,
// so each output sample's 24-bit integer names the input sample it came from.
//
//   M1  a hole: buffers at frames 0..4095 then 4200..8295. Output frames 4096..4199 are
//       zero, frame 4200 holds buffer 2's first sample, and every output buffer is
//       stamped where the last ended (one contiguous stream from frame 0).
//   M2  an overlap: buffers at 0..4095 then 3996..8091. Buffer 2's frame 100 lands at
//       output 4096, nothing doubled; the total length is the union, 8,092 frames.
//   M3  a late start: the first buffer at frame 480. The first output stamp is
//       480 / 48 000 s and every sample k of the stream sits at frame 480 + k.
//
// Prints one JSON object {"rows": [{name, ok, detail}]} on stdout.
import AVFoundation
import Foundation

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String) {
    rows.append(["name": name, "ok": ok, "detail": detail])
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
}

/// Input sample `index` of buffer `buffer`: a distinct multiple of 2⁻¹⁵ under 0.25.
func value(buffer: Int, index: Int) -> Float {
    Float((buffer * 5000 + index) % 8000 + 1) / 32768
}

/// Its 24-bit integer once quantised: value × 2²³, exact.
func expected(_ v: Float) -> Int32 { Int32(v * 8_388_608) }

/// A float stereo buffer of `frames` frames stamped at `frame` / 48 kHz: left the
/// buffer's values, right their negatives.
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

/// One output buffer: its stamp in frames and its left channel's 24-bit integers.
struct Out {
    let frame: Int
    let left: [Int32]
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
    var left: [Int32] = []
    for k in 0..<frames {
        let raw = UInt32(bytes[6 * k]) | UInt32(bytes[6 * k + 1]) << 8
            | UInt32(bytes[6 * k + 2]) << 16
        left.append(Int32(bitPattern: raw << 8) >> 8)
    }
    return Out(frame: Int(stamp), left: left)
}

/// The master over `inputs` ((buffer, frames, at)), then `finish()`.
func run(_ inputs: [(Int, Int, Int)]) throws -> [Out] {
    let master = ExportAudioMaster(bits: 24, ceilingDBTP: -1, origin: .zero)
    var outs: [Out] = []
    for (buffer, frames, at) in inputs {
        if let made = try master.apply(to: try floatBuffer(buffer: buffer, frames: frames, at: at)) {
            outs.append(try read(made))
        }
    }
    if let tail = try master.finish() { outs.append(try read(tail)) }
    return outs
}

/// The stream as one array, and whether every buffer starts where the last ended.
func joined(_ outs: [Out]) -> (start: Int?, samples: [Int32], contiguous: Bool) {
    var contiguous = true
    var next = outs.first?.frame
    var all: [Int32] = []
    for out in outs {
        if out.frame != next { contiguous = false }
        all += out.left
        next = out.frame + out.left.count
    }
    return (outs.first?.frame, all, contiguous)
}

/// The first index where `got` and `want` differ, or nil.
func firstDifference(_ got: [Int32], _ want: [Int32]) -> Int? {
    if got.count != want.count { return min(got.count, want.count) }
    return zip(got, want).enumerated().first { $0.element.0 != $0.element.1 }?.offset
}

func row(_ name: String, inputs: [(Int, Int, Int)], start: Int, want: [Int32], note: String) {
    do {
        let stream = joined(try run(inputs))
        let diff = firstDifference(stream.samples, want)
        let ok = stream.start == start && stream.contiguous && diff == nil
        check(name, ok, "\(note); first stamp \(stream.start.map(String.init) ?? "none") "
            + "(want \(start)), contiguous \(stream.contiguous), \(stream.samples.count) frames "
            + "(want \(want.count)), first differing frame "
            + "\(diff.map { "\($0): got \($0 < stream.samples.count ? stream.samples[$0] : 0), want \($0 < want.count ? want[$0] : 0)" } ?? "none")")
    } catch {
        check(name, false, "\(error)")
    }
}

let n = 4096
let first = (0..<n).map { expected(value(buffer: 0, index: $0)) }
let second = (0..<n).map { expected(value(buffer: 1, index: $0)) }

row("M1 a hole in the stamps is fed as zeros and later sound stays at its stamp",
    inputs: [(0, n, 0), (1, n, 4200)], start: 0,
    want: first + [Int32](repeating: 0, count: 104) + second,
    note: "frames 4096..4199 zero, frame 4200 buffer 2's first sample")
row("M2 an overlap's covered head is cut: nothing doubled, the length the union",
    inputs: [(0, n, 0), (1, n, 3996)], start: 0,
    want: first + Array(second[100...]),
    note: "buffer 2's frame 100 at output 4096, 8,092 frames")
row("M3 a late first buffer: the stream starts at its frame and sample k sits at 480 + k",
    inputs: [(0, n, 480), (1, n, 480 + n)], start: 480,
    want: first + second,
    note: "first stamp 480 / 48 000 s")

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.prettyPrinted])
FileHandle.standardOutput.write(answer)
