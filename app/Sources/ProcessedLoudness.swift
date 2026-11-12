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
/// render at all, (a), an action's end counted since AU-159 and its limiter
/// since AU-165, `endSetsLimiter`);
/// `measurementPlan` (the trial's plan cut to the clip, pre-fader, (c)); `render` (the export's waits, the build and one mix read,
/// (d)); and `Memo`, the last R0 per document, clip, plan and chain, which At volume
/// reads (g), with the verify render that answered a press (`Verified`, AU-165 (c)). The
/// trial handle itself is made on main by the run, (b).
enum ProcessedLoudness {
    /// One render at a time, off main.
    static let queue = DispatchQueue(
        label: "com.kgalligan.FrameJob.processed-loudness", qos: .userInitiated)

    /// AU-64 (a) as AU-159 (a) and AU-165 (a) amend it: whether the clip
    /// plays through a stage the loudness cache leaves out, in its base audio
    /// or at the end of one of its actions with a duration above 0, or a
    /// limiter an action's end sets. Read from the snapshot: never the plan,
    /// the playhead or a selected action. It errs toward a render: an end's
    /// EQ counts whatever its slots, and an action outside the played window
    /// counts.
    static func needsRender(_ clip: ClipSnapshot?) -> Bool {
        guard let clip else { return false }
        if needsRender(clip.audio) || endSetsLimiter(clip) { return true }
        return clip.actions.contains { $0.duration > 0 && endNeedsRender($0.end.audio) }
    }

    /// AU-165 (a): whether an action of the clip with a duration above 0 has
    /// the `limiter` key at its end, a limiter or a null keying the clip's
    /// own off. The cache's model runs only the clip's own limiter over the
    /// whole clip, so it sees neither, and an end limiter's threshold follows
    /// the base volume (AU-22), so the solve checks it by render. The memo's
    /// key names the same ends.
    static func endSetsLimiter(_ clip: ClipSnapshot?) -> Bool {
        guard let clip else { return false }
        return clip.actions.contains { action in
            guard action.duration > 0, let end = action.end.audio else { return false }
            if case .some = end.limiter { return true }
            return false
        }
    }

    /// Whether an action's end switches one of (a)'s stages on: a `hum`,
    /// `gate`, `de_esser`, `compressor`, `leveller` or `eq` that is not null,
    /// an `isolation` or `noise_reduction` above 0. `voice` is the base's
    /// alone (AU-88).
    private static func endNeedsRender(_ end: AudioPatch?) -> Bool {
        guard let end else { return false }
        func on<T>(_ value: T??) -> Bool {
            if case .some(.some) = value { return true }
            return false
        }
        if on(end.eq) || on(end.hum) || on(end.gate) || on(end.deEsser) { return true }
        if on(end.compressor) || on(end.leveller) { return true }
        return (end.isolation ?? 0) > 0 || (end.noiseReduction ?? 0) > 0
    }

    /// The base half of `needsRender`: whether these props have a stage the
    /// loudness cache leaves out. Pan, mono, channels and the limiter are
    /// counted or modelled by the cache reading, so a clip with only those
    /// plans off the cache as before.
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

    /// What one R0 was measured from: the document (its `recipeKey`, so two
    /// open projects never share one, #401), the clip, its measurement plan
    /// and its chain (the audio props less volume, mute, fades, their shapes,
    /// the duck and the limiter, which are the fader's or the solve's).
    ///
    /// AU-159 (g): `plan` is the measurement plan with `limiter` taken out of
    /// every automation point, because the core writes the BASE limiter into
    /// each point and R0 is measured with that limiter cleared: left in, the
    /// solve's own limiter would change the key and the reading would never
    /// be found again. `chain` then names each action end that has the
    /// `limiter` key, a null ("off") included, with the action's start,
    /// duration and curve, so the key still follows a limiter an action
    /// switches on or off, which R0 IS measured through.
    struct Key: Hashable {
        let document: Int
        let clip: UInt32
        let plan: String
        let chain: String
    }

    /// The key of `clip` in `project` (a scoped handle in a nest) of the
    /// document whose `recipeKey` is `document`; nil when it has no audio
    /// props or no audio segment.
    static func key(clip: UInt32, project: ReelProject, document: Int) -> Key? {
        guard let snapshot = project.snapshot.clip(clip), let a = snapshot.audio,
            let measured = measurementPlan(project.planJSON, clip: clip),
            let plan = withoutPointLimiters(measured.json)
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
        var ends = ""
        for action in snapshot.actions where action.duration > 0 {
            guard let limiter = action.end.audio?.limiter else { continue }
            let value = limiter.map { "\($0.ceilingDb),\($0.release)" } ?? "off"
            ends += "|\(action.start):\(action.duration):\(action.curve.rawValue):\(value)"
        }
        return Key(document: document, clip: clip, plan: plan, chain: text + ends)
    }

    /// A measurement plan's JSON with `limiter` removed from every
    /// segment's automation points, keys sorted; nil when it cannot be read.
    /// Only the memo's key reads it: `render` builds from the plan as it is.
    private static func withoutPointLimiters(_ json: String) -> String? {
        guard json.contains("\"automation\"") else { return json }
        guard let data = json.data(using: .utf8),
            var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        root["audio_tracks"] = (root["audio_tracks"] as? [[String: Any]] ?? []).map { item in
            var track = item
            track["segments"] = (track["segments"] as? [[String: Any]] ?? []).map { item in
                var segment = item
                guard let points = segment["automation"] as? [[String: Any]] else { return segment }
                segment["automation"] = points.map { item -> [String: Any] in
                    var point = item
                    if var audio = point["audio"] as? [String: Any] {
                        audio.removeValue(forKey: "limiter")
                        point["audio"] = audio
                    }
                    return point
                }
                return segment
            }
            return track
        }
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        else { return nil }
        return String(data: out, encoding: .utf8)
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

    /// AU-165 (c): the verify render that answered a press on a clip with an
    /// action-end limiter (`endSetsLimiter`): the volume and limiter it
    /// rendered at, and its loudness and linear true peak through the fader
    /// at that volume, as the clip plays at them.
    struct Verified: Equatable {
        let volume: Double
        let limiter: LimiterProps?
        let lufs: Double
        let truePeak: Double

        /// Whether a clip at `current` and `own` plays as this render did: the
        /// same limiter, and the volume within `AudioNormalize.keepVolumeDB`
        /// (the keep rule's figure, so a kept volume still reads it).
        func holds(volume current: Double, limiter own: LimiterProps?) -> Bool {
            guard own == limiter, current > 0, volume > 0 else { return false }
            return abs(20 * log10(current / volume)) <= AudioNormalize.keepVolumeDB
        }
    }

    /// What At volume reads for a clip: R0's steps and step peaks, and the
    /// verify render that answered the last press since that R0, if any.
    typealias Reading = (steps: [Double], peaks: [Double], verified: Verified?)

    /// AU-64 (g): the last R0 measured per `Key`, which At volume reads on a
    /// clip that renders, and beside it the verify render that answered a
    /// press (AU-165 (c)). 32 keys, oldest out first; emptied when a loudness
    /// file lands or is withdrawn and when an offline render settles. Held
    /// through a live gesture for the same clip of the same document, as
    /// `ClipLoudness.Memo` holds its answer, so a Volume drag decodes no plan
    /// per tick. Main only.
    final class Memo {
        static let shared = Memo()
        static let capacity = 32

        private var entries: [Key: (steps: [Double], peaks: [Double])] = [:]
        private var verified: [Key: Verified] = [:]
        private var order: [Key] = []
        private weak var heldDocument: ProjectDocument?
        private weak var heldProject: ReelProject?
        private var heldClip: UInt32?
        private var held: Reading?

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

        /// A new R0 for `key`: any verify render stored beside the last one
        /// goes with it.
        func store(_ key: Key, steps: [Double], peaks: [Double]) {
            assert(Thread.isMainThread)
            if entries.updateValue((steps, peaks), forKey: key) == nil { order.append(key) }
            verified.removeValue(forKey: key)
            while order.count > Self.capacity {
                let oldest = order.removeFirst()
                entries.removeValue(forKey: oldest)
                verified.removeValue(forKey: oldest)
            }
            forget()
        }

        /// AU-165 (c): the verify render that answered a press, beside the R0
        /// stored under `key`; nothing when no R0 is.
        func storeVerified(_ key: Key, _ figures: Verified) {
            assert(Thread.isMainThread)
            guard entries[key] != nil else { return }
            verified[key] = figures
            forget()
        }

        func reading(for clip: UInt32, in document: ProjectDocument) -> Reading? {
            assert(Thread.isMainThread)
            if heldClip == clip, heldDocument === document,
                document.isLiveEditing || heldProject === document.editedProject
            {
                return held
            }
            let project = document.editedProject
            let answer = Self.key(clip: clip, project: project, document: document.recipeKey)
                .flatMap { key in
                    entries[key].map { ($0.steps, $0.peaks, verified[key]) }
                }
            heldDocument = document
            heldProject = project
            heldClip = clip
            held = answer
            return answer
        }

        private func removeAll() {
            entries.removeAll()
            verified.removeAll()
            order.removeAll()
            forget()
        }

        private func forget() {
            heldDocument = nil
            heldProject = nil
            heldClip = nil
            held = nil
        }

        private static func key(clip: UInt32, project: ReelProject, document: Int) -> Key? {
            ProcessedLoudness.key(clip: clip, project: project, document: document)
        }
    }
}
