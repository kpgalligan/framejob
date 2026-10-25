// speech_cache_probe.swift — issue #351's two fixes, against app/Sources.
//
// S1–S9: `loadSpeech` admits a `.bin` only under a marker of the current
// `speechVersion` and only when it is whole Float32s; `speechIsCurrent` asks
// `loadSpeech`, so a refused file is made again. W1–W3: `writeSpeech` writes
// nothing for a nil stamp, removes the `.bin` when its marker will not write,
// and replaces a refused pair with a whole one. A1–A3: `AudioRateCopy.append`
// (the transcription extract's wait since #351) leaves its wait when the
// writer stops writing and when `cancelled` answers true, where the extract's
// old `while !input.isReadyForMoreMediaData` loop would spin.
//
// Arguments: the authored 16 kHz mono WAV, a scratch folder.
import AVFoundation
import CoreMedia
import Foundation

var passed = 0
var failed = 0
func check(_ name: String, _ good: Bool, _ detail: String = "") {
    if good { passed += 1; print("  ok   \(name)") }
    else { failed += 1; print("  FAIL \(name) \(detail)") }
}

let wav = URL(fileURLWithPath: CommandLine.arguments[1])
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let manager = FileManager.default

func folder(_ name: String) -> URL {
    let url = scratch.appendingPathComponent(name, isDirectory: true)
    try? manager.removeItem(at: url)
    try? manager.createDirectory(
        at: url.appendingPathComponent("speech", isDirectory: true),
        withIntermediateDirectories: true)
    return url
}

func floats(_ values: [Float]) -> Data { values.withUnsafeBufferPointer { Data(buffer: $0) } }

func encoded<S: Encodable>(_ value: S) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try! encoder.encode(value)
}

let duration: Ticks = ReelTime.perSecond
let media = MediaSnapshot(
    id: 5, path: wav.path, kind: .audio, duration: duration, hasVideo: false, hasAudio: true)
guard let stamp = MediaImporter.CacheStamp.stamp(for: media, url: wav) else {
    print("  FAIL the fixture stamps")
    exit(1)
}
let current = MediaImporter.SpeechStamp(stamp)
let values: [Float] = [0.25, 0.5, 0.75]

/// One cache folder holding `bin` (when given) and `marker` (when given).
func cache(_ name: String, bin: Data?, marker: Data?) -> URL {
    let dir = folder(name)
    if let bin { try! bin.write(to: MediaImporter.speechURL(for: media.id, in: dir)) }
    if let marker { try! marker.write(to: MediaImporter.speechMarkerURL(for: media.id, in: dir)) }
    return dir
}

func load(_ dir: URL) -> [Float]? { MediaImporter.loadSpeech(for: media.id, in: dir) }

// ---- S: the reader's accept/reject rules ---------------------------------
let whole = cache("whole", bin: floats(values), marker: encoded(current))
check("S1 a current-version marker and whole Float32s load", load(whole) == values,
      "\(String(describing: load(whole)))")

let unmarked = cache("unmarked", bin: floats(values), marker: nil)
check("S2 a .bin with no marker is refused", load(unmarked) == nil)

var oldJSON = try! JSONSerialization.jsonObject(with: encoded(current)) as! [String: Any]
oldJSON["version"] = MediaImporter.speechVersion - 1
let old = cache(
    "old", bin: floats(values),
    marker: try! JSONSerialization.data(withJSONObject: oldJSON, options: [.sortedKeys]))
check("S3 a marker of an older speechVersion is refused", load(old) == nil)

let garbled = cache("garbled", bin: floats(values), marker: Data("{\"not\":1}".utf8))
check("S4 a marker that does not decode is refused", load(garbled) == nil)

let ragged = cache("ragged", bin: floats(values) + Data([0, 0]), marker: encoded(current))
check("S5 a .bin that is not whole Float32s (14 bytes) is refused", load(ragged) == nil)

let empty = cache("empty", bin: Data(), marker: encoded(current))
check("S6 an empty .bin is refused", load(empty) == nil)

let missing = cache("missing", bin: nil, marker: encoded(current))
check("S7 a marker with no .bin is refused", load(missing) == nil)

check("S8 speechIsCurrent: a matching marker and an accepted .bin",
      MediaImporter.speechIsCurrent(for: media, stamp: stamp, in: whole))
check("S9 speechIsCurrent is false for a refused .bin (made again) and for a nil stamp",
      !MediaImporter.speechIsCurrent(for: media, stamp: stamp, in: ragged)
          && !MediaImporter.speechIsCurrent(for: media, stamp: nil, in: whole))

// ---- W: the writer's certification ---------------------------------------
let asset = AVURLAsset(url: wav)
guard let track = asset.tracks(withMediaType: .audio).first else {
    print("  FAIL the fixture has an audio track")
    exit(1)
}

func exists(_ url: URL) -> Bool { manager.fileExists(atPath: url.path) }

let nilStamp = folder("nil-stamp")
MediaImporter.writeSpeech(for: media, asset: asset, track: track, stamp: nil, into: nilStamp)
check("W1 a nil stamp writes neither .bin nor marker",
      !exists(MediaImporter.speechURL(for: media.id, in: nilStamp))
          && !exists(MediaImporter.speechMarkerURL(for: media.id, in: nilStamp)))

check("W0 the Silero model is beside the probe", SileroVAD.isAvailable)

// A FOLDER where the marker goes: `writeStamp`'s atomic write fails.
let blocked = folder("blocked")
try! manager.createDirectory(
    at: MediaImporter.speechMarkerURL(for: media.id, in: blocked),
    withIntermediateDirectories: true)
MediaImporter.writeSpeech(for: media, asset: asset, track: track, stamp: stamp, into: blocked)
check("W2 a marker that will not write takes its .bin with it",
      !exists(MediaImporter.speechURL(for: media.id, in: blocked)) && load(blocked) == nil)

let rebuilt = cache("rebuilt", bin: floats(values) + Data([0, 0]), marker: encoded(current))
MediaImporter.writeSpeech(for: media, asset: asset, track: track, stamp: stamp, into: rebuilt)
let fresh = load(rebuilt)
check("W3 a refused pair is written again whole and loads",
      fresh?.count == MediaSpeech.chunkCount(duration: duration)
          && MediaImporter.speechIsCurrent(for: media, stamp: stamp, in: rebuilt),
      "\(fresh?.count ?? -1) values, \(MediaSpeech.chunkCount(duration: duration)) expected")

// ---- A: the shared append's wait ------------------------------------------
let pcm: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000.0,
    AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
]

/// A sample buffer of the fixture, and a started writer with one input.
func writer(_ name: String) -> (AVAssetWriter, AVAssetWriterInput, CMSampleBuffer) {
    let reader = try! AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
    reader.add(output)
    reader.startReading()
    let sample = output.copyNextSampleBuffer()!
    reader.cancelReading()
    let url = scratch.appendingPathComponent("\(name).wav")
    try? manager.removeItem(at: url)
    let writer = try! AVAssetWriter(outputURL: url, fileType: .wav)
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
    input.expectsMediaDataInRealTime = false
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
    return (writer, input, sample)
}

/// `body` on a thread of its own, bounded: nil when it is still waiting.
func bounded(_ seconds: Double, _ body: @escaping () -> String?) -> String?? {
    final class Box: @unchecked Sendable { var answer: String?? = .none }
    let box = Box()
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        box.answer = .some(body())
        done.signal()
    }
    return done.wait(timeout: .now() + seconds) == .success ? box.answer : .none
}

// A1: the writer stopped. Cancelled here; a disk-full failure is the same
// `status != .writing` with the input never ready again.
let (stopped, stoppedInput, stoppedSample) = writer("stopped")
stoppedInput.markAsFinished()
stopped.cancelWriting()
let a1Ready = stoppedInput.isReadyForMoreMediaData
let a1 = bounded(5) {
    AudioRateCopy.append(stoppedSample, to: stoppedInput, writer: stopped)
}
check("A1 a stopped writer ends the wait with a reason (the old loop: input ready \(a1Ready))",
      !a1Ready && a1 != nil && a1! != nil, "answered \(String(describing: a1))")

// A2/A3: the writer still writing, the input never ready again (finished).
// The old loop spins for ever here; `cancelled` is polled inside the wait.
let (writing, writingInput, writingSample) = writer("writing")
writingInput.markAsFinished()
let a2Status = writing.status == .writing
let a2Ready = writingInput.isReadyForMoreMediaData
final class Counter: @unchecked Sendable { var asked = 0 }
let counter = Counter()
let a2 = bounded(5) {
    AudioRateCopy.append(
        writingSample, to: writingInput, writer: writing,
        cancelled: { counter.asked += 1; return counter.asked >= 3 })
}
check("A2 Cancel reaches the wait of a writing writer whose input is never ready "
          + "(writing \(a2Status), ready \(a2Ready))",
      a2Status && !a2Ready && a2 == .some(.some("cancelled")) && counter.asked == 3,
      "answered \(String(describing: a2)), asked \(counter.asked)")
let a3 = bounded(1) { AudioRateCopy.append(writingSample, to: writingInput, writer: writing) }
check("A3 with no cancel the same wait is still waiting after 1 s (the hang A2 escapes)",
      a3 == nil, "answered \(String(describing: a3))")
writing.cancelWriting()

print("\n\(passed)/\(passed + failed) checks passed")
exit(failed == 0 ? 0 : 1)
