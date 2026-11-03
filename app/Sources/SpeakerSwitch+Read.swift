import Foundation

/// Switch by Speaker's one reader (spec §11 SW-20, SW-25), shaped like
/// `AudioSync.read`: the edited project's snapshot and plan, and each
/// microphone's loudness and speech caches, read onto the range's 10 ms grid
/// through `ClipLevelSeries`. A missing cache file is "still being analysed",
/// never silence.
extension SpeakerSwitch {
    /// `clips` nil: the document's selection. `pairing` nil: SW-20's
    /// defaults. `range` nil: the In–Out range, else the selected angle
    /// clips' extent. nil only when the edited project's plan cannot be read.
    static func read(
        from document: ProjectDocument, clips: [UInt32]?, pairing: Pairing?,
        range: (from: Ticks, to: Ticks)?, settings: Settings
    ) -> Input? {
        let project = document.editedProject
        guard let plan = project.plan else { return nil }
        let snapshot = project.snapshot
        var seen: Set<UInt32> = []
        let selection = (clips ?? document.selection.sorted())
            .filter { seen.insert($0).inserted }
            .compactMap { snapshot.clip($0) }
        let implied = defaults(selection: selection, in: snapshot)
        let pairing = pairing ?? implied.pairing

        // A named pairing's microphones are the tracks it names that hold a
        // selected sounding clip, a detached camera sound included (SW-20).
        let front = snapshot.tracks.reversed().map(\.id)
        let microphoneTracks: [UInt32]
        if pairing == implied.pairing {
            microphoneTracks = implied.microphones
        } else {
            let named = Set(pairing.speakers.compactMap(\.mic))
            microphoneTracks = front.filter { track in
                named.contains(track) && selection.contains {
                    guard $0.track == track, case .media = $0.source, $0.enabled.audio else {
                        return false
                    }
                    return snapshot.media(for: $0)?.hasAudio == true
                }
            }
        }

        let angles = implied.angles.map { track in
            AngleTrack(
                track: track,
                clips: SwitchAngle.pictureClips(on: track, in: snapshot).map {
                    Span(clip: $0.id, start: $0.start, end: $0.end)
                })
        }
        let angleClips = selection.filter {
            implied.angles.contains($0.track) && isPicture($0, in: snapshot)
        }
        let span = range ?? document.inOutRange.map { ($0.start, $0.end) }
            ?? (angleClips.map(\.start).min() ?? 0, angleClips.map(\.end).max() ?? 0)
        let step = stepTicks
        let count = step > 0 ? Int(max(0, span.1 - span.0) / step) : 0

        let segments = AudioNormalize.audioSegments(in: plan)
        let voiced = SileroVAD.isAvailable
        var loudness: [UInt32: MediaLoudness] = [:]
        var speech: [UInt32: [Float]] = [:]
        var problems: [String] = []
        var microphones: [Microphone] = []
        for track in microphoneTracks {
            let clips = selection.filter { $0.track == track && segments[$0.id] != nil }
                .sorted { $0.start < $1.start }
            let media = clips.compactMap { segments[$0.id]?.first?.media }
            for id in media where loudness[id] == nil {
                if let read = document.cacheDirectory.flatMap({
                    MediaImporter.loadLoudness(for: id, in: $0)
                }) { loudness[id] = read }
            }
            if voiced {
                for id in media where speech[id] == nil {
                    if let read = document.cacheDirectory.flatMap({
                        MediaImporter.loadSpeech(for: id, in: $0)
                    }) { speech[id] = read }
                }
            }
            let unread = "The microphone on track \(track) is still being analysed — its "
            var pending = false
            if media.contains(where: { loudness[$0] == nil }) {
                pending = true
                problems.append(unread + "loudness has not been measured yet. Try again in a moment.")
            } else if voiced, media.contains(where: { speech[$0] == nil }) {
                pending = true
                problems.append(unread + "speech has not been detected yet. Try again in a moment.")
            }
            guard !pending, voiced else {
                microphones.append(Microphone(track: track, level: [], voice: [], covered: []))
                continue
            }
            var energy = [Double](repeating: 0, count: count)
            var voice = [Float](repeating: 0, count: count)
            var covered = [Bool](repeating: false, count: count)
            for clip in clips {
                guard let own = segments[clip.id], let first = own.first,
                    let cache = loudness[first.media]
                else { continue }
                let cited = own.filter { $0.media == first.media }
                let pivots = cited.map { MediaPeaks.reversedPivot(for: $0, in: snapshot) }
                let low = cited.map(\.start).min() ?? 0
                let high = cited.map { $0.start + $0.duration }.max() ?? 0
                let k0 = max(0, Int(MediaPeaks.bucketIndex(low - span.0, bucket: step)))
                let k1 = min(count, Int(MediaPeaks.bucketIndex(high - span.0 + step - 1, bucket: step)))
                guard k1 > k0 else { continue }
                let origin = span.0 + Ticks(k0) * step
                let read = ClipLevelSeries.energies(
                    cache, segments: cited, pivots: pivots, matrix: .init(clip.audio),
                    from: origin, count: k1 - k0)
                let p = ClipLevelSeries.voice(
                    speech[first.media] ?? [], segments: cited, pivots: pivots, from: origin,
                    count: k1 - k0)
                for j in 0..<(k1 - k0) where read.covered[j] {
                    energy[k0 + j] = read.energy[j]
                    voice[k0 + j] = p[j]
                    covered[k0 + j] = true
                }
            }
            microphones.append(
                Microphone(
                    track: track, level: ClipLevelSeries.levels(energy), voice: voice,
                    covered: covered))
        }
        if !voiced {
            problems.append(
                "Speech detection is unavailable on this Mac, so Switch by Speaker cannot tell "
                    + "who is talking.")
        }
        return Input(
            from: span.0, to: span.1, fps: snapshot.canvas.fps, angles: angles,
            microphones: microphones, pairing: pairing, problems: problems,
            clipCount: ShotSplit.clipCount(document.project.snapshot), settings: settings)
    }
}
