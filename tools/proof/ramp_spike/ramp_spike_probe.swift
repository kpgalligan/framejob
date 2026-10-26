// tools/proof/ramp_spike/ramp_spike_probe.swift — the in-process instrument
// behind `ramp_spike.py` (road map "speed-ramps", SR1; spec §11 SR-5).
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, against `libframejob_core.a`, through `swift_build.build`
// (`-D FRAMEJOB_DEV_TOOLS`), with `Blank.mp4` and a `default.metallib` of the
// app's own shader beside the binary:
//
//     ramp-spike-probe <plan|export|playback|render> <work-dir> <job.json>
//
// `job.json` is a list of `{name, project, fixture, reads, length}`: the
// project is a `project.json` (plan, export) or a `.framejob` package
// (playback), `reads` names what to read of it and `length` is the clip's
// timeline length in ticks. Per read the probe writes one file under
// `<work-dir>/runs/` and prints one stdout JSON line `{name, read, ok, path,
// error, …}`. It locates and judges nothing; the runner does.
//
//   plan     `ReelProject.from(json:)`, its `planJSON` written verbatim
//   wav      `Exporter().export` with `ReelExport.settings(_:preset: "audio_wav")`
//   prores   the same with `prores_422` (`export_offset_probe.swift`'s loop,
//            the run loop turned to a 120 s bound)
//   mix      (#334, #337) `CompositionBuilder.build` with a `RecipeSource` key,
//            as `Exporter` builds; one `AVAssetReader` over
//            `Exporter.timeRange(ReelExport.settings(_:preset: "audio_wav"), …)`
//            with an `AVAssetReaderAudioMixOutput` over every audio track and
//            the plan's mix, per the job's optional `mix_variant`: `app`
//            (`ExportWriter.decodedAudioSettings`, the default), `float`
//            (`ExportAudioGain.floatMixSettings`) or `output_varispeed` (`app`
//            with the output's `audioTimePitchAlgorithm` `.varispeed`). The
//            file is channel 0, float32 LE, in order; the line adds `variant`,
//            `chunks: [[pts_ticks, frames]…]`, `range_ticks`,
//            `composition_ticks` and `audio_track_ends: [ticks]`.
//   tap      the package opened as a `ProjectDocument` with its editor
//            (`media_less_playback_probe.swift`'s `Opened`); once the editor's
//            item is ready its `audioMix` is replaced by one whose inputs are
//            `CompositionBuilder.audioParameters(for:segments:ramps:onset:dsp:
//            nil, meter: nil)` per composition audio track, carrying this
//            probe's own `MTAudioProcessingTap` created PostEffects (the
//            job's optional `tap_flag`: `post`, the default, or `pre`, the
//            product `AudioTap`'s PreEffects, #335); each
//            buffer's channel 0 is kept, stamped with the start of
//            `MTAudioProcessingTapGetSourceAudio`'s time range (as
//            `AudioTap.swift` reads it). `playback.seek(to: 0)`, `play()`,
//            run to the clip's end + 0.5 s (bound 3 × its length), `pause()`.
//            The line adds `chunks: [[item_ticks | null, frames]…]`, `format`
//            and `calls`; the file is the kept samples, float32 LE, in order.
//   frames   in the same document: an `AVPlayerItemVideoOutput` (32BGRA) on
//            the item; for each timeline frame k `playback.seek(to: k·20 000)`,
//            the seek settled, `copyPixelBuffer(forItemTime:)` polled up to
//            1 s, and the mean luma (Rec. 709) of each bar's centre 16 × 16
//            block. The line adds `bars: [[10 lumas] | null…]`.
//
// Each job's document is closed (`document.close()`, `spin(0.5)`) before the
// next opens: never more than one open (the forty-document deadlock).
//
//   render   (SR1b, spec §11 SR-7) `job.json` is a list of `{name, source,
//            clip_ticks, source_ticks, keep_pitch, destination, lead_frames?}`;
//            per job `RampAudioRenderer.render` writes `destination` and the
//            probe prints `{name, read: "render", ok, error, path, frames,
//            channels, wall_s, bytes, latency_frames, pulled_frames,
//            lead_frames, peak_rss_bytes}` (SR1d: keep pitch on's lead, a
//            job's `lead_frames` overriding `rateLeadFrames` for SR-14's
//            sweep; `getrusage`'s `ru_maxrss`, the process's peak so far). No
//            document is opened.
import AVFoundation
import AppKit
import MediaToolbox

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}

let arguments = CommandLine.arguments
guard arguments.count == 4, ["plan", "export", "playback", "render"].contains(arguments[1]) else {
    FileHandle.standardError.write(
        Data("usage: ramp-spike-probe <plan|export|playback|render> <work-dir> <job.json>\n".utf8))
    exit(2)
}
let group = arguments[1]
let runs = URL(fileURLWithPath: arguments[2], isDirectory: true).appendingPathComponent("runs")
try? FileManager.default.createDirectory(at: runs, withIntermediateDirectories: true)

_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(group == "playback" ? .accessory : .prohibited)
// Preview Quality pinned to Full in the argument domain (volatile, never
// written), so a stored Half cannot halve the frames this probe reads.
UserDefaults.standard.setVolatileDomain(
    ["FrameJobPreviewQuality": 0], forName: UserDefaults.argumentDomain)

struct Job: Decodable {
    let name: String
    let project: String
    let fixture: String
    let reads: [String]
    let length: Int64
    /// The `mix` read's output (#334): `app`, `float` or `output_varispeed`.
    let mix_variant: String?
    /// The `tap` read's tap: `post` (nil) or `pre` (#335).
    let tap_flag: String?
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func emit(_ line: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]))
        ?? Data("{\"error\":\"unserialisable line\"}".utf8)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

/// One read: its body answers the line's extras, or throws its error.
func read(_ job: Job, _ kind: String, ext: String, _ body: (URL) throws -> [String: Any]) {
    let url = runs.appendingPathComponent("\(job.name)-\(kind).\(ext)")
    try? FileManager.default.removeItem(at: url)
    var line: [String: Any] = ["name": job.name, "read": kind, "path": url.path]
    do {
        line.merge(try body(url)) { _, new in new }
        line["ok"] = true
        line["error"] = NSNull()
    } catch {
        line["ok"] = false
        line["error"] = "\(error)"
    }
    emit(line)
}

func loadProject(_ path: String) throws -> ReelProject {
    var url = URL(fileURLWithPath: path)
    if url.pathExtension == "framejob" { url.appendPathComponent("project.json") }
    return try ReelProject.from(json: try String(contentsOf: url, encoding: .utf8))
}

func mediaURLs(_ project: ReelProject) -> [UInt32: URL] {
    var urls: [UInt32: URL] = [:]
    for item in project.snapshot.media { urls[item.id] = URL(fileURLWithPath: item.path) }
    return urls
}

// MARK: - Plan and export

func planRead(_ job: Job) {
    read(job, "plan", ext: "json") { url in
        let project = try loadProject(job.project)
        try project.planJSON.write(to: url, atomically: true, encoding: .utf8)
        return [:]
    }
}

func exportRead(_ job: Job, _ kind: String, preset: String, ext: String) {
    read(job, kind, ext: ext) { url in
        let project = try loadProject(job.project)
        let settings = try ReelExport.settings(project, preset: preset)
        let exporter = Exporter()
        var outcome: Result<URL, any Error>?
        exporter.export(
            project: project, urls: mediaURLs(project), settings: settings, to: url,
            progress: { _ in }, completion: { outcome = $0 })
        let deadline = Date().addingTimeInterval(120)
        while outcome == nil, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        switch outcome {
        case .success?:
            return [:]
        case .failure(let error)?:
            throw ProbeError("the export failed: \(error.localizedDescription)")
        case nil:
            exporter.cancel()
            throw ProbeError("the export did not end within 120 s")
        }
    }
}

// MARK: - The mix (#334, #337)

/// The plan's mix read the way the export's writer reads it, with no writer:
/// channel 0 of every buffer in order, each buffer's stamp and frame count.
func mixRead(_ job: Job) {
    let variant = job.mix_variant ?? "app"
    read(job, "mix", ext: "f32") { url in
        guard ["app", "float", "output_varispeed"].contains(variant) else {
            throw ProbeError("unknown mix_variant \(variant)")
        }
        let project = try loadProject(job.project)
        guard let plan = project.plan else { throw ProbeError("no plan") }
        let key = RecipeSource.shared.register()
        defer { RecipeSource.shared.unregister(key) }
        RecipeSource.shared.set(project, for: key)
        let built = try CompositionBuilder.build(
            plan: plan, planJSON: project.planJSON, urls: mediaURLs(project), recipeKey: key)
        let range = Exporter.timeRange(
            try ReelExport.settings(project, preset: "audio_wav"), composition: built.composition)
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ProbeError("the composition has no audio track") }
        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = range
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: variant == "float"
                ? ExportAudioGain.floatMixSettings : ExportWriter.decodedAudioSettings)
        output.audioMix = built.audioMix
        if variant == "output_varispeed" { output.audioTimePitchAlgorithm = .varispeed }
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw ProbeError("the reader refused the output") }
        reader.add(output)
        guard reader.startReading() else {
            throw ProbeError("the read did not start: \(String(describing: reader.error))")
        }
        var samples: [Float] = []
        var chunks: [Any] = []
        while let sample = output.copyNextSampleBuffer() {
            let frames = CMSampleBufferGetNumSamples(sample)
            chunks.append([
                NSNumber(value: CompositionBuilder.ticks(
                    CMSampleBufferGetPresentationTimeStamp(sample))), frames,
            ])
            guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample),
                let format = CMSampleBufferGetFormatDescription(sample),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            else { continue }
            let channels = Int(asbd.mChannelsPerFrame)
            let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
            let width = Int(asbd.mBitsPerChannel) / 8
            guard channels > 0, asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                (isFloat && width == 4) || (!isFloat && width == 2)
            else { throw ProbeError("an unexpected format: \(asbd)") }
            var bytes = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
            guard CMBlockBufferCopyDataBytes(
                block, atOffset: 0, dataLength: bytes.count, destination: &bytes)
                == kCMBlockBufferNoErr
            else { throw ProbeError("a buffer could not be copied") }
            let count = min(frames, bytes.count / (width * channels))
            bytes.withUnsafeBytes { raw in
                for i in 0..<count {
                    let offset = i * width * channels
                    samples.append(
                        isFloat
                            ? raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
                            : Float(raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                                / 32768)
                }
            }
        }
        guard reader.status == .completed else {
            throw ProbeError("the read ended \(reader.status.rawValue): "
                + "\(String(describing: reader.error))")
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url)
        return [
            "variant": variant, "chunks": chunks,
            "range_ticks": CompositionBuilder.ticks(range.duration),
            "composition_ticks": CompositionBuilder.ticks(built.composition.duration),
            "audio_track_ends": tracks.map { CompositionBuilder.ticks($0.timeRange.end) },
        ]
    }
}

// MARK: - The tap

/// What the probe's tap kept: channel 0 of every buffer, in order, with each
/// buffer's source-audio start (nil when not numeric) and frame count.
final class TapRecorder {
    let lock = NSLock()
    var samples: [Float] = []
    var chunks: [(Ticks?, Int)] = []
    var calls = 0
    var rate = 0.0
    var channels = 0
    var flags: AudioFormatFlags = 0
    var bits: UInt32 = 0
    var unreadable = 0

    func prepare(_ format: AudioStreamBasicDescription) {
        lock.lock()
        defer { lock.unlock() }
        rate = format.mSampleRate
        channels = Int(format.mChannelsPerFrame)
        flags = format.mFormatFlags
        bits = format.mBitsPerChannel
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        calls += 1
        guard frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let isFloat = flags & kAudioFormatFlagIsFloat != 0 && bits == 32
        let interleaved = flags & kAudioFormatFlagIsNonInterleaved == 0
        chunks.append((time.isNumeric ? CompositionBuilder.ticks(time) : nil, frames))
        guard isFloat, let first = buffers.first, let data = first.mData else {
            unreadable += 1
            samples.append(contentsOf: [Float](repeating: 0, count: frames))
            return
        }
        let stride = interleaved ? max(1, Int(first.mNumberChannels)) : 1
        let pointer = data.assumingMemoryBound(to: Float.self)
        let available = Int(first.mDataByteSize) / 4 / stride
        for i in 0..<frames { samples.append(i < available ? pointer[i * stride] : 0) }
    }
}

/// A PostEffects `MTAudioProcessingTap` feeding `recorder` (`AudioTap.make`'s
/// shape: the context retained by the tap and released in `finalize`).
func makeTap(_ recorder: TapRecorder, pre: Bool = false) -> MTAudioProcessingTap? {
    let context = Unmanaged.passRetained(recorder).toOpaque()
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: context,
        init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
        finalize: { tap in
            Unmanaged<TapRecorder>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        },
        prepare: { tap, _, format in
            Unmanaged<TapRecorder>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue().prepare(format.pointee)
        },
        unprepare: { _ in },
        process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
            let recorder = Unmanaged<TapRecorder>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            var timeRange = CMTimeRange()
            guard MTAudioProcessingTapGetSourceAudio(
                tap, numberFrames, bufferListInOut, flagsOut, &timeRange,
                numberFramesOut) == noErr
            else {
                numberFramesOut.pointee = 0
                return
            }
            recorder.process(
                bufferListInOut, frames: Int(numberFramesOut.pointee), time: timeRange.start)
        })
    var tap: MTAudioProcessingTap?
    guard MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks,
        pre ? kMTAudioProcessingTapCreationFlag_PreEffects
            : kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        == noErr
    else {
        Unmanaged<TapRecorder>.fromOpaque(context).release()
        return nil
    }
    return tap
}

// MARK: - Playback

/// One opened document and the editor over it
/// (`media_less_playback_probe.swift`'s `Opened`).
final class Opened {
    let document: ProjectDocument
    let editor: EditorViewController
    let player: AVPlayer

    init(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        document = ProjectDocument()
        try document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = url
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        guard let editor = document.windowControllers.first?.contentViewController
            as? EditorViewController, let player = editor.playback.playerLayer.player
        else { throw ProbeError("the document opened no editor with a player") }
        self.editor = editor
        self.player = player
        spin(3)
    }

    /// The editor's item, ready, with no rebuild in flight (bound 15 s).
    func readyItem() throws -> AVPlayerItem {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if let item = player.currentItem, item.status == .readyToPlay,
                editor.playback.built != nil, !editor.playback.rebuilding
            {
                return item
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        throw ProbeError("the editor's item was not ready within 15 s "
            + "(status \(player.currentItem?.status.rawValue ?? -1))")
    }

    func seekAndSettle(_ t: Ticks) {
        editor.playback.seek(to: t)
        let deadline = Date().addingTimeInterval(3)
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        } while editor.playback.isSeeking && Date() < deadline
    }

    func close() {
        editor.playback.pause()
        document.close()
        spin(0.5)
    }
}

func tapRead(_ job: Job, _ o: Opened) {
    read(job, "tap", ext: "f32") { url in
        let item = try o.readyItem()
        guard let plan = o.document.editedProject.plan else { throw ProbeError("no plan") }
        let tracks = item.asset.tracks(withMediaType: .audio)
        guard tracks.count == 1 else {
            throw ProbeError("\(tracks.count) composition audio tracks, not one")
        }
        let recorder = TapRecorder()
        guard ["post", "pre"].contains(job.tap_flag ?? "post") else {
            throw ProbeError("unknown tap_flag \(job.tap_flag ?? "")")
        }
        guard let tap = makeTap(recorder, pre: job.tap_flag == "pre") else {
            throw ProbeError("no tap was made")
        }
        var how = "audioParameters"
        let mix = AVMutableAudioMix()
        mix.inputParameters = try tracks.map { track -> AVAudioMixInputParameters in
            let parameters: AVMutableAudioMixInputParameters
            if let mutable = track as? AVMutableCompositionTrack,
                let planTrack = plan.audioTracks.first(where: { $0.id == Int(track.trackID) })
                    ?? (plan.audioTracks.count == 1 ? plan.audioTracks.first : nil)
            {
                let built = CompositionBuilder.audioParameters(
                    for: mutable, segments: planTrack.segments, ramps: planTrack.ramps,
                    onset: planTrack.segments.map(\.start).min(), dsp: nil, meter: nil)
                parameters = (built as? AVMutableAudioMixInputParameters)
                    ?? (built.mutableCopy() as! AVMutableAudioMixInputParameters)
            } else if let existing = item.audioMix?.inputParameters.first(where: {
                $0.trackID == track.trackID
            }) {
                how = "the item's own parameters, copied"
                parameters = existing.mutableCopy() as! AVMutableAudioMixInputParameters
            } else {
                throw ProbeError("composition audio track \(track.trackID) has no parameters")
            }
            parameters.audioTapProcessor = tap
            return parameters
        }
        item.audioMix = mix
        spin(0.5)
        o.seekAndSettle(0)
        spin(0.3)
        let seconds = Double(job.length) / Double(ReelTime.perSecond)
        let started = Date()
        o.editor.playback.play()
        while CompositionBuilder.ticks(o.player.currentTime()) < job.length,
            Date().timeIntervalSince(started) < 3 * seconds
        {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        spin(0.5)
        o.editor.playback.pause()
        spin(0.3)
        let reached = CompositionBuilder.ticks(o.player.currentTime())
        recorder.lock.lock()
        let samples = recorder.samples
        let chunks = recorder.chunks.map { chunk -> [Any] in
            [chunk.0.map { NSNumber(value: $0) as Any } ?? NSNull(), chunk.1]
        }
        let line: [String: Any] = [
            "chunks": chunks, "calls": recorder.calls, "mix": how, "reached": reached,
            "tap_flag": job.tap_flag ?? "post",
            "played_s": Date().timeIntervalSince(started),
            "format": [
                "rate": recorder.rate, "channels": recorder.channels,
                "flags": Int(recorder.flags), "bits": Int(recorder.bits),
                "unreadable": recorder.unreadable,
            ] as [String: Any],
        ]
        recorder.lock.unlock()
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: url)
        return line
    }
}

/// The mean Rec. 709 luma (0…255) of each bar's centre 16 × 16 block, the
/// bars 32 px wide on a 320 px canvas, scaled to the buffer's size.
func barLumas(_ buffer: CVPixelBuffer) -> [Double]? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
        CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let scale = Double(w) / 320
    let half = max(1, Int((8 * scale).rounded()))
    return (0..<10).map { j in
        let cx = Int(((32 * Double(j) + 16) * scale).rounded())
        let cy = h / 2
        var sum = 0.0
        var n = 0
        for y in max(0, cy - half)..<min(h, cy + half) {
            let p = (base + y * row).assumingMemoryBound(to: UInt8.self)
            for x in max(0, cx - half)..<min(w, cx + half) {
                let b = Double(p[x * 4]), g = Double(p[x * 4 + 1]), r = Double(p[x * 4 + 2])
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                n += 1
            }
        }
        return n > 0 ? sum / Double(n) : 0
    }
}

func framesRead(_ job: Job, _ o: Opened) {
    read(job, "frames", ext: "json") { url in
        let item = try o.readyItem()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        defer { item.remove(output) }
        spin(0.3)
        var bars: [Any] = []
        var missing = 0
        let count = Int(job.length / 20_000)
        for k in 0..<count {
            let t = Ticks(k) * 20_000
            o.seekAndSettle(t)
            let target = CompositionBuilder.time(t)
            var buffer: CVPixelBuffer?
            let deadline = Date().addingTimeInterval(1)
            repeat {
                buffer = output.copyPixelBuffer(forItemTime: target, itemTimeForDisplay: nil)
                if buffer == nil {
                    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
                }
            } while buffer == nil && Date() < deadline
            if let lumas = buffer.flatMap(barLumas) {
                bars.append(lumas)
            } else {
                bars.append(NSNull())
                missing += 1
                if missing == k + 1, k >= 2 {
                    throw ProbeError("the video output vended no buffer for frames 0…\(k)")
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: bars)
        try data.write(to: url)
        return ["bars": bars, "missing": missing, "frames": count]
    }
}

// MARK: - Render (SR1b)

struct RenderJob: Decodable {
    let name: String
    let source: String
    let clip_ticks: [Int64]
    let source_ticks: [Double]
    let keep_pitch: Bool
    let destination: String
    let lead_frames: Int?
}

func peakRSS() -> Int64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return -1 }
    return Int64(usage.ru_maxrss)  // bytes on macOS
}

func renderRead(_ job: RenderJob) {
    var line: [String: Any] = ["name": job.name, "read": "render", "path": job.destination]
    let destination = URL(fileURLWithPath: job.destination)
    try? FileManager.default.removeItem(at: destination)
    do {
        var renderJob = RampAudioRenderer.Job(
            source: URL(fileURLWithPath: job.source),
            map: RampAudioMap(clipTicks: job.clip_ticks, sourceTicks: job.source_ticks),
            keepPitch: job.keep_pitch, destination: destination)
        renderJob.leadFrames = job.lead_frames
        let report = try RampAudioRenderer.render(renderJob)
        line["ok"] = true
        line["error"] = NSNull()
        line["frames"] = report.frames
        line["channels"] = report.channels
        line["wall_s"] = report.wallSeconds
        line["bytes"] = report.bytes
        line["latency_frames"] = report.latencyFrames.map { $0 as Any } ?? NSNull()
        line["pulled_frames"] = report.pulledFrames.map { $0 as Any } ?? NSNull()
        line["lead_frames"] = report.leadFrames.map { $0 as Any } ?? NSNull()
    } catch {
        line["ok"] = false
        line["error"] = "\(error)"
    }
    line["peak_rss_bytes"] = peakRSS()
    emit(line)
}

if group == "render" {
    let renderJobs: [RenderJob]
    do {
        renderJobs = try JSONDecoder().decode(
            [RenderJob].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
    } catch {
        FileHandle.standardError.write(Data("the job file could not be read: \(error)\n".utf8))
        exit(3)
    }
    for job in renderJobs { renderRead(job) }
    exit(0)
}

// MARK: - The jobs

let jobs: [Job]
do {
    jobs = try JSONDecoder().decode(
        [Job].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
} catch {
    FileHandle.standardError.write(Data("the job file could not be read: \(error)\n".utf8))
    exit(3)
}

for job in jobs {
    switch group {
    case "plan":
        planRead(job)
    case "export":
        for kind in job.reads {
            switch kind {
            case "wav": exportRead(job, "wav", preset: "audio_wav", ext: "wav")
            case "prores": exportRead(job, "prores", preset: "prores_422", ext: "mov")
            case "mix": mixRead(job)
            default: emit(["name": job.name, "read": kind, "ok": false, "error": "unknown read"])
            }
        }
    default:
        let opened: Opened
        do {
            opened = try Opened(job.project)
        } catch {
            for kind in job.reads {
                emit(["name": job.name, "read": kind, "ok": false, "error": "open: \(error)"])
            }
            continue
        }
        for kind in job.reads {
            switch kind {
            case "tap": tapRead(job, opened)
            case "frames": framesRead(job, opened)
            default: emit(["name": job.name, "read": kind, "ok": false, "error": "unknown read"])
            }
        }
        opened.close()
    }
}
exit(0)
