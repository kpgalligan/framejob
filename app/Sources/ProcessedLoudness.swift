import AVFoundation
import Foundation

/// A clip's loudness measured through its own chain (spec §11 AU-64): the
/// clip's window rendered offline through the composition the export builds,
/// pre-fader, and read into the 10 ms steps a `ClipLoudness` reading has.
/// Enhance Voice and Loudness Normalize solve their volume on it
/// (`LoudnessMeasureRun`), because the cleaning stages change which blocks
/// BS.1770's relative gate counts, which the loudness cache cannot see.
///
/// The pieces, in the order a press uses them: `needsRender` (which clips
/// render at all, (a)); `measurementPlan` (the trial's plan cut to the clip,
/// pre-fader, (c)); `render` (the export's waits, the build and one mix read,
/// (d)); and `Memo`, the last R0 per clip, plan and chain, which At volume
/// reads (g). The trial handle itself is made on main by the run, (b).
enum ProcessedLoudness {
    /// One render at a time, off main.
    static let queue = DispatchQueue(
        label: "com.kgalligan.FrameJob.processed-loudness", qos: .userInitiated)

    /// AU-64 (a): whether the clip's base audio has a stage the loudness
    /// cache leaves out. Pan, mono, channels and the limiter are counted or
    /// modelled by the cache reading, so a clip with only those plans off the
    /// cache as before.
    static func needsRender(_ audio: AudioProps?) -> Bool {
        guard let audio else { return false }
        if let eq = audio.eq, !eq.bypass, eq.activeCount > 0 { return true }
        if audio.hum != nil || audio.isolation > 0 || audio.noiseReduction > 0 { return true }
        if audio.gate != nil || audio.deEsser != nil || audio.compressor != nil { return true }
        if audio.leveller != nil { return true }
        if let voice = audio.voice, !VoiceChain.isInert(VoiceChain.settings(voice)) { return true }
        return false
    }

    // MARK: - The measurement plan

    struct MeasurementPlan {
        let plan: CompositionPlan
        /// The edited plan as JSON, keys sorted: the builder's `planJSON` and
        /// the memo key's `plan`.
        let json: String
        /// The span of the clip's segments, timeline ticks.
        let start: Ticks
        let end: Ticks
    }

    /// AU-64 (c): `planJSON` with only `clip`'s audio segments (a track left
    /// empty dropped), every track's `ramps` removed and every segment's
    /// `track_pans` emptied (pre-fader: no volume, fades, ducks, mute, track
    /// volume or pan), no video tracks or ducks, and one instruction over the
    /// plan. nil when the clip has no audio segment or the JSON cannot be read.
    ///
    /// With a `volume` other than 1 each kept track's ramps are instead ONE
    /// constant ramp at it over the plan: the clip's base volume as the
    /// export's fader applies it, and nothing else of the envelope. A render
    /// is read through it (`render`), because a gated clip under a limiter
    /// read with no ramp measured 0.19–0.25 LU above its own export, and
    /// with the ramp the same as it (AP6's record).
    static func measurementPlan(_ planJSON: String, clip: UInt32, volume: Double? = nil)
        -> MeasurementPlan?
    {
        guard let data = planJSON.data(using: .utf8),
            var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let duration = (root["duration"] as? NSNumber)?.int64Value ?? 0
        var tracks: [[String: Any]] = []
        var start = Ticks.max
        var end = Ticks.min
        for var track in root["audio_tracks"] as? [[String: Any]] ?? [] {
            var segments: [[String: Any]] = []
            for var segment in track["segments"] as? [[String: Any]] ?? [] {
                guard (segment["clip"] as? NSNumber)?.uint32Value == clip else { continue }
                let from = (segment["start"] as? NSNumber)?.int64Value ?? 0
                let length = (segment["duration"] as? NSNumber)?.int64Value ?? 0
                start = min(start, Ticks(from))
                end = max(end, Ticks(from + length))
                segment["track_pans"] = [Double]()
                segments.append(segment)
            }
            guard !segments.isEmpty else { continue }
            track["segments"] = segments
            track.removeValue(forKey: "ramps")
            tracks.append(track)
        }
        guard !tracks.isEmpty, end > start else { return nil }
        let span = max(duration, Int64(end))
        if let volume, volume.isFinite, volume >= 0, volume != 1 {
            let fader: [String: Any] = ["start": 0, "duration": span, "from": volume, "to": volume]
            tracks = tracks.map { var track = $0; track["ramps"] = [fader]; return track }
        }
        root["audio_tracks"] = tracks
        root["video_tracks"] = [[String: Any]]()
        root["ducks"] = [[String: Any]]()
        root["instructions"] = [
            ["start": 0, "duration": span, "required_track_ids": [Int]()] as [String: Any]
        ]
        guard
            let out = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
            let json = String(data: out, encoding: .utf8),
            let plan = ReelJSON.decode(CompositionPlan.self, from: json)
        else { return nil }
        return MeasurementPlan(plan: plan, json: json, start: start, end: end)
    }

    // MARK: - The memo's key

    /// What one R0 was measured from: the clip, its measurement plan and its
    /// chain (the audio props less volume, mute, fades, their shapes, the
    /// duck and the limiter, which are the fader's or the solve's).
    struct Key: Hashable {
        let clip: UInt32
        let plan: String
        let chain: String
    }

    /// The key of `clip` in `project` (a scoped handle in a nest); nil when it
    /// has no audio props or no audio segment.
    static func key(clip: UInt32, project: ReelProject) -> Key? {
        guard let a = project.snapshot.clip(clip)?.audio,
            let measured = measurementPlan(project.planJSON, clip: clip)
        else { return nil }
        let chain = AudioProps(
            mono: a.mono, keepPitch: a.keepPitch, pan: a.pan, compressor: a.compressor,
            noiseReduction: a.noiseReduction, isolation: a.isolation, eq: a.eq, hum: a.hum,
            channels: a.channels, gate: a.gate, deEsser: a.deEsser, voice: a.voice,
            leveller: a.leveller)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(chain), let text = String(data: data, encoding: .utf8)
        else { return nil }
        return Key(clip: clip, plan: measured.json, chain: text)
    }

    // MARK: - The render

    enum Rendered: Equatable {
        /// The steps' energies and linear true peaks, as `StepLoudnessMeter` gives them.
        case steps([Double], peaks: [Double])
        /// An `ExportError` from the waits, its own sentence.
        case failed(String)
        /// A skip's reason, a sentence after the clip's name.
        case skipped(String)
        case cancelled
    }

    /// AU-64 (d): `trial`'s measurement plan for `clip` rendered under a
    /// fresh `RecipeSource` key with `resolution` published for it, through
    /// the export's waits (`Exporter.withOfflineAudio`), the build and one
    /// float mix read placed by stamp into a `StepLoudnessMeter`. The key is
    /// unregistered and unpublished before the return, and answered so the
    /// caller releases its render wants when the press is done. The steps
    /// are at the trial clip's base volume, through its fader
    /// (`measurementPlan`'s `volume`): a trial at volume 1 reads pre-fader.
    /// `spectrum`, when given, is fed every frame the step meter is (Match
    /// Audio's speech spectrum, spec §11 AU-124). Never main.
    static func render(
        _ trial: ReelProject, clip: UInt32, urls: [UInt32: URL], resolution: ReverseResolution,
        spectrum: SpeechSpectrumMeter? = nil, cancelled: @escaping () -> Bool
    ) -> (Rendered, key: Int) {
        assert(!Thread.isMainThread)
        let key = RecipeSource.shared.register()
        guard !resolution.pending.contains(clip) else {
            RecipeSource.shared.unregister(key)
            return (.skipped("its reversed copy is still being made."), key)
        }
        RecipeSource.shared.set(trial, for: key)
        ReverseSource.shared.publish(resolution, project: trial, for: key)
        defer {
            ReverseSource.shared.unpublish(key)
            RecipeSource.shared.unregister(key)
        }
        let volume = trial.snapshot.clip(clip)?.audio?.volume
        guard let measured = measurementPlan(trial.planJSON, clip: clip, volume: volume) else {
            return (.skipped("plays no sound in this timeline."), key)
        }
        let rendered: Rendered
        do {
            rendered = try Exporter.withOfflineAudio(
                plan: measured.plan, urls: urls, key: key, cancelled: cancelled
            ) {
                let built = try CompositionBuilder.build(
                    plan: measured.plan, planJSON: measured.json, urls: urls, recipeKey: key)
                return read(
                    built, from: measured.start, to: measured.end, spectrum: spectrum,
                    cancelled: cancelled)
            }
        } catch Exporter.ExportError.cancelled {
            return (.cancelled, key)
        } catch let error as Exporter.ExportError {
            return (.failed(error.errorDescription ?? "\(error)"), key)
        } catch {
            return (.failed(error.localizedDescription), key)
        }
        if case .steps(let steps, _) = rendered, StepLoudness.integrated(steps) == nil {
            return (.skipped("is under −70 LUFS after its processing."), key)
        }
        return (rendered, key)
    }

    /// One `AVAssetReaderAudioMixOutput` of every audio track through the
    /// built mix over `[start, end)`, streamed into a `StepLoudnessMeter`:
    /// each buffer placed by its stamp as `ScrubGrains.read` places it, a gap
    /// fed as zeros, and the span always fed whole.
    private static func read(
        _ built: BuiltComposition, from start: Ticks, to end: Ticks,
        spectrum: SpeechSpectrumMeter?, cancelled: () -> Bool
    ) -> Rendered {
        let rate = ExportAudioEnd.sampleRate
        let frames = ExportAudioEnd.frames(ofTicks: end - start)
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard frames > 0, !tracks.isEmpty, let reader = try? AVAssetReader(asset: built.composition)
        else { return .failed("its sound could not be read.") }
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks, audioSettings: ExportAudioMaster.floatMixSettings)
        output.audioMix = built.audioMix
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return .failed("its sound could not be read.") }
        reader.add(output)
        let startTime = CompositionBuilder.time(start)
        reader.timeRange = CMTimeRange(
            start: startTime,
            duration: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(rate)))
        guard reader.startReading() else {
            return .failed(reader.error?.localizedDescription ?? "its sound could not be read.")
        }
        let meter = StepLoudnessMeter()
        var fed = 0
        var silence = [Float](repeating: 0, count: 2 * 4800)
        func feedSilence(until frame: Int) {
            while fed < frame {
                let take = min(frame - fed, 4800)
                silence.withUnsafeBufferPointer {
                    meter.feed($0.baseAddress!, frames: take)
                    spectrum?.feed($0.baseAddress!, frames: take)
                }
                fed += take
            }
        }
        var interleaved: [Float] = []
        while fed < frames, let sample = output.copyNextSampleBuffer() {
            if cancelled() {
                reader.cancelReading()
                return .cancelled
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMBlockBufferGetDataLength(block) / (2 * MemoryLayout<Float>.size)
            guard count > 0 else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let offset = Int(
                CMTimeConvertScale(
                    CMTimeSubtract(pts, startTime), timescale: CMTimeScale(rate),
                    method: .roundHalfAwayFromZero
                ).value)
            feedSilence(until: min(max(offset, 0), frames))
            if interleaved.count < 2 * count {
                interleaved = [Float](repeating: 0, count: 2 * count)
            }
            let copied = interleaved.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: 2 * count * MemoryLayout<Float>.size,
                    destination: raw.baseAddress!)
            }
            guard copied == kCMBlockBufferNoErr else { continue }
            let first = max(0, fed - offset)
            let last = min(count, frames - offset)
            if first < last {
                interleaved.withUnsafeBufferPointer {
                    meter.feed($0.baseAddress! + 2 * first, frames: last - first)
                    spectrum?.feed($0.baseAddress! + 2 * first, frames: last - first)
                }
                fed = offset + last
            }
        }
        if fed < frames, reader.status == .reading { reader.cancelReading() }
        guard reader.status != .failed else {
            return .failed(reader.error?.localizedDescription ?? "its sound could not be read.")
        }
        feedSilence(until: frames)
        silence.removeAll()
        let measured = meter.finish()
        return .steps(measured.steps, peaks: measured.peaks)
    }

    // MARK: - The readout's memo

    /// AU-64 (g): the last R0 measured per `Key`, which At volume reads on a
    /// clip that renders. 32 keys, oldest out first; emptied when a loudness
    /// file lands or is withdrawn and when an offline render settles. Held
    /// through a live gesture for the same clip of the same document, as
    /// `ClipLoudness.Memo` holds its answer, so a Volume drag decodes no plan
    /// per tick. Main only.
    final class Memo {
        static let shared = Memo()
        static let capacity = 32

        private var entries: [Key: (steps: [Double], peaks: [Double])] = [:]
        private var order: [Key] = []
        private weak var heldDocument: ProjectDocument?
        private weak var heldProject: ReelProject?
        private var heldClip: UInt32?
        private var held: (steps: [Double], peaks: [Double])?

        private init() {
            NotificationCenter.default.addObserver(
                forName: .mediaCacheDidChange, object: nil, queue: .main
            ) { [weak self] note in
                guard note.userInfo?[MediaImporter.cacheKindKey] as? String
                    == MediaImporter.loudnessKind
                else { return }
                self?.removeAll()
            }
            NotificationCenter.default.addObserver(
                forName: .reversedMediaDidChange, object: nil, queue: .main
            ) { [weak self] _ in self?.removeAll() }
        }

        func store(_ key: Key, steps: [Double], peaks: [Double]) {
            assert(Thread.isMainThread)
            if entries.updateValue((steps, peaks), forKey: key) == nil { order.append(key) }
            while order.count > Self.capacity { entries.removeValue(forKey: order.removeFirst()) }
            forget()
        }

        func reading(for clip: UInt32, in document: ProjectDocument)
            -> (steps: [Double], peaks: [Double])?
        {
            assert(Thread.isMainThread)
            if heldClip == clip, heldDocument === document,
                document.isLiveEditing || heldProject === document.editedProject
            {
                return held
            }
            let project = document.editedProject
            let answer = Self.key(clip: clip, project: project).flatMap { entries[$0] }
            heldDocument = document
            heldProject = project
            heldClip = clip
            held = answer
            return answer
        }

        private func removeAll() {
            entries.removeAll()
            order.removeAll()
            forget()
        }

        private func forget() {
            heldDocument = nil
            heldProject = nil
            heldClip = nil
            held = nil
        }

        private static func key(clip: UInt32, project: ReelProject) -> Key? {
            ProcessedLoudness.key(clip: clip, project: project)
        }
    }
}
