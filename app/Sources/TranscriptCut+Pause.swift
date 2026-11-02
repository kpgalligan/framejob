import Foundation

/// The pause token (road map "creator-jobs" TX3b, spec §11 TX-34): a silence
/// of more than 1 s between two shown words of one clip, read from the voice
/// cache, and the cut that shortens it to 0.2 s each end. Pure: it reads the
/// cut's `Table` and its `Context`, no file and no window.
///
/// **Detection.** Consecutive shown tokens a and b, both editable, in ONE
/// instance (`edges`' rule: candidates keyed by clip id and nest path, the
/// first whose segment holds the word's start, else the first — so one
/// instance is one clip, one nest path and one media). Their source words
/// are the media's first words whose `identityTick` is the tokens' `id.source`
/// (TX-17: an on-device word's `source` is its moved start). The window opens
/// at a's END, not its start, so one silence makes one pause. In the window,
/// the longest run of non-speech voice cells (the earliest of equal runs) is
/// the silence, extended back over non-speech cells to no earlier than a's
/// start (`quietStart`): a recognised end is not moved (TX-19) and often lies
/// past the phrase's sound, so the run starts where the speech ends.
/// Projected onto the timeline, it is a pause only when longer than
/// `pauseLongerThan` of TIMELINE time.
///
/// **The cut.** The span less `pauseKept` each end, each bound snapped to its
/// nearest frame; when b's start lies inside, the cut starts on the frame
/// after it, so no word's start is cut. Dropped when that leaves nothing, when
/// another shown word's TX-32 extent meets it, or when an unread clip starts
/// inside it: a pause's cut never takes a shown word.
extension TranscriptCut {

    /// A pause is a silence longer than this, in timeline ticks: 1 s.
    static let pauseLongerThan: Ticks = ReelTime.perSecond
    /// What a pause's cut keeps of it at each end, in timeline ticks: 0.2 s.
    static let pauseKept: Ticks = ReelTime.perSecond / 5

    struct Pause: Equatable {
        /// The shown token before it; the token after is `after + 1`.
        let after: Int
        /// The silence, in timeline ticks: the run projected, unsnapped.
        let span: Range
        /// What deleting it cuts, snapped; `cut.end > cut.start`.
        let cut: Range
    }

    struct PausePlan: Equatable {
        let range: Range
        let clipsAfter: Int
        let clipsPeak: Int
        let refusal: Refusal?
    }

    /// Every pause between the table's shown tokens, in ascending `after`.
    static func pauses(_ table: Table, fps: Fps) -> [Pause] {
        guard table.shown.count > 1 else { return [] }
        let context = table.context
        struct Key: Hashable {
            let clip: UInt32
            let nestPath: [UInt32]
        }
        var byKey: [Key: [Int]] = [:]
        for (index, instance) in context.instances.enumerated() {
            byKey[Key(clip: instance.clip.id, nestPath: Array(instance.segment.path.dropLast())), default: []]
                .append(index)
        }
        func instance(of word: TimelineTranscript.Word) -> Int? {
            let candidates = byKey[Key(clip: word.clip, nestPath: word.id.nestPath)] ?? []
            return candidates.first(where: {
                let segment = context.instances[$0].segment
                return segment.start <= word.start && word.start < segment.start + segment.duration
            }) ?? candidates.first
        }
        // Each media's first source word at a source tick, made once.
        var firstAt: [UInt32: [Ticks: Int]] = [:]
        func sourceWord(_ word: TimelineTranscript.Word) -> TimelineTranscript.SourceWord? {
            guard let heard = context.media[word.media] else { return nil }
            if firstAt[word.media] == nil {
                var map: [Ticks: Int] = [:]
                for (index, source) in heard.words.enumerated() {
                    let tick = source.identityTick  // TX-17
                    if map[tick] == nil { map[tick] = index }
                }
                firstAt[word.media] = map
            }
            return firstAt[word.media]?[word.id.source].map { heard.words[$0] }
        }
        var out: [Pause] = []
        for after in 0..<(table.shown.count - 1) {
            let a = table.word(after)
            let b = table.word(after + 1)
            guard a.editable, b.editable,
                let number = instance(of: a), instance(of: b) == number,
                let speech = context.speech[a.media],
                let aw = sourceWord(a), let bw = sourceWord(b)
            else { continue }
            let instance = context.instances[number]
            let job = instance.job
            let low = max(aw.source, aw.sourceEnd, job.sourceIn)
            let high = min(max(bw.source, bw.sourceEnd), job.sourceIn + job.sourceLength)
            guard let run = longestQuietRun(speech, from: low, to: high) else { continue }
            let quiet = quietStart(speech, runStart: run.start, floor: max(aw.source, job.sourceIn))
            let shift = instance.segment.origin.map { $0 - instance.clip.start } ?? 0
            let span = Range(
                start: MediaTranscript.project(quiet, in: job) + shift,
                end: MediaTranscript.project(run.end, in: job) + shift)
            guard span.end - span.start > pauseLongerThan else { continue }
            var s = max(0, ReelTime.snapToFrame(span.start + pauseKept, fps: fps))
            let e = max(0, ReelTime.snapToFrame(span.end - pauseKept, fps: fps))
            if s <= b.start, b.start < e {
                let past = TimelineTranscript.frameFloor(b.start, fps: fps) + max(1, fps.frameDuration)
                s = ReelTime.snapToFrame(past, fps: fps)
            }
            guard e > s else { continue }
            let before = after > 0 && table.reachBefore[after - 1] > s
            let beyond = after + 2 < table.shown.count && table.onsetAfter[after + 2] < e
            if before || beyond { continue }
            if table.unread.contains(where: { s <= $0 && $0 < e }) { continue }
            out.append(Pause(after: after, span: span, cut: Range(start: s, end: e)))
        }
        return out
    }

    /// The longest run of consecutive non-speech cells wholly inside `[low,
    /// high)` of source ticks, the earliest of equal runs, as `[r0, r1)`; nil
    /// when the window holds none.
    static func longestQuietRun(_ speech: [Float], from low: Ticks, to high: Ticks) -> Range? {
        let chunk = MediaSpeech.chunkTicks
        let threshold = Float(SilenceDetector.Settings.defaultVoiceConfidence)
        guard high > low, high > 0 else { return nil }
        let first = Int(max(0, (low + chunk - 1) / chunk))
        let past = min(Int(high / chunk), speech.count)
        guard past > first else { return nil }
        var best: (start: Int, count: Int)?
        var runStart = first
        var count = 0
        for k in first..<past {
            if speech[k] < threshold {
                if count == 0 { runStart = k }
                count += 1
                if count > (best?.count ?? 0) { best = (runStart, count) }
            } else {
                count = 0
            }
        }
        guard let best else { return nil }
        return Range(start: Ticks(best.start) * chunk, end: Ticks(best.start + best.count) * chunk)
    }

    /// Where a quiet run starting at `runStart` (a cell boundary) really
    /// starts: stepped back one cell while the cell before it is non-speech
    /// and starts at or after `floor`, in source ticks.
    static func quietStart(_ speech: [Float], runStart: Ticks, floor: Ticks) -> Ticks {
        let chunk = MediaSpeech.chunkTicks
        let threshold = Float(SilenceDetector.Settings.defaultVoiceConfidence)
        var k = Int(runStart / chunk)
        while k > 0, k - 1 < speech.count, speech[k - 1] < threshold, Ticks(k - 1) * chunk >= floor {
            k -= 1
        }
        return Ticks(k) * chunk
    }

    /// A pause's cut planned: counted, and refused in TX-34's order — a read
    /// word on a locked track (every track) whose corrected extent meets the
    /// cut, then the peak clip count past `ceiling`.
    static func planPause(
        _ pause: Pause, table: Table, container: ProjectSnapshot, total: Int,
        ceiling: Int = Int(RC_MAX_CLIPS)
    ) -> PausePlan {
        let cut = pause.cut
        let after = clipsAfter(cutting: cut, container: container, total: total)
        let peak = clipsPeak(cutting: cut, container: container, total: total)
        var refusal: Refusal?
        if let held = table.all.indices.first(where: { index in
            let e = table.allEdges[index]
            return container.track(table.all[index].track)?.locked == true
                && e.start < cut.end && max(e.end, e.start + 1) > cut.start
        }) {
            let id = table.all[held].track
            let row = container.track(id)
            refusal = .locked(track: row.map { $0.name.isEmpty ? "\($0.id)" : $0.name } ?? "\(id)")
        } else if ceiling < peak {
            refusal = .ceiling(clips: peak)
        }
        return PausePlan(range: cut, clipsAfter: after, clipsPeak: peak, refusal: refusal)
    }
}
