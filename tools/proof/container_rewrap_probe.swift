// tools/proof/container_rewrap_probe.swift — the WebM/Matroska rewrap
// probe's entry (issue batch B73, spec §11 #216-R).
//
// Copied to tools/proof/work/container-rewrap-probe/main.swift and compiled
// LAST with every app/Sources/*.swift except the app's main.swift (the
// harness's swiftc line), so each row runs the product's own
// `ContainerRewrap.rewrap` and reads the result back through the product's
// `MediaImporter.waitForProbe` and AVFoundation.
//
//   container-rewrap-probe <jobs.json>
//
// jobs.json is a list of {id, source, dest, free_delta?, stop_after?,
// refuse_audio_at?, inspect?, frame47?, payload?}. Prints one HOST line,
// then one ROW line per job, each a JSON object (container_rewrap_probe.py
// scores them); a rewrap that has not returned in 60 s is `"hung"`.
// `free_delta` stands in `required_bytes + free_delta` for the volume's free
// space. stdout is line-buffered so every finished row survives a kill.
//
// Issue batch B76 (spec §11 #228-P): one job of `kind: "cancel"` ({source:
// P1, p2: P2, dest: a scratch folder}) runs rows C20–C30 after the others —
// the copy's progress and Cancel through `rewrap`, `assist`, the probe's
// faces, `ProjectDocument.probeForOpening`, the Add Media door
// (`importMedia`, with `PresentCountingController` counting what reaches
// `presentError`) and the window's Cancel, which is never ordered front.
//
// Issue batch B77 (spec §11 #228-V): `inspect` also answers each track's
// media subtype, so W10 can read the copied Vorbis track as `vorb`.

import AppKit
import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

setvbuf(stdout, nil, _IOLBF, 0)

/// Counts every error presented through the document controller and shows
/// none. Made before anything reads `NSDocumentController.shared`, so it is
/// the shared one.
final class PresentCountingController: NSDocumentController {
    var presents = 0
    override func presentError(_ error: any Error) -> Bool {
        presents += 1
        return false
    }
}
let presentCounter = PresentCountingController()
let probeApp = NSApplication.shared
probeApp.setActivationPolicy(.prohibited)

final class Box<T>: @unchecked Sendable {
    var value: T?
}

func waitFor<T>(_ seconds: Double, _ body: @escaping @Sendable () async -> T) -> T? {
    let box = Box<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached(priority: .userInitiated) {
        box.value = await body()
        done.signal()
    }
    guard done.wait(timeout: .now() + seconds) == .success else { return nil }
    return box.value
}

func emit(_ tag: String, _ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(tag + " " + String(decoding: data, as: UTF8.self))
}

func describe(_ c: ReelContainer) -> ContainerDescription? {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try? decoder.decode(ContainerDescription.self, from: Data(c.describeJSON.utf8))
}

/// The source's index as the rewrap retimes it, independently opened.
func index(_ source: URL) -> (ReelContainer, ContainerDescription, Bool)? {
    guard let c = try? ReelContainer(path: source.path), let d = describe(c) else { return nil }
    var retimed = false
    if let nominal = d.video?.nominalFps {
        retimed = c.retime(MediaImporter.rationalFrameRate(nominal))
    }
    guard let after = describe(c) else { return nil }
    return (c, after, retimed)
}

func bytes(of source: URL, _ s: RcContainerSample) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: source) else { return nil }
    defer { try? handle.close() }
    try? handle.seek(toOffset: s.offset)
    return try? handle.read(upToCount: Int(s.size))
}

func errorFacts(_ error: any Error) -> [String: Any] {
    var facts: [String: Any] = ["message": error.localizedDescription]
    switch error {
    case let e as ContainerRewrapError:
        switch e {
        case .unsupported: facts["type"] = "unsupported"
        case .noSpace: facts["type"] = "noSpace"
        case .unreadable: facts["type"] = "unreadable"
        case .failed: facts["type"] = "failed"
        case .cancelled: facts["type"] = "cancelled"
        }
        facts["invites_ffmpeg"] = e.invitesFFmpeg
    case let e as MediaImporter.ImportError:
        switch e {
        case .undecodable: facts["type"] = "undecodable"
        case .noTracks: facts["type"] = "noTracks"
        default: facts["type"] = "import"
        }
        facts["invites_ffmpeg"] = false
    case let e as CocoaError:
        facts["type"] = e.code == .userCancelled ? "userCancelled" : "cocoa"
        facts["invites_ffmpeg"] = false
    default:
        facts["type"] = "other"
        facts["invites_ffmpeg"] = false
    }
    return facts
}

/// The written movie's tracks, through AVFoundation's loading API: each
/// one's range, timescale, atoms, media subtype (B77) and sample count.
func inspect(_ url: URL) async -> [String: Any] {
    let asset = AVURLAsset(url: url)
    var facts: [String: Any] = [:]
    for (key, type) in [("video", AVMediaType.video), ("audio", AVMediaType.audio)] {
        guard let track = try? await asset.loadTracks(withMediaType: type).first else { continue }
        let range = (try? await track.load(.timeRange)) ?? .zero
        let descriptions = (try? await track.load(.formatDescriptions)) ?? []
        var entry: [String: Any] = [
            "start": range.start.seconds, "duration": range.duration.seconds,
            "timescale": Int((try? await track.load(.naturalTimeScale)) ?? 0),
        ]
        if let first = descriptions.first {
            let atoms = CMFormatDescriptionGetExtension(
                first, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                as? [String: Any]
            entry["atoms"] = (atoms?.keys).map { Array($0).sorted() } ?? []
            let code = CMFormatDescriptionGetMediaSubType(first)
            entry["subtype"] = String(
                decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
        }
        if let reader = try? AVAssetReader(asset: asset) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            var count = 0
            if reader.startReading() {
                while let sample = output.copyNextSampleBuffer() {
                    count += max(CMSampleBufferGetNumSamples(sample), 0) > 0 ? 1 : 0
                }
            }
            entry["samples"] = count
        }
        facts[key] = entry
    }
    return facts
}

/// The exact-time frame request at `time`: the time the generator answers.
func exactFrame(_ url: URL, _ time: CMTime) -> Double? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var actual = CMTime.zero
    guard (try? generator.copyCGImage(at: time, actualTime: &actual)) != nil else { return nil }
    return actual.seconds
}

/// A passthrough buffer split into its samples: each one's time and bytes.
/// An audio buffer carries many packets, timed from its packet
/// descriptions; a video one is split by its size and timing arrays.
func split(_ sample: CMSampleBuffer) -> [(CMTime, Data)] {
    guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
    var all = Data(count: CMBlockBufferGetDataLength(block))
    _ = all.withUnsafeMutableBytes {
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count,
                                   destination: $0.baseAddress!)
    }
    let start = CMSampleBufferGetPresentationTimeStamp(sample)
    var packets: UnsafePointer<AudioStreamPacketDescription>?
    var packetBytes = 0
    if CMSampleBufferGetAudioStreamPacketDescriptionsPtr(
        sample, packetDescriptionsPointerOut: &packets, sizeOut: &packetBytes)
        == noErr, let packets, packetBytes > 0,
        let format = CMSampleBufferGetFormatDescription(sample),
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
    {
        var out: [(CMTime, Data)] = []
        var t = start
        for i in 0..<(packetBytes / MemoryLayout<AudioStreamPacketDescription>.stride) {
            let d = packets[i]
            let from = Int(d.mStartOffset)
            out.append((t, all.subdata(in: from..<(from + Int(d.mDataByteSize)))))
            let frames = d.mVariableFramesInPacket != 0 ? d.mVariableFramesInPacket
                : asbd.mFramesPerPacket
            t = t + CMTime(value: Int64(frames), timescale: CMTimeScale(asbd.mSampleRate))
        }
        return out
    }
    let n = CMSampleBufferGetNumSamples(sample)
    guard n > 1 else { return [(start, all)] }
    var sizes = [Int](repeating: 0, count: n)
    var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: n)
    var got = 0
    CMSampleBufferGetSampleSizeArray(sample, entryCount: n, arrayToFill: &sizes,
                                     entriesNeededOut: &got)
    CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: n, arrayToFill: &timings,
                                           entriesNeededOut: &got)
    var out: [(CMTime, Data)] = []
    var from = 0
    for i in 0..<n {
        out.append((timings[i].presentationTimeStamp, all.subdata(in: from..<(from + sizes[i]))))
        from += sizes[i]
    }
    return out
}

/// The written movie's passthrough sample of `type` whose MOVIE time is
/// `wanted` (exactly, for video) or nearest it (audio): its time and bytes.
/// A passthrough read answers MEDIA times; the track's edit maps them onto
/// the movie's (the writer shifts a B-frame track's media one frame later so
/// its decode times start at 0, and puts AAC's 2112 priming samples before
/// an edit), so each time is moved by the first edit's offset.
func writtenSample(_ url: URL, _ type: AVMediaType, _ wanted: CMTime, exact: Bool)
    async -> (CMTime, Data)?
{
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: type).first,
        let reader = try? AVAssetReader(asset: asset)
    else { return nil }
    let edit = ((try? await track.load(.segments)) ?? []).first { !$0.isEmpty }
    let offset = edit.map { $0.timeMapping.source.start - $0.timeMapping.target.start } ?? .zero
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else { return nil }
    var best: (CMTime, Data, Double)?
    while let buffer = output.copyNextSampleBuffer() {
        for (media, data) in split(buffer) {
            let pts = media - offset
            let distance = abs((pts - wanted).seconds)
            if exact ? pts != wanted : (best.map { distance >= $0.2 } ?? false) { continue }
            best = (pts, data, distance)
        }
    }
    reader.cancelReading()
    return best.map { ($0.0, $0.1) }
}

/// Every passthrough sample of the written movie's `type` track, in order.
func writtenPackets(_ url: URL, _ type: AVMediaType) async -> [Data]? {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: type).first,
        let reader = try? AVAssetReader(asset: asset)
    else { return nil }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    guard reader.startReading() else { return nil }
    var out: [Data] = []
    while let buffer = output.copyNextSampleBuffer() { out += split(buffer).map { $0.1 } }
    return out
}

/// When the decoded sound first passes 0.3 (an impulse), in movie seconds.
func decodedClick(_ url: URL) async -> Double? {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
        let reader = try? AVAssetReader(asset: asset)
    else { return nil }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: 48000,
    ])
    reader.add(output)
    guard reader.startReading() else { return nil }
    while let buffer = output.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let n = CMBlockBufferGetDataLength(block) / 4
        var samples = [Float](repeating: 0, count: n)
        _ = samples.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * 4,
                                       destination: $0.baseAddress!)
        }
        if let k = samples.firstIndex(where: { abs($0) > 0.3 }) {
            reader.cancelReading()
            return CMSampleBufferGetPresentationTimeStamp(buffer).seconds + Double(k) / 48000
        }
    }
    return nil
}

DecoderSupport.enable()
let version = ProcessInfo.processInfo.operatingSystemVersion
emit("HOST", [
    "macos": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
    "hw_av1": VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
])

let jobsData = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let jobs = try! JSONSerialization.jsonObject(with: jobsData) as! [[String: Any]]

for job in jobs where job["kind"] == nil {
    let source = URL(fileURLWithPath: job["source"] as! String)
    let dest = URL(fileURLWithPath: job["dest"] as! String)
    var row: [String: Any] = ["id": job["id"] as! String]
    let indexed = index(source)
    if let (_, d, retimed) = indexed {
        row["retimed"] = retimed
        row["required"] = d.requiredBytes
        row["index_video_samples"] = d.video?.samples ?? 0
    } else {
        row["retimed"] = NSNull()
    }
    var freeBytes: Int64?
    if let delta = job["free_delta"] as? Int, let required = indexed?.1.requiredBytes {
        freeBytes = Int64(required) + Int64(delta)
        let folder = dest.deletingLastPathComponent()
        let values = try? folder.resourceValues(forKeys: [.volumeLocalizedNameKey])
        row["volume"] = values?.volumeLocalizedName ?? NSNull()
        row["need_text"] = ByteCountFormatter.string(
            fromByteCount: Int64(required), countStyle: .file)
        row["free_text"] = ByteCountFormatter.string(
            fromByteCount: freeBytes ?? 0, countStyle: .file)
    }
    // On its own thread, bounded: a copy that never returns is a row
    // ("hung"), not a probe that never finishes.
    let outcome = Box<Result<Void, any Error>>()
    let returned = DispatchSemaphore(value: 0)
    let (free, stopAfter) = (freeBytes, job["stop_after"] as? Int)
    let refuseAudioAt = job["refuse_audio_at"] as? Int
    Thread.detachNewThread {
        outcome.value = Result {
            try ContainerRewrap.rewrap(
                source, to: dest, freeBytes: free, stopAfter: stopAfter,
                refuseAudioAt: refuseAudioAt)
        }
        returned.signal()
    }
    if returned.wait(timeout: .now() + 60) == .timedOut {
        row["rewrap"] = "hung"
    } else if case .failure(let error) = outcome.value {
        row["rewrap"] = "error"
        row["error"] = errorFacts(error)
    } else {
        row["rewrap"] = "ok"
    }
    let manager = FileManager.default
    row["dest_exists"] = manager.fileExists(atPath: dest.path)
    let partial = dest.deletingPathExtension().appendingPathExtension("partial.mov")
    row["partial_exists"] = manager.fileExists(atPath: partial.path)
    row["listing"] = (try? manager.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path))?
        .sorted() ?? []
    if row["rewrap"] as? String == "ok", job["inspect"] as? Bool == true {
        do {
            let m = try MediaImporter.waitForProbe(dest)
            row["probe"] = [
                "kind": m.kind.rawValue, "width": m.width, "height": m.height,
                "fps": [m.fps.num, m.fps.den], "has_video": m.hasVideo,
                "has_audio": m.hasAudio, "duration_ticks": Int(m.duration),
            ] as [String: Any]
        } catch {
            row["probe"] = ["error": error.localizedDescription]
        }
        row["tracks"] = waitFor(60) { await inspect(dest) } ?? NSNull()
    }
    if row["rewrap"] as? String == "ok", job["click"] as? Bool == true {
        let heard = waitFor(60) { await decodedClick(dest) } ?? nil
        row["click"] = heard.map { $0 as Any } ?? NSNull()
    }
    if row["rewrap"] as? String == "ok", job["frame47"] as? Bool == true,
        let (c, d, _) = indexed, let video = d.video
    {
        // Frame 47's own time, from the index's grid.
        let s47 = (0..<c.count(ReelContainer.video)).compactMap {
            c.sample(ReelContainer.video, at: $0)
        }.sorted { $0.pts < $1.pts }
        if s47.count > 47 {
            let wanted = CMTime(value: s47[47].pts, timescale: CMTimeScale(video.timescale))
            row["frame47_wanted"] = wanted.seconds
            row["frame47_actual"] = exactFrame(dest, wanted) ?? NSNull()
        }
    }
    if row["rewrap"] as? String == "ok", job["payload"] as? Bool == true,
        let (c, d, _) = indexed, let video = d.video, let audio = d.audio
    {
        var payload: [String: Any] = [:]
        let vs = (0..<c.count(ReelContainer.video)).compactMap {
            c.sample(ReelContainer.video, at: $0)
        }.sorted { $0.pts < $1.pts }
        if vs.count > 47 {
            let entry = vs[47]
            let wanted = CMTime(value: entry.pts, timescale: CMTimeScale(video.timescale))
            let written = waitFor(60) { await writtenSample(dest, .video, wanted, exact: true) }
            if let found = written ?? nil {
                payload["video_found"] = true
                payload["video_equal"] = found.1 == bytes(of: source, entry)
                payload["video_size"] = found.1.count
                payload["video_index_size"] = Int(entry.size)
                let twin = vs.first {
                    Int($0.size) == found.1.count && bytes(of: source, $0) == found.1
                }
                payload["video_match_time"] = twin.map {
                    Double($0.pts) / Double(video.timescale)
                } ?? NSNull()
            } else {
                payload["video_found"] = false
            }
        }
        // The whole audio track in order: the written packets, less the
        // copies of its first packet the writer puts before an AAC track as
        // priming, against the index's entries.
        let sourcePackets = (0..<c.count(ReelContainer.audio)).compactMap {
            c.sample(ReelContainer.audio, at: $0).flatMap { bytes(of: source, $0) }
        }
        if let written = waitFor(60, { await writtenPackets(dest, .audio) }) ?? nil,
            let first = sourcePackets.first
        {
            let lead = written.prefix { $0 == first }.count
            payload["audio_prepended"] = max(lead - 1, 0)
            payload["audio_written"] = written.count
            payload["audio_source"] = sourcePackets.count
            payload["audio_sequence_equal"] =
                lead >= 1 && Array(written.dropFirst(lead - 1)) == sourcePackets
        }
        let one = CMTime(value: 1, timescale: 1)
        let written = waitFor(60) { await writtenSample(dest, .audio, one, exact: false) }
        if let found = written ?? nil {
            let scale = Double(audio.timescale)
            let entries = (0..<c.count(ReelContainer.audio)).compactMap {
                c.sample(ReelContainer.audio, at: $0)
            }
            let nearest = entries.min {
                abs(Double($0.pts) / scale - found.0.seconds)
                    < abs(Double($1.pts) / scale - found.0.seconds)
            }
            payload["audio_found"] = true
            payload["audio_time"] = found.0.seconds
            payload["audio_index_time"] = nearest.map { Double($0.pts) / scale } ?? NSNull()
            payload["audio_equal"] = nearest.map { found.1 == bytes(of: source, $0) } ?? false
            let twin = entries.first {
                Int($0.size) == found.1.count && bytes(of: source, $0) == found.1
            }
            payload["audio_match_time"] = twin.map { Double($0.pts) / scale } ?? NSNull()
        } else {
            payload["audio_found"] = false
        }
        row["payload"] = payload
    }
    emit("ROW", row)
}

// MARK: - B76: the copy's progress and Cancel (C20–C30)

/// `body` on its own thread, bounded: nil when it has not returned.
func offMain<T>(_ seconds: Double = 60, _ body: @escaping () -> T) -> T? {
    let box = Box<T>()
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        box.value = body()
        done.signal()
    }
    guard done.wait(timeout: .now() + seconds) == .success else { return nil }
    return box.value
}

/// A watch that records each call and cancels at 30 %.
final class WatchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    func cancelling(_ p: RewrapProgress) {
        lock.lock(); count += 1; lock.unlock()
        p.cancelAt = 0.3
    }
    func recording(_ p: RewrapProgress) {
        lock.lock(); count += 1; lock.unlock()
    }
}

func outcome(_ result: Result<Void, any Error>?) -> [String: Any] {
    switch result {
    case nil: return ["rewrap": "hung"]
    case .success?: return ["rewrap": "ok"]
    case .failure(let error)?: return ["rewrap": "error", "error": errorFacts(error)]
    }
}

func listing(_ folder: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted() ?? []
}

func runCancelRows(_ job: [String: Any]) {
    let manager = FileManager.default
    let p1 = URL(fileURLWithPath: job["source"] as? String ?? "")
    let p2 = URL(fileURLWithPath: job["p2"] as? String ?? "")
    let scratch = URL(fileURLWithPath: job["dest"] as? String ?? "")
    let described = index(p1)?.1
    let expected = (described?.video?.bytes ?? 0) + (described?.audio?.bytes ?? 0)
    let pumps = [described?.video?.samples ?? 0, described?.audio?.samples ?? 0]
        .filter { $0 > 0 }.count
    let copy = FFmpegRewrap.destination(for: p1)
    let copyPartial = copy?.deletingPathExtension().appendingPathExtension("partial.mov")
    func discardCopy() {
        if let copy { FFmpegRewrap.discard(copy) }
        if let copyPartial { FFmpegRewrap.discard(copyPartial) }
    }
    func copyFacts(_ row: inout [String: Any]) {
        row["copy_exists"] = copy.map { manager.fileExists(atPath: $0.path) } ?? NSNull()
        row["copy_partial_exists"] =
            copyPartial.map { manager.fileExists(atPath: $0.path) } ?? NSNull()
    }
    func folder(_ id: String) -> URL {
        let url = scratch.appendingPathComponent(id)
        try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // C20: a whole copy reports every byte, never going back.
    do {
        let dir = folder("C20")
        let dest = dir.appendingPathComponent("c20.mov")
        let p = RewrapProgress(source: p1)
        let box = Box<Result<Void, any Error>>()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            box.value = Result { try ContainerRewrap.rewrap(p1, to: dest, progress: p) }
            done.signal()
        }
        var seen: [UInt64] = []
        let deadline = Date().addingTimeInterval(60)
        var returned = false
        while Date() < deadline {
            seen.append(p.copiedBytes)
            if done.wait(timeout: .now() + .milliseconds(1)) == .success {
                returned = true
                break
            }
        }
        seen.append(p.copiedBytes)
        var row: [String: Any] = outcome(returned ? box.value : nil)
        row["id"] = "C20"
        row["monotonic"] = zip(seen, seen.dropFirst()).allSatisfy { $0 <= $1 }
        row["readings"] = seen.count
        row["copied"] = p.copiedBytes
        row["total"] = p.totalBytes
        row["expected"] = expected
        row["fraction"] = p.fraction ?? NSNull()
        row["dest_exists"] = manager.fileExists(atPath: dest.path)
        emit("ROW", row)
    }

    // C21: a Cancel at 30 % stops the copy and leaves nothing.
    do {
        let dir = folder("C21")
        let dest = dir.appendingPathComponent("c21.mov")
        let p = RewrapProgress(source: p1)
        p.cancelAt = 0.3
        var row = outcome(offMain { Result { try ContainerRewrap.rewrap(p1, to: dest, progress: p) } })
        row["id"] = "C21"
        row["fraction"] = p.fraction ?? NSNull()
        row["adds_after_cancel"] = p.addsAfterCancel
        row["pumps"] = pumps
        row["dest_exists"] = manager.fileExists(atPath: dest.path)
        row["partial_exists"] = manager.fileExists(
            atPath: dest.deletingPathExtension().appendingPathExtension("partial.mov").path)
        row["listing"] = listing(dir)
        emit("ROW", row)
    }

    // C22: a Cancel before the copy writes nothing.
    do {
        let dir = folder("C22")
        let dest = dir.appendingPathComponent("c22.mov")
        let p = RewrapProgress(source: p1)
        p.cancel()
        var row = outcome(offMain { Result { try ContainerRewrap.rewrap(p1, to: dest, progress: p) } })
        row["id"] = "C22"
        row["listing"] = listing(dir)
        emit("ROW", row)
    }

    // C23: `assist` with a cancelling watch, then again with none.
    do {
        discardCopy()
        let log = WatchLog()
        var row = outcome(offMain {
            Result { _ = try ContainerRewrap.assist(p1, watch: log.cancelling) }
        })
        row["id"] = "C23"
        row["watch_calls"] = log.calls
        copyFacts(&row)
        let second = offMain { Result { try ContainerRewrap.assist(p1) } }
        switch second {
        case .success(let url)?:
            row["second"] = "ok"
            row["second_exists"] = manager.fileExists(atPath: url.path)
            row["second_probes"] = (try? MediaImporter.waitForProbe(url)) != nil
        case .failure(let error)?:
            row["second"] = "error"
            row["second_error"] = errorFacts(error)
        case nil:
            row["second"] = "hung"
        }
        discardCopy()
        emit("ROW", row)
    }

    // C24: the blocking face, off main, passes the watch.
    do {
        discardCopy()
        let log = WatchLog()
        var row = outcome(offMain {
            Result { _ = try MediaImporter.probeBlocking(url: p1, watch: log.cancelling) }
        })
        row["id"] = "C24"
        row["watch_calls"] = log.calls
        copyFacts(&row)
        discardCopy()
        emit("ROW", row)
    }

    // C25: inside `withoutAsking` the watch is dropped and the copy lands.
    do {
        discardCopy()
        let log = WatchLog()
        var row = outcome(offMain {
            Result {
                _ = try MediaImporter.withoutAsking {
                    try MediaImporter.probeBlocking(url: p1, watch: log.cancelling)
                }
            }
        })
        row["id"] = "C25"
        row["watch_calls"] = log.calls
        copyFacts(&row)
        discardCopy()
        emit("ROW", row)
    }

    // C26: `probeForOpening` off main answers the Cancel as userCancelled.
    do {
        discardCopy()
        let log = WatchLog()
        var row = outcome(offMain {
            Result { _ = try ProjectDocument.probeForOpening(p1, watch: log.cancelling) }
        })
        row["id"] = "C26"
        row["watch_calls"] = log.calls
        copyFacts(&row)
        discardCopy()
        emit("ROW", row)
    }

    // C27: on main, `probeForOpening` passes no watch.
    do {
        discardCopy()
        let log = WatchLog()
        var row = outcome(Result { _ = try ProjectDocument.probeForOpening(p1, watch: log.recording) })
        row["id"] = "C27"
        row["watch_calls"] = log.calls
        row["on_main"] = Thread.isMainThread
        copyFacts(&row)
        discardCopy()
        emit("ROW", row)
    }

    // C28: which errors are a Cancel, and the detail line's two forms.
    do {
        let fresh = RewrapProgress(source: p1)
        let before = RewrapProgressWindowController.detail(for: fresh)
        fresh.begin(totalBytes: 1_000_000_000)
        fresh.add(bytes: 400_000_000)
        let after = RewrapProgressWindowController.detail(for: fresh)
        emit("ROW", [
            "id": "C28",
            "cancelled": ProjectDocument.isCancelledCopy(ContainerRewrapError.cancelled(p1)),
            "failed": ProjectDocument.isCancelledCopy(
                ContainerRewrapError.failed(p1, reason: "x")),
            "no_space": ProjectDocument.isCancelledCopy(
                ContainerRewrapError.noSpace(p1, sentence: "x")),
            "unreadable": ProjectDocument.isCancelledCopy(
                MediaImporter.ImportError.unreadable(p1)),
            "detail_before": before, "detail_after": after,
        ])
    }

    // C29: the Add Media door — P1 cancelled at 30 %, a .mov beside it.
    do {
        discardCopy()
        let dir = folder("C29")
        let mov = dir.appendingPathComponent("p2.mov")
        var row: [String: Any] = ["id": "C29"]
        let made = offMain { Result { try ContainerRewrap.rewrap(p2, to: mov) } }
        if case .success? = made {
            let original = ProjectDocument.copyWatch
            ProjectDocument.copyWatch = { p in
                RewrapProgressWindowController.watch(p)
                p.cancelAt = 0.3
            }
            let presentsBefore = presentCounter.presents
            let document = ProjectDocument()
            var ids: [UInt32]?
            var maxLive = 0
            document.importMedia([p1, mov]) { ids = $0 }
            let deadline = Date().addingTimeInterval(60)
            while ids == nil, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                maxLive = max(maxLive, RewrapProgressWindowController.live.count)
            }
            let settle = Date().addingTimeInterval(3)
            while !RewrapProgressWindowController.live.isEmpty, Date() < settle {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            ProjectDocument.copyWatch = original
            let media = document.project.snapshot.media
            row["completed"] = ids != nil
            row["ids"] = (ids ?? []).map { Int($0) }
            row["media_paths"] = media.map { URL(fileURLWithPath: $0.path).lastPathComponent }
            row["presents"] = presentCounter.presents - presentsBefore
            row["max_live"] = maxLive
            row["live_after"] = RewrapProgressWindowController.live.count
            copyFacts(&row)
            document.close()
        } else {
            row["setup"] = outcome(made)
        }
        discardCopy()
        emit("ROW", row)
    }

    // C30: the window's Cancel, never ordered front.
    do {
        let p = RewrapProgress(source: p1)
        let controller = RewrapProgressWindowController(progress: p)
        controller.cancelCopy(nil)
        emit("ROW", [
            "id": "C30", "cancelled": p.isCancelled, "title": controller.cancelButton.title,
            "enabled": controller.cancelButton.isEnabled,
            "visible": controller.window?.isVisible ?? NSNull(),
            "window_title": controller.window?.title ?? NSNull(),
        ])
    }
}

if let cancelJob = jobs.first(where: { $0["kind"] as? String == "cancel" }) {
    runCancelRows(cancelJob)
}
