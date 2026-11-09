import Foundation

/// Switch by Speaker's faces mode (road map "creator-jobs" SW8, spec §11 SW-80…SW-86): one
/// microphone shared by two or more angles, who talks decided by each angle's mouth activity
/// (`FaceActivity`) while the microphone hears speech, and SW-22's `shots` run unchanged over
/// those labels with the face pairing.
///
/// `withoutWide`, `faceSpeakers`, `mode`, `facePairing`, `faceLabels` and `faceSeries` are pure
/// (SW-25). `readFaces` (from `read`) and `facesWanted` (the menu's Analyzing sheet, the tool's
/// wait) are the switch's second and third readers: the `faces` kind through the analysis store
/// in forward-media source ticks (SW-84). Names no `rc_*`.
extension SpeakerSwitch {

    // MARK: - The mode (SW-83)

    /// Each speaker whose angle is the wide AND whose microphone another speaker shares is
    /// dropped; every other pairing comes back identical.
    static func withoutWide(_ pairing: Pairing) -> Pairing {
        guard let wide = pairing.wide else { return pairing }
        let speakers = pairing.speakers
        let kept = speakers.indices.filter { i in
            guard speakers[i].angle == wide, let mic = speakers[i].mic else { return true }
            return !speakers.indices.contains { $0 != i && speakers[$0].mic == mic }
        }
        return Pairing(speakers: kept.map { speakers[$0] }, wide: wide)
    }

    /// The speakers with an angle that is not the wide, the first per angle.
    static func faceSpeakers(_ pairing: Pairing) -> [Speaker] {
        var seen: Set<UInt32> = []
        return pairing.speakers.filter { speaker in
            guard let angle = speaker.angle, angle != pairing.wide else { return false }
            return seen.insert(angle).inserted
        }
    }

    /// Faces when two or more face speakers all name one microphone; else microphones.
    static func mode(_ pairing: Pairing) -> Mode {
        let speakers = faceSpeakers(pairing)
        guard speakers.count >= 2, let mic = speakers[0].mic,
            speakers.allSatisfy({ $0.mic == mic })
        else { return .microphones }
        return .faces
    }

    /// The face speakers as their own labels — `(mic: angle, angle: angle)` — and the same wide,
    /// so `shots` maps `faceLabels`' `.person(angle)` to that angle.
    static func facePairing(_ pairing: Pairing) -> Pairing {
        Pairing(
            speakers: faceSpeakers(pairing).map { Speaker(mic: $0.angle, angle: $0.angle) },
            wide: pairing.wide)
    }

    // MARK: - The labels (SW-81)

    /// One label per step: `.person(angle track)`, `.crosstalk` or `.nobody`. A step is speech
    /// when the shared microphone covers it at v ≥ `voice_threshold`; the face speakers' angles
    /// contest it front first.
    static func faceLabels(_ input: Input) -> [Label] {
        let step = stepTicks
        let count = step > 0 ? Int(max(0, input.to - input.from) / step) : 0
        let nobody = [Label](repeating: .nobody, count: count)
        let speakers = faceSpeakers(input.pairing)
        guard let micTrack = speakers.first?.mic,
            let mic = input.microphones.first(where: { $0.track == micTrack }),
            mic.voice.count == count, mic.covered.count == count
        else { return nobody }
        let order = input.angles.map(\.track)
        let contest = speakers.compactMap(\.angle)
            .sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        let series: [(UInt32, [Double?])] = contest.map { angle in
            let read = input.faces.first { $0.track == angle }?.activity ?? []
            return (angle, read.count == count ? read : [Double?](repeating: nil, count: count))
        }
        let threshold = input.settings.voiceThreshold
        return (0..<count).map { k in
            FaceActivity.label(
                speech: mic.covered[k] && mic.voice[k] >= threshold,
                activities: series.map { (angle: $0.0, activity: $0.1[k]) },
                ratio: input.settings.faceRatio, floor: input.settings.faceFloor)
        }
    }

    /// An angle clip as the faces series reads it: its span, its times, its media's sample grid
    /// and duration, and the media's activity per grid index.
    struct FaceClip {
        let span: Span
        let times: AnalysisClipTimes
        let grid: AnalysisGrid
        let duration: Ticks
        let activity: [Double?]
    }

    /// Step k's activity: the sample nearest the forward source tick of the step's midpoint,
    /// through the covering clip (the later-starting where two cover); nil off every clip or
    /// outside the media's 0…duration.
    static func faceSeries(_ clips: [FaceClip], from: Ticks, count: Int) -> [Double?] {
        let step = stepTicks
        return (0..<max(0, count)).map { k -> Double? in
            let mid = from + Ticks(k) * step + step / 2
            var covering: FaceClip?
            for clip in clips where clip.span.start <= mid && mid < clip.span.end {
                if covering.map({ clip.span.start >= $0.span.start }) ?? true { covering = clip }
            }
            guard let clip = covering else { return nil }
            let source = clip.times.source(atClip: mid - clip.span.start)
            guard source >= 0, source <= clip.duration else { return nil }
            let index = clip.grid.index(of: source)
            return index < clip.activity.count ? clip.activity[index] : nil
        }
    }

    // MARK: - The store (SW-84)

    /// A face speaker's angle clip of moving-video media crossing the range, and the window of
    /// its media the faces series needs: the part inside the range in source ticks, widened by
    /// half the activity window and clamped to 0…duration.
    struct FaceWindow {
        let track: UInt32
        let span: Span
        let media: MediaSnapshot
        let times: AnalysisClipTimes
        let window: ClosedRange<Ticks>
    }

    static func faceWindows(
        in project: ReelProject, angles: [AngleTrack], pairing: Pairing, from: Ticks, to: Ticks
    ) -> [FaceWindow] {
        let snapshot = project.snapshot
        let wanted = Set(faceSpeakers(pairing).compactMap(\.angle))
        let half = Ticks((FaceActivity.window / 2 * Double(ReelTime.perSecond)).rounded())
        var out: [FaceWindow] = []
        for angle in angles where wanted.contains(angle.track) {
            for span in angle.clips where span.end > from && span.start < to {
                guard let clip = snapshot.clip(span.clip), let media = snapshot.media(for: clip),
                    media.kind == .video, media.hasVideo
                else { continue }
                let times = AnalysisClipTimes(clip: clip, media: media, map: project.sourceMap(clip.id))
                let a = times.source(atClip: max(span.start, from) - span.start)
                let b = times.source(atClip: min(span.end, to) - span.start)
                let low = max(0, min(a, b) - half)
                let high = min(media.duration, max(a, b) + half)
                guard high > low else { continue }
                out.append(FaceWindow(
                    track: angle.track, span: span, media: media, times: times, window: low...high))
            }
        }
        return out
    }

    /// The media's activity per grid index from the cached samples: each index the marker covers
    /// has the opening of its sample, the rest none.
    static func storedActivity(_ media: MediaSnapshot, grid: AnalysisGrid, cacheDir: URL)
        -> [Double?]
    {
        var openings = [Double?](repeating: nil, count: grid.count)
        if let marker = AnalysisStore.readMarker(.faces, media: media.id, in: cacheDir),
            let file = marker.files.first,
            let data = AnalysisStore.readPayload(.faces, media: media.id, file: file, in: cacheDir),
            let decoded = AnalysisFaces.decode(data), decoded.count == grid.count
        {
            for range in marker.ranges {
                // A range past the grid's last index covers none of it (#456).
                let lo = max(0, range.lowerBound), hi = min(grid.lastIndex, range.upperBound)
                guard lo <= hi else { continue }
                for k in lo...hi {
                    openings[k] = FaceActivity.opening(decoded.samples[k])
                }
            }
        }
        let rate = grid.rate * Double(ReelTime.perSecond)
        return FaceActivity.activities(openings, half: FaceActivity.halfWidth(rate: rate))
    }

    /// Each face speaker's angle, front first, on the range's grid, and the "still being
    /// analysed" problem for an angle any of whose windows the store does not answer (read as
    /// `[]`). Main thread.
    static func readFaces(
        from document: ProjectDocument, angles: [AngleTrack], pairing: Pairing, from: Ticks,
        count: Int
    ) -> (faces: [FaceAngle], problems: [String]) {
        let to = from + Ticks(max(0, count)) * stepTicks
        let windows = faceWindows(
            in: document.editedProject, angles: angles, pairing: pairing, from: from, to: to)
        let wanted = Set(faceSpeakers(pairing).compactMap(\.angle))
        var activity: [UInt32: [Double?]] = [:]
        var faces: [FaceAngle] = []
        var problems: [String] = []
        for angle in angles where wanted.contains(angle.track) {
            var clips: [FaceClip] = []
            var pending = false
            for window in windows where window.track == angle.track {
                let missed: Bool
                do {
                    missed = try document.analysisRequest(
                        kind: .faces, media: window.media, window: window.window) != nil
                } catch {
                    missed = true
                }
                guard !missed, let cacheDir = document.cacheDirectory else {
                    pending = true
                    continue
                }
                let grid = AnalysisKind.faces.grid(of: window.media)
                let stored = activity[window.media.id]
                    ?? storedActivity(window.media, grid: grid, cacheDir: cacheDir)
                activity[window.media.id] = stored
                clips.append(FaceClip(
                    span: window.span, times: window.times, grid: grid,
                    duration: window.media.duration, activity: stored))
            }
            if pending {
                problems.append(
                    "The camera on track \(angle.track) is still being analyzed — its faces have "
                        + "not been found yet. Try again in a moment.")
                faces.append(FaceAngle(track: angle.track, activity: []))
            } else {
                faces.append(FaceAngle(
                    track: angle.track, activity: faceSeries(clips, from: from, count: count)))
            }
        }
        return (faces, problems)
    }

    /// One `faces` request a media still needs, and the first face-speaker angle clip needing it.
    struct FacesWant {
        let track: UInt32
        let clip: UInt32
        let media: MediaSnapshot
        let request: AnalysisRequest
    }

    /// The requests the faces mode still needs, one per media in first-window order, each
    /// media's misses merged (`ShotSplit.wants`' shape); empty in the microphones mode or when
    /// every window is a hit. Main thread; throws `analysisRequest`'s errors.
    static func facesWanted(_ input: Input, in document: ProjectDocument) throws -> [FacesWant] {
        guard mode(input.pairing) == .faces else { return [] }
        let windows = faceWindows(
            in: document.editedProject, angles: input.angles, pairing: input.pairing,
            from: input.from, to: input.to)
        var order: [UInt32] = []
        var misses: [UInt32: [AnalysisRequest]] = [:]
        var first: [UInt32: FaceWindow] = [:]
        for window in windows {
            guard let request = try document.analysisRequest(
                kind: .faces, media: window.media, window: window.window)
            else { continue }
            let id = window.media.id
            if misses[id] == nil {
                order.append(id)
                first[id] = window
            }
            misses[id, default: []].append(request)
        }
        return order.compactMap { id in
            guard let requests = misses[id], let head = requests.first, let window = first[id]
            else { return nil }
            let request = AnalysisRequest(
                kind: head.kind, cacheDir: head.cacheDir, media: head.media, url: head.url,
                stamp: head.stamp, input: head.input,
                ranges: AnalysisStore.merged(requests.flatMap(\.ranges)))
            return FacesWant(
                track: window.track, clip: window.span.clip, media: window.media, request: request)
        }
    }
}

extension AnalysisClipTimes {
    /// The forward source tick at `t` ticks from the clip's start: the inverse of
    /// `clipTime(ofSource:)` (its source map when it ramps, its speed when not, the reversed
    /// mirror last).
    func source(atClip t: Ticks) -> Int64 {
        let played: Int64
        if let map {
            played = Int64(map.source(atClip: Double(t)).rounded())
        } else {
            played = sourceIn + Int64((Double(t) * speed).rounded())
        }
        return pivot.map { ReverseMirror.mirrored(played, about: $0) } ?? played
    }
}
