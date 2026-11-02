import Foundation

/// Where a word's cut falls (road map "creator-jobs" TX3a, spec §11 TX-30):
/// each word's ONSET, from the voice cache, and the range a run of shown
/// words cuts, onset to the next kept word's onset. Pure: it is handed the
/// instances, each media's words and each media's voice cache, and reads no
/// file, no cache and no window. TX-S3 measures `sourceOnsets`.
///
/// **The rules (TX-30, TX-S3).** All in the SOURCE ticks of the word's media,
/// per instance, its words in source order; `lead` is
/// `CaptionPages.lead(for:)` (0 under E0), a word's mid is
/// `(source + max(source, sourceEnd)) / 2 + lead`.
/// - E0: the onset is the transcript's start.
/// - E1: the onset is the start corrected by the lead.
/// - E2: the onset is the END of the latest run of at least
///   `minimumRunCells` non-speech voice cells (probability under
///   `defaultVoiceConfidence`; cell k is `[k·chunk, (k+1)·chunk)`) whose end
///   lies in (the previous word's mid, this word's mid] — the window opening
///   at the instance's `windowStart` for its first word, the run free to
///   begin before it — less the guard G; with no such run or no voice cache,
///   E1.
/// Every onset is then clamped to at least the previous word's corrected end
/// and to at least `windowStart`.
///
/// **A run's cut.** Words are matched to their instance by clip id and nest
/// path, and to their source word by its identity tick in order (TX-17). `Table.cut` of a
/// run of shown tokens is `[min onset, end)`, `end` the least of the next
/// shown word's onset, the run's latest corrected end plus `cap`, and the
/// first start of a shown-track instance whose media has no words that is at
/// or after the run's latest start; with no next shown word, the latest end
/// plus G. Never before its start. Unsnapped: `TranscriptCut+Plan.swift`
/// widens and snaps.
enum TranscriptCut {

    enum Rule: Equatable {
        case e0
        case e1
        case e2(guardTicks: Ticks)

        /// The guard G: 0 unless E2.
        var guardTicks: Ticks {
            if case .e2(let guardTicks) = self { return guardTicks }
            return 0
        }
    }

    /// TX-S3's verdict (spec §11 TX-30): E0, the transcript's own edges —
    /// on the `say` fixture E2 and E1 each clipped 3 of 20 onsets (the clamp
    /// to the previous word's corrected end), E0 none. JOB-11 judges it.
    static let shipped: Rule = .e0
    /// The most of a pause after a cut's last word that the cut takes: 1 s.
    static let cap: Ticks = ReelTime.perSecond
    /// The shortest non-speech run an onset is read from: two 32 ms cells.
    static let minimumRunCells = 2

    struct Context {
        let instances: [TimelineTranscript.Instance]
        let media: [UInt32: TimelineTranscript.MediaWords]
        let speech: [UInt32: [Float]]
    }

    /// One word's edges in TIMELINE ticks: its onset, and its start and end
    /// corrected by the lead.
    struct Edges: Equatable {
        let onset: Ticks
        let start: Ticks
        let end: Ticks
    }

    /// A timeline range, `[start, end)`.
    struct Range: Equatable {
        let start: Ticks
        let end: Ticks
    }

    /// The lead a rule corrects an engine's words by.
    static func lead(_ engine: TranscriptionEngine, rule: Rule) -> Ticks {
        rule == .e0 ? 0 : CaptionPages.lead(for: engine)
    }

    // MARK: - Onsets

    /// One instance's words in source order, its window opening at
    /// `windowStart` (`job.sourceIn`): each word's onset, in source ticks.
    static func sourceOnsets(
        _ words: [TimelineTranscript.SourceWord], windowStart: Ticks, lead: Ticks,
        speech: [Float]?, rule: Rule
    ) -> [Ticks] {
        var out: [Ticks] = []
        out.reserveCapacity(words.count)
        var previousMid = windowStart
        var previousEnd: Ticks?
        for word in words {
            let end = max(word.source, word.sourceEnd)
            let mid = (word.source + end) / 2 + lead
            var onset = word.source + lead
            if case .e2(let guardTicks) = rule, let speech,
                let runEnd = latestRunEnd(speech, after: previousMid, upTo: mid)
            {
                onset = runEnd - guardTicks
            }
            if let previousEnd { onset = max(onset, previousEnd) }
            out.append(max(onset, windowStart))
            previousMid = mid
            previousEnd = end + lead
        }
        return out
    }

    /// The end, in source ticks, of the latest run of at least
    /// `minimumRunCells` non-speech cells whose end lies in (`lower`,
    /// `upper`]; nil when there is none. A run ends where a speech cell, or
    /// the cache's end, follows it.
    static func latestRunEnd(_ speech: [Float], after lower: Ticks, upTo upper: Ticks) -> Ticks? {
        let chunk = MediaSpeech.chunkTicks
        let threshold = Float(SilenceDetector.Settings.defaultVoiceConfidence)
        let high = min(floorDivide(upper, chunk), speech.count)
        let low = max(floorDivide(lower, chunk) + 1, minimumRunCells)
        guard high >= low else { return nil }
        var boundary = high
        while boundary >= low {
            let endsHere = boundary == speech.count || speech[boundary] >= threshold
            if endsHere, (1...minimumRunCells).allSatisfy({ speech[boundary - $0] < threshold }) {
                return Ticks(boundary) * chunk
            }
            boundary -= 1
        }
        return nil
    }

    private static func floorDivide(_ a: Ticks, _ b: Ticks) -> Int {
        Int(a >= 0 ? a / b : -((-a + b - 1) / b))
    }

    // MARK: - Edges

    /// Each word's edges, in the order given (TX-10's). A word whose
    /// instance or source word is not in `context` keeps its own start and
    /// end, its onset its start.
    static func edges(
        _ words: [TimelineTranscript.Word], context: Context, rule: Rule
    ) -> [Edges] {
        struct Key: Hashable {
            let clip: UInt32
            let nestPath: [UInt32]
        }
        struct Prepared {
            let words: [TimelineTranscript.SourceWord]
            let onsets: [Ticks]
            let bySource: [Ticks: [Int]]
            let lead: Ticks
        }
        var byKey: [Key: [Int]] = [:]
        for (index, instance) in context.instances.enumerated() {
            let key = Key(clip: instance.clip.id, nestPath: Array(instance.segment.path.dropLast()))
            byKey[key, default: []].append(index)
        }
        var prepared: [Int: Prepared] = [:]
        var used: [Int: [Ticks: Int]] = [:]
        func prepare(_ number: Int) -> Prepared? {
            if let done = prepared[number] { return done }
            let instance = context.instances[number]
            let job = instance.job
            guard let heard = context.media[job.media] else { return nil }
            let windowEnd = job.sourceIn + job.sourceLength
            let words = heard.words.filter { $0.source >= job.sourceIn && $0.source < windowEnd }
            let lead = lead(heard.engine, rule: rule)
            let onsets = sourceOnsets(
                words, windowStart: job.sourceIn, lead: lead, speech: context.speech[job.media],
                rule: rule)
            var bySource: [Ticks: [Int]] = [:]
            for (index, word) in words.enumerated() {
                bySource[word.identityTick, default: []].append(index)  // TX-17
            }
            let made = Prepared(words: words, onsets: onsets, bySource: bySource, lead: lead)
            prepared[number] = made
            return made
        }
        return words.map { word in
            let own = Edges(onset: word.start, start: word.start, end: word.end)
            let candidates = byKey[Key(clip: word.clip, nestPath: word.id.nestPath)] ?? []
            guard
                let number = candidates.first(where: {
                    let segment = context.instances[$0].segment
                    return segment.start <= word.start && word.start < segment.start + segment.duration
                }) ?? candidates.first,
                let made = prepare(number), let matches = made.bySource[word.id.source]
            else { return own }
            let taken = used[number, default: [:]][word.id.source, default: 0]
            used[number, default: [:]][word.id.source] = taken + 1
            let index = matches[min(taken, matches.count - 1)]
            let instance = context.instances[number]
            let shift = instance.segment.origin.map { $0 - instance.clip.start } ?? 0
            func place(_ source: Ticks) -> Ticks {
                MediaTranscript.project(source, in: instance.job) + shift
            }
            let source = made.words[index]
            return Edges(
                onset: place(made.onsets[index]), start: place(source.source + made.lead),
                end: place(max(source.source, source.sourceEnd) + made.lead))
        }
    }

    // MARK: - The shown words

    /// The words a cut is planned over: every read word with its edges, the
    /// shown ones (Words from's tracks), and the starts of shown-track
    /// instances whose media has no words yet.
    struct Table {
        let all: [TimelineTranscript.Word]
        let allEdges: [Edges]
        /// Indices into `all`; shown order is `TranscriptTokens`' token order.
        let shown: [Int]
        /// Sorted segment starts of shown-track instances whose media has no
        /// words in the context.
        let unread: [Ticks]
        let rule: Rule
        /// Over shown order: the latest extent end at or before each token,
        /// and the earliest onset at or after it — the bounds a widening's
        /// scan stops at.
        let reachBefore: [Ticks]
        let onsetAfter: [Ticks]

        init(
            all: [TimelineTranscript.Word], tracks: Set<UInt32>?, context: Context,
            rule: Rule = TranscriptCut.shipped
        ) {
            self.all = all
            self.rule = rule
            let edges = TranscriptCut.edges(all, context: context, rule: rule)
            allEdges = edges
            let shown = all.indices.filter { tracks?.contains(all[$0].track) ?? true }
            self.shown = shown
            unread = context.instances
                .filter { (tracks?.contains($0.track) ?? true) && context.media[$0.job.media] == nil }
                .map(\.segment.start).sorted()
            var before: [Ticks] = []
            before.reserveCapacity(shown.count)
            for index in shown {
                let reach = max(edges[index].end, edges[index].onset + 1)
                before.append(max(before.last ?? reach, reach))
            }
            reachBefore = before
            var after = [Ticks](repeating: 0, count: shown.count)
            var least = Ticks.max
            for token in shown.indices.reversed() {
                least = min(least, edges[shown[token]].onset)
                after[token] = least
            }
            onsetAfter = after
        }

        /// The word and edges of shown token `token`.
        func word(_ token: Int) -> TimelineTranscript.Word { all[shown[token]] }
        func edges(_ token: Int) -> Edges { allEdges[shown[token]] }

        /// The cut of shown tokens `selection`, unsnapped (TX-30).
        func cut(_ selection: ClosedRange<Int>) -> Range {
            var start = Ticks.max
            var latestEnd = Ticks.min
            var latestStart = Ticks.min
            for token in selection {
                let e = edges(token)
                start = min(start, e.onset)
                latestEnd = max(latestEnd, e.end)
                latestStart = max(latestStart, e.start)
            }
            var end: Ticks
            if selection.upperBound + 1 < shown.count {
                end = min(edges(selection.upperBound + 1).onset, latestEnd + TranscriptCut.cap)
            } else {
                end = latestEnd + rule.guardTicks
            }
            if let wall = unread.first(where: { $0 >= latestStart }) { end = min(end, wall) }
            return Range(start: start, end: max(end, start))
        }

        /// One token's run of one, unwidened: `cut(token...token)`.
        func own(_ token: Int) -> Range { cut(token...token) }
    }
}
