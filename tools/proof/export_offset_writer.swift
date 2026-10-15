// export_offset_writer — export_offset_proof.py's camera-like fixtures made by
// AVFoundation itself (issue #298 phase 1): `export_offset_writer <out.mov>
// pcm|aac <frame,frame,…>`.
//
// A 10 s QuickTime movie: 320×180, 30 fps H.264 written with
// `AVVideoAllowFrameReorderingKey: false` (so every frame's decode order is its
// presentation order), white on the listed frames and black on every other;
// and 48 kHz mono audio holding, for each listed frame F, a Hann click 1 ms
// wide, amplitude 0.5, centred at sample 1600·F (frame F's start at 30 fps):
// v(n) = 0.25·(1 + cos(π(n − c)/24)) for |n − c| < 24, quantised to s16 as the
// proof's `write_clicks_wav` does. `pcm` writes the audio as LPCM s16, `aac`
// as AAC at 128 kbps (whose priming the writer records as AVFoundation does).
//
// Exit 0 only when the file is written AND reopens with exactly one video and
// one audio track; 1 otherwise. One line out naming what was written.

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

func fail(_ text: String) -> Never {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4, arguments[2] == "pcm" || arguments[2] == "aac" else {
    fail("usage: export_offset_writer <out.mov> pcm|aac <frame,frame,…>")
}
let output = URL(fileURLWithPath: arguments[1])
let aac = arguments[2] == "aac"
let flashes = Set(arguments[3].split(separator: ",").compactMap { Int($0) })
guard !flashes.isEmpty else { fail("no frames listed") }

let rate = 48_000
let seconds = 10
let frames = 30 * seconds
let width = 320
let height = 180
let total = rate * seconds

// The audio, whole: every click at 1600·F.
var pcm = [Int16](repeating: 0, count: total)
let half = Double(rate) / 2000
for frame in flashes {
    let centre = 1600 * frame
    let reach = Int(half.rounded(.up))
    for n in max(0, centre - reach)...min(total - 1, centre + reach) {
        let d = Double(n - centre)
        guard abs(d) < half else { continue }
        let v = 0.25 * (1 + cos(Double.pi * d / half))
        pcm[n] = Int16(max(-32767, min(32767, (v * 32767).rounded())))
    }
}

try? FileManager.default.removeItem(at: output)
let writer: AVAssetWriter
do {
    writer = try AVAssetWriter(outputURL: output, fileType: .mov)
} catch {
    fail("writer: \(error)")
}
let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false],
])
video.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: video,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
let audioSettings: [String: Any] = aac
    ? [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
       AVEncoderBitRateKey: 128_000]
    : [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
       AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
       AVLinearPCMIsNonInterleaved: false]
let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
audio.expectsMediaDataInRealTime = false
guard writer.canAdd(video), writer.canAdd(audio) else { fail("the writer refused an input") }
writer.add(video)
writer.add(audio)

var asbd = AudioStreamBasicDescription(
    mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
    mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
    mBitsPerChannel: 16, mReserved: 0)
var madeFormat: CMAudioFormatDescription?
guard CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
        magicCookie: nil, extensions: nil, formatDescriptionOut: &madeFormat) == noErr,
      let audioFormat = madeFormat
else { fail("the audio format description could not be made") }

/// `count` samples from `start` as one ready LPCM sample buffer.
func audioBuffer(from start: Int, count: Int) -> CMSampleBuffer {
    let bytes = count * 2
    var made: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
            blockBufferOut: &made) == noErr,
          let block = made
    else { fail("block buffer at \(start)") }
    let copied = pcm.withUnsafeBytes { raw in
        CMBlockBufferReplaceDataBytes(
            with: raw.baseAddress!.advanced(by: start * 2), blockBuffer: block,
            offsetIntoDestination: 0, dataLength: bytes)
    }
    guard copied == noErr else { fail("block buffer copy at \(start)") }
    var sample: CMSampleBuffer?
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: audioFormat,
            sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(start),
                                                              timescale: CMTimeScale(rate)),
            packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
          let ready = sample
    else { fail("audio sample buffer at \(start)") }
    return ready
}

/// Frame `index` as a BGRA buffer, white or black.
func frameBuffer(_ index: Int) -> CVPixelBuffer {
    var made: CVPixelBuffer?
    if let pool = adaptor.pixelBufferPool {
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
    }
    if made == nil {
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made)
    }
    guard let buffer = made else { fail("pixel buffer for frame \(index)") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!
    let row = CVPixelBufferGetBytesPerRow(buffer)
    memset(base, flashes.contains(index) ? 255 : 0, row * height)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
}

guard writer.startWriting() else {
    fail("could not start: \(String(describing: writer.error))")
}
writer.startSession(atSourceTime: .zero)

let chunk = 4800
var nextFrame = 0
var nextSample = 0
let deadline = Date().addingTimeInterval(120)
while nextFrame < frames || nextSample < total {
    guard Date() < deadline else { fail("the writer took more than 120 s") }
    var moved = false
    if nextFrame < frames, video.isReadyForMoreMediaData {
        let time = CMTime(value: CMTimeValue(nextFrame), timescale: 30)
        guard adaptor.append(frameBuffer(nextFrame), withPresentationTime: time) else {
            fail("frame \(nextFrame) refused: \(String(describing: writer.error))")
        }
        nextFrame += 1
        moved = true
        if nextFrame == frames { video.markAsFinished() }
    }
    if nextSample < total, audio.isReadyForMoreMediaData {
        let count = min(chunk, total - nextSample)
        guard audio.append(audioBuffer(from: nextSample, count: count)) else {
            fail("audio at \(nextSample) refused: \(String(describing: writer.error))")
        }
        nextSample += count
        moved = true
        if nextSample == total { audio.markAsFinished() }
    }
    if !moved { usleep(1000) }
}
writer.endSession(atSourceTime: CMTime(value: CMTimeValue(seconds), timescale: 1))
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
guard finished.wait(timeout: .now() + 120) == .success, writer.status == .completed else {
    fail("the writer ended \(writer.status.rawValue): \(String(describing: writer.error))")
}

let back = AVURLAsset(url: output)
let videoTracks = back.tracks(withMediaType: .video).count
let audioTracks = back.tracks(withMediaType: .audio).count
print("\(output.lastPathComponent): \(frames) frames, \(total) samples "
    + "(\(aac ? "AAC 128 kbps" : "LPCM s16")), \(flashes.count) flashes; reopened with "
    + "\(videoTracks) video and \(audioTracks) audio track(s)")
exit(videoTracks == 1 && audioTracks == 1 ? 0 : 1)
