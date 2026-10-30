import AppKit
import AVFoundation
import CoreMedia
import Foundation

// The loudness cache's arithmetic probe (road map "audio" AP1, spec §11
// AU-10..AU-15), compiled with app/Sources through swift_build. Arguments:
// the fixtures folder, a scratch folder. Prints one "ok"/"FAIL" line per row,
// each row's name first (C1..C11), for loudness_cache_probe.py to score.

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.prohibited)

let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scratch = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

func check(_ row: String, _ name: String, _ good: Bool, _ detail: String = "") {
    print((good ? "  ok   " : "  FAIL ") + row + " " + name + (detail.isEmpty ? "" : ": " + detail))
}
func f3(_ x: Double?) -> String { x.map { String(format: "%.3f", $0) } ?? "nil" }
func ticks(_ seconds: Double) -> Ticks { Ticks((seconds * 600_000).rounded()) }

// MARK: - Decoding and the reference meter

struct PCM { let rate: Double; let channels: Int; var samples: [Float]
    var frames: Int { samples.count / channels } }

func decode(_ url: URL) -> PCM? {
    let asset = AVURLAsset(url: url)
    let box = TrackBox()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.track = (try? await asset.loadTracks(withMediaType: .audio))?.first
        done.signal()
    }
    done.wait()
    guard let track = box.track, let reader = try? AVAssetReader(asset: asset) else { return nil }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false])
    reader.add(output)
    guard reader.startReading() else { return nil }
    var samples: [Float] = []
    var rate = 0.0
    var channels = 0
    while let buffer = output.copyNextSampleBuffer() {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
            let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        rate = asbd.mSampleRate
        channels = Int(asbd.mChannelsPerFrame)
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / 4)
        _ = chunk.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                       destination: $0.baseAddress!)
        }
        samples += chunk
    }
    return reader.status == .completed ? PCM(rate: rate, channels: channels, samples: samples) : nil
}
final class TrackBox: @unchecked Sendable { var track: AVAssetTrack? }

/// `LoudnessMeter` on interleaved stereo (mono duplicated: the export's dual mono).
func meter(_ pcm: PCM, from a: Int, to b: Int, reversed: Bool = false,
           matrix: ClipLoudness.ChannelMatrix = .identity) -> LoudnessReport? {
    guard pcm.rate == 48000, let m = LoudnessMeter(sampleRate: 48000, channelCount: 2) else {
        return nil
    }
    var stereo: [Float] = []
    stereo.reserveCapacity((b - a) * 2)
    let order = reversed ? Array((a..<b).reversed()) : Array(a..<b)
    for f in order {
        let l = Double(pcm.samples[f * pcm.channels])
        let r = pcm.channels == 2 ? Double(pcm.samples[f * 2 + 1]) : l
        if pcm.channels == 2 {
            stereo.append(Float(matrix.m00 * l + matrix.m01 * r))
            stereo.append(Float(matrix.m10 * l + matrix.m11 * r))
        } else {
            stereo.append(Float(l))
            stereo.append(Float(l))
        }
    }
    stereo.withUnsafeBufferPointer { m.feed($0.baseAddress!, frames: b - a) }
    return m.finish()
}

// MARK: - The cache

func snapshot(_ url: URL, _ id: UInt32, _ duration: Ticks) -> MediaSnapshot {
    MediaSnapshot(id: id, path: url.path, kind: .audio, duration: duration,
                  hasVideo: false, hasAudio: true)
}

/// Builds the cache through the product's async pass and loads it.
func build(_ media: MediaSnapshot, _ url: URL, into dir: URL) -> (Bool, MediaLoudness?) {
    let done = DispatchSemaphore(value: 0)
    let box = ResultBox()
    Task.detached {
        box.value = await MediaImporter.loudness(
            for: media, url: url, stamp: MediaImporter.CacheStamp.stamp(for: media, url: url),
            into: dir)
        done.signal()
    }
    _ = done.wait(timeout: .now() + 120)
    return (box.value, MediaImporter.loadLoudness(for: media.id, in: dir))
}
final class ResultBox: @unchecked Sendable { var value = false }

func segment(_ media: UInt32, sourceIn: Ticks, duration: Ticks, start: Ticks = 0) -> PlanSegment {
    let json = """
        {"clip": 2, "media": \(media), "source_in": \(sourceIn), "source_duration": \(duration),
         "start": \(start), "duration": \(duration)}
        """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(PlanSegment.self, from: Data(json.utf8))
}

func props(_ json: String) -> AudioProps {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(AudioProps.self, from: Data(json.utf8))
}

func cacheDir(_ name: String) -> URL {
    let url = scratch.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Ticks for a 48 kHz frame count, exactly when it is even.
func duration(_ pcm: PCM) -> Ticks {
    Ticks((Double(pcm.frames) / pcm.rate * 600_000).rounded(.up))
}

/// S4's ten named windows, seconds (its eleventh is the whole file).
let windows: [(Double, Double)] = [
    (2.282, 10.475), (2.882, 14.596), (10.381, 14.844), (5.698, 28.893), (2.326, 22.159),
    (4.290, 19.097), (2.497, 9.296), (20.958, 28.675), (7.322, 28.558), (1.877, 22.487)]

let rodeURL = fixtures.appendingPathComponent("rode.m4a")
let stereoURL = fixtures.appendingPathComponent("stereo.wav")
guard let rode = decode(rodeURL), let stereoPCM = decode(stereoURL) else {
    check("C0", "fixtures decode", false)
    exit(1)
}
let rodeMedia = snapshot(rodeURL, 1, duration(rode))
let stereoMedia = snapshot(stereoURL, 2, duration(stereoPCM))
let monoDir = cacheDir("mono")
let stereoDir = cacheDir("stereo")
let (monoBuilt, monoCacheOpt) = build(rodeMedia, rodeURL, into: monoDir)
let (stereoBuilt, stereoCacheOpt) = build(stereoMedia, stereoURL, into: stereoDir)

// C1: the files.
do {
    let monoMarker = MediaImporter.readLoudnessStamp(
        at: MediaImporter.loudnessMarkerURL(for: 1, in: monoDir))
    let stereoMarker = MediaImporter.readLoudnessStamp(
        at: MediaImporter.loudnessMarkerURL(for: 2, in: stereoDir))
    let monoBytes = (try? Data(contentsOf: MediaImporter.loudnessURL(for: 1, in: monoDir)))?.count
    let stereoBytes = (try? Data(contentsOf: MediaImporter.loudnessURL(for: 2, in: stereoDir)))?.count
    let monoCount = Int((Double(rodeMedia.duration) / 6000).rounded(.up))
    let stereoCount = Int((Double(stereoMedia.duration) / 6000).rounded(.up))
    check("C1", "mono cache published, width 2, ⌈duration·100⌉ records, marker v1 at 100/s ×4",
          monoBuilt && monoCacheOpt?.width == 2 && monoCacheOpt?.count == monoCount
            && monoBytes == monoCount * 8 && monoMarker?.channels == 1
            && monoMarker?.sampleRate == 48000 && monoMarker?.version == 1
            && monoMarker?.blocksPerSecond == 100 && monoMarker?.oversample == 4,
          "built \(monoBuilt), count \(monoCacheOpt?.count ?? -1)/\(monoCount), "
            + "bytes \(monoBytes ?? -1), marker \(String(describing: monoMarker))")
    check("C1", "stereo cache published, width 5, 20 bytes a record",
          stereoBuilt && stereoCacheOpt?.width == 5 && stereoCacheOpt?.count == stereoCount
            && stereoBytes == stereoCount * 20 && stereoMarker?.channels == 2,
          "built \(stereoBuilt), count \(stereoCacheOpt?.count ?? -1)/\(stereoCount), "
            + "bytes \(stereoBytes ?? -1)")
}
guard let monoCache = monoCacheOpt, let stereoCache = stereoCacheOpt else { exit(1) }

func cacheReading(_ cache: MediaLoudness, _ media: UInt32, _ a: Double, _ b: Double,
                  pivot: Ticks? = nil, matrix: ClipLoudness.ChannelMatrix = .identity)
    -> ClipLoudness.Reading {
    let seg = segment(media, sourceIn: ticks(a), duration: ticks(b) - ticks(a))
    return ClipLoudness.reading(cache, segments: [seg], pivots: [pivot], matrix: matrix)
}
func frame(_ s: Double) -> Int { Int((s * 48000).rounded()) }

// C2: the whole file against the meter, as dual mono.
do {
    let whole = Double(rode.frames) / 48000
    let read = cacheReading(monoCache, 1, 0, whole)
    let ref = meter(rode, from: 0, to: rode.frames)
    let tp = 20 * log10(read.truePeak)
    let dl = (read.lufs ?? .nan) - (ref?.integratedLUFS ?? .nan)
    check("C2", "whole file within 0.1 LU and 0.01 dB TP of LoudnessMeter as dual mono",
          abs(dl) <= 0.1 && abs(tp - (ref?.truePeakDBTP ?? .nan)) <= 0.01,
          "cache \(f3(read.lufs)) LUFS \(f3(tp)) dBTP, meter \(f3(ref?.integratedLUFS)) LUFS "
            + "\(f3(ref?.truePeakDBTP)) dBTP")
}

// C3: S4's ten windows forward.
do {
    var worst = 0.0
    var detail: [String] = []
    for (a, b) in windows {
        let read = cacheReading(monoCache, 1, a, b)
        let ref = meter(rode, from: frame(a), to: frame(b))?.integratedLUFS
        let d = (read.lufs ?? .nan) - (ref ?? .nan)
        worst = d.isNaN ? .infinity : max(worst, abs(d))
        detail.append("\(a)–\(b) \(f3(read.lufs))/\(f3(ref))")
    }
    check("C3", "ten windows forward within 0.1 LU of the meter on each window",
          worst <= 0.1, "worst \(f3(worst)); " + detail.joined(separator: ", "))
}

// C4: reversed windows against the meter on reversed samples.
do {
    let pivot = rodeMedia.duration
    var worst = 0.0
    var detail: [String] = []
    for (a, b) in windows {
        let read = cacheReading(monoCache, 1, a, b, pivot: pivot)
        let ref = meter(rode, from: rode.frames - frame(b), to: rode.frames - frame(a),
                        reversed: true)?.integratedLUFS
        let d = (read.lufs ?? .nan) - (ref ?? .nan)
        worst = d.isNaN ? .infinity : max(worst, abs(d))
        detail.append("\(a)–\(b) \(f3(read.lufs))/\(f3(ref))")
    }
    check("C4", "ten reversed windows within 0.1 LU of the meter on reversed samples",
          worst <= 0.1, "worst \(f3(worst)); " + detail.joined(separator: ", "))
}

// C5: stereo identity, mono fold, hard pan.
do {
    let fold = ClipLoudness.ChannelMatrix(props(#"{"mono": true}"#))
    let left = ClipLoudness.ChannelMatrix(props(#"{"pan": -1}"#))
    check("C5", "the matrices: fold ½ everywhere, hard left √2 on L only",
          fold == ClipLoudness.ChannelMatrix(m00: 0.5, m01: 0.5, m10: 0.5, m11: 0.5)
            && abs(left.m00 - 2.0.squareRoot()) < 1e-6 && abs(left.m11) < 1e-6
            && left.m01 == 0 && left.m10 == 0,
          "\(fold) \(left)")
    let whole = Double(stereoPCM.frames) / 48000
    for (name, matrix) in [("identity", ClipLoudness.ChannelMatrix.identity), ("mono fold", fold),
                           ("hard left", left)] {
        var worst = 0.0
        var detail: [String] = []
        for (a, b) in [(0, whole), (2.282, 10.475), (5.698, 28.893), (20.958, 28.675)] {
            let read = cacheReading(stereoCache, 2, a, b, matrix: matrix)
            let ref = meter(stereoPCM, from: frame(a), to: min(frame(b), stereoPCM.frames),
                            matrix: matrix)?.integratedLUFS
            let d = (read.lufs ?? .nan) - (ref ?? .nan)
            worst = d.isNaN ? .infinity : max(worst, abs(d))
            detail.append("\(f3(read.lufs))/\(f3(ref))")
        }
        check("C5", "stereo \(name) within 0.1 LU of the meter on transformed samples",
              worst <= 0.1, "worst \(f3(worst)); " + detail.joined(separator: ", "))
    }
}

// C6: 44.1 kHz fixtures against the meter on ffmpeg's 48 kHz copies.
for stem in ["rode44", "tone44"] {
    let url = fixtures.appendingPathComponent(stem + ".wav")
    guard let native = decode(url), let copy = decode(fixtures.appendingPathComponent(stem + "to48.wav"))
    else { check("C6", "\(stem) fixtures decode", false); continue }
    let media = snapshot(url, 3, duration(native))
    let (_, cache) = build(media, url, into: cacheDir(stem))
    let read = cache.map { cacheReading($0, 3, 0, Double(native.frames) / native.rate) }
    let ref = meter(copy, from: 0, to: copy.frames)?.integratedLUFS
    let d = (read?.lufs ?? .nan) - (ref ?? .nan)
    check("C6", "\(stem) at 44.1 kHz within 0.1 LU of the meter on its 48 kHz copy",
          native.rate == 44100 && abs(d) <= 0.1,
          "rate \(native.rate), cache \(f3(read?.lufs)), meter \(f3(ref))")
}

// C7: under 0.4 s, and every block under −70.
do {
    let short = cacheReading(monoCache, 1, 21.0, 21.39)
    let quietURL = fixtures.appendingPathComponent("quiet48.wav")
    let quiet = decode(quietURL)
    let media = snapshot(quietURL, 4, quiet.map(duration) ?? 0)
    let (_, cache) = build(media, quietURL, into: cacheDir("quiet"))
    let read = cache.map { cacheReading($0, 4, 0, 5) }
    let longer = cacheReading(monoCache, 1, 21.0, 21.4)
    let ref = meter(rode, from: frame(21.0), to: frame(21.4))?.integratedLUFS
    check("C7", "0.39 s played reads nil, 0.40 s reads what the meter reads",
          short.lufs == nil && longer.lufs != nil && ref != nil,
          "\(f3(short.lufs)), \(f3(longer.lufs)), meter \(f3(ref))")
    check("C7", "a −85 dBFS tone reads nil (gated out)", read != nil && read?.lufs == nil,
          "\(String(describing: read))")
}

// C8: the plan (AU-24): a volume alone, the limiter turned on through the
// model, a clip's own limiter kept, the ×32 cap, a turn-down, the fallback.
do {
    /// One second of 10 ms steps at `lufs`, each step's peak `quiet`, every
    /// `every`th step `loud` (the reading's true peak).
    func r(_ clip: UInt32, _ lufs: Double, quiet: Double, loud: Double, every: Int = 50,
           limiter: LimiterProps? = nil) -> AudioNormalize.LoudnessReading {
        let steps = [Double](repeating: pow(10, (lufs - LoudnessMeter.offset) / 10), count: 100)
        let peaks = (0..<100).map { $0 % every == every - 1 ? loud : quiet }
        return AudioNormalize.LoudnessReading(
            clip: clip, media: 9, lufs: ClipLoudness.integrated(steps) ?? .nan,
            truePeak: max(quiet, loud), steps: steps, stepPeaks: peaks, limiter: limiter)
    }
    let input = AudioNormalize.LoudnessInput(readings: [
        r(1, -30, quiet: 0.1, loud: 0.1), r(2, -30, quiet: 0.05, loud: 0.5),
        r(3, -50, quiet: 0.001, loud: 0.001), r(4, -30, quiet: 0.5, loud: 0.5, every: 1),
        r(5, -10, quiet: 0.1, loud: 0.1),
        r(6, -30, quiet: 0.1, loud: 0.1, limiter: LimiterProps(ceilingDb: -3, release: 30_000)),
        r(7, -30, quiet: 0.1, loud: 0.1, limiter: LimiterProps(ceilingDb: 0, release: 30_000)),
    ], problems: [])
    let plan = AudioNormalize.plan(input, targetLUFS: -16)
    let rows = plan.normalized
    func near(_ x: Double, _ y: Double, _ e: Double = 1e-9) -> Bool { abs(x - y) < e }
    func patch(_ index: Int) -> [String: Any] {
        plan.ops[index].args["patch"] as? [String: Any] ?? [:]
    }
    check("C8", "a peak that fits: volume 10^(14/20) alone, no limiter, −16 LUFS",
          near(rows[0].volume, pow(10, 14.0 / 20)) && rows[0].limit == nil
            && rows[0].limiter == nil && near(rows[0].resultLUFS, -16)
            && patch(0).keys.sorted() == ["volume"], "\(rows[0]) \(patch(0))")
    check("C8", "a peak past −1 dBTP: the default limiter on, the model's gain reaches −16 "
            + "within 0.001 LU, the result's peak at the ceiling",
          rows[1].limiter == LimiterProps() && rows[1].limit == nil
            && rows[1].volume > pow(10, 14.0 / 20) && near(rows[1].resultLUFS, -16, 0.001)
            && near(rows[1].resultTruePeakDBTP, -1, 1e-9)
            && patch(1)["limiter"] != nil && patch(1)["volume"] != nil,
          "\(rows[1]) \(patch(1))")
    check("C8", "the ×32 cap: volume 32, limited_by max_gain, no limiter",
          rows[2].volume == 32 && rows[2].limit == .maxGain && rows[2].limiter == nil,
          "\(rows[2])")
    check("C8", "every step past the ceiling: the limiter on, ×32, limited_by max_gain",
          rows[3].volume == 32 && rows[3].limit == .maxGain && rows[3].limiter != nil
            && rows[3].resultLUFS < -16, "\(rows[3])")
    check("C8", "a loud clip is turned down", near(rows[4].volume, pow(10, -6.0 / 20))
            && rows[4].limit == nil && rows[4].limiter == nil, "\(rows[4])")
    check("C8", "a clip's own limiter is kept (−3 stays, 30,000 ticks) and written with the "
            + "volume, which is the unlimited gain when nothing is limited",
          rows[5].limiter == LimiterProps(ceilingDb: -3, release: 30_000)
            && near(rows[5].volume, pow(10, 14.0 / 20)) && patch(5)["limiter"] != nil,
          "\(rows[5])")
    check("C8", "a clip's own ceiling above −1 dBTP is lowered to −1",
          rows[6].limiter == LimiterProps(ceilingDb: -1, release: 30_000), "\(rows[6])")
    let fallback = AudioNormalize.plan(input, targetLUFS: .nan)
    check("C8", "a non-finite target runs and reports −16", fallback.targetLUFS == -16
            && near(fallback.normalized[0].volume, rows[0].volume), "\(fallback.targetLUFS)")
}

// C9: a stale marker reads absent.
do {
    let dir = cacheDir("stale")
    let bin = MediaImporter.loudnessURL(for: 1, in: dir)
    try? FileManager.default.createDirectory(
        at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.copyItem(at: MediaImporter.loudnessURL(for: 1, in: monoDir), to: bin)
    let good = MediaImporter.readLoudnessStamp(at: MediaImporter.loudnessMarkerURL(for: 1, in: monoDir))!
    func write(_ version: Int, _ bps: Int) -> MediaLoudness? {
        let stamp = MediaImporter.LoudnessStamp(
            source: good.source, version: version, channels: 1, sampleRate: 48000,
            blocksPerSecond: bps, oversample: 4)
        _ = MediaImporter.writeStamp(stamp, to: MediaImporter.loudnessMarkerURL(for: 1, in: dir))
        return MediaImporter.loadLoudness(for: 1, in: dir)
    }
    let current = write(1, 100)
    let stale = write(0, 100)
    let grain = write(1, 50)
    check("C9", "version 1 loads; version 0 and 50 blocks a second read absent",
          current != nil && stale == nil && grain == nil,
          "\(current != nil) \(stale != nil) \(grain != nil)")
}

// C10, C11: the memo over a probe document.
do {
    let package = scratch.appendingPathComponent("memo.framejob", isDirectory: true)
    try? FileManager.default.removeItem(at: package)
    try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
    let project: [String: Any] = [
        "version": Int(RC_FORMAT_VERSION),
        "canvas": ["width": 320, "height": 180, "fps": [30, 1], "background": [0, 0, 0, 1],
                   "fit_new_clips": true, "timecode_frames": true],
        "media": [["id": 91, "path": rodeURL.path, "kind": "audio",
                   "duration": Int(rodeMedia.duration), "has_video": false, "has_audio": true]],
        "tracks": [["id": 1, "name": "Track 1"]],
        "clips": [["id": 2, "track": 1, "start": 0, "duration": Int(rodeMedia.duration),
                   "source": ["kind": "media", "media": 91, "in": 0], "audio": [:]]],
        "markers": [], "next_id": 300, "nests": []]
    try! JSONSerialization.data(withJSONObject: project)
        .write(to: package.appendingPathComponent("project.json"))
    let document = ProjectDocument()
    do {
        try document.read(from: package, ofType: ProjectDocument.projectTypeIdentifier)
    } catch {
        check("C10", "the probe document opens", false, "\(error)")
        exit(1)
    }
    let memo = ClipLoudness.Memo()
    let first = memo.answer(for: 2, in: document)
    let media = snapshot(rodeURL, 91, rodeMedia.duration)
    let (built, _) = build(media, rodeURL, into: document.cacheDirectory!)
    let held = memo.answer(for: 2, in: document)
    memo.invalidate()
    let after = memo.answer(for: 2, in: document)
    let whole = meter(rode, from: 0, to: rode.frames)?.integratedLUFS
    var lufs: Double?
    if case .reading(let reading) = after { lufs = reading.lufs }
    check("C10", "pending before the cache, held until invalidate, then the reading",
          first == .pending && built && held == .pending && lufs != nil
            && abs((lufs ?? .nan) - (whole ?? .nan)) <= 0.1,
          "\(first) \(held) \(after) meter \(f3(whole))")

    let reads = memo.reads
    let computed = memo.computations
    document.beginLiveEdit()
    document.updateLiveEdit(.setAudio(clips: [2], patch: AudioPatch(volume: 2)))
    let live1 = memo.answer(for: 2, in: document)
    document.updateLiveEdit(.setAudio(clips: [2], patch: AudioPatch(volume: 3, pan: 0.5)))
    let live2 = memo.answer(for: 2, in: document)
    let liveReads = memo.reads
    let liveComputed = memo.computations
    document.endLiveEdit("Volume")
    let ended = memo.answer(for: 2, in: document)
    check("C11", "through a live edit the held reading, no file read and no recompute",
          live1 == after && live2 == after && liveReads == reads && liveComputed == computed,
          "reads \(reads)→\(liveReads), computed \(computed)→\(liveComputed)")
    check("C11", "the first answer after the gesture recomputes without reading the file",
          memo.computations == computed + 1 && memo.reads == reads && ended == after,
          "reads \(memo.reads), computed \(memo.computations)")
}
