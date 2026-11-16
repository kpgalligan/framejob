import Foundation

/// The timeline transcript's two judgements (road map "creator-jobs" TX1):
/// whether a word may be cut (spec §11 TX-11) and whether two clips carry the
/// same speech (TX-10). Pure.
extension TimelineTranscript {

    // MARK: - TX-11: editability

    /// Why cutting a word would break something, or nil when it may be cut.
    /// The first rule that applies: inside a nest (naming the OUTERMOST
    /// enclosing nest); near an overlap between two clips (the word's [start, max(end,
    /// start + 1)) meets one of the container's `overlapWalls`); on a locked
    /// track (the word's container track). A ramped clip's words are
    /// editable (SR-18 (e)).
    static func whyNotEditable(
        start: Ticks, end: Ticks, nestPath: [UInt32], track: UInt32,
        snapshot: ProjectSnapshot, walls: [SilenceDetector.Span]
    ) -> String? {
        if let outer = nestPath.first {
            return "Inside nest \(nestName(outer, in: snapshot)): open it (⌘↓) to cut its words."
        }
        let wordEnd = max(end, start + 1)
        if walls.contains(where: { $0.start < wordEnd && $0.end > start }) {
            return "Near an overlap between two clips: a cut here would leave one clip's "
                + "tail under the other."
        }
        if let row = snapshot.track(track), row.locked {
            let name = row.name.isEmpty ? "\(row.id)" : row.name
            return "Track \(name) is locked: a cut would leave these words in place and move "
                + "everything after them."
        }
        return nil
    }

    /// The name of the nest a nest clip shows (its id when it has none).
    static func nestName(_ nestClip: UInt32, in snapshot: ProjectSnapshot) -> String {
        guard let clip = snapshot.clip(nestClip), let nest = snapshot.nest(for: clip) else {
            return "\(nestClip)"
        }
        return nest.name.isEmpty ? "\(nest.id)" : nest.name
    }

    // MARK: - TX-10: the same speech twice

    /// The overlap two clips need before their words are compared.
    static let sameSpeechOverlap: Ticks = 3_000_000
    /// The share of the shorter side the common words must reach.
    static let sameSpeechShare = 0.6

    /// The tool's note for each pair, by id: an agent reads ids (TX-10).
    static func sameSpeech(_ words: [Word], instances: [Instance]) -> [String] {
        sameSpeechPairs(words, instances: instances).map { pair in
            "Clips \(pair.a) and \(pair.b) carry the same speech. Mute one, or switch its audio "
                + "off, to read it once."
        }
    }

    /// The Transcript tab's note for each pair, by name with the id beside
    /// it: a person sees names on the timeline and no id (TX-36).
    static func sameSpeechShown(_ words: [Word], instances: [Instance]) -> [String] {
        var names: [UInt32: String] = [:]
        for instance in instances { names[instance.clip.id] = instance.job.name }
        return sameSpeechPairs(words, instances: instances).map { pair in
            "“\(names[pair.a] ?? "")” (clip \(pair.a)) and “\(names[pair.b] ?? "")” "
                + "(clip \(pair.b)) carry the same speech. Mute one, or switch its audio off, to "
                + "read it once."
        }
    }

    /// Each pair of clips of DIFFERENT media whose instances overlap
    /// on the timeline for at least `sameSpeechOverlap` and whose words
    /// starting inside that overlap match: tokens `FillerWords.normalized`,
    /// empties dropped, at least one each side, a longest common subsequence
    /// of at least `sameSpeechShare` × the shorter side. Clip ids ascending.
    /// `words` are the windowed words, before `tracks` and paging.
    static func sameSpeechPairs(
        _ words: [Word], instances: [Instance]
    ) -> [(a: UInt32, b: UInt32)] {
        var spans: [UInt32: [(Ticks, Ticks)]] = [:]
        var mediaOf: [UInt32: UInt32] = [:]
        for instance in instances {
            let start = instance.segment.start
            spans[instance.clip.id, default: []].append((start, start + instance.segment.duration))
            mediaOf[instance.clip.id] = instance.job.media
        }
        var byClip: [UInt32: [Word]] = [:]
        for word in words { byClip[word.clip, default: []].append(word) }
        let ids = byClip.keys.sorted()
        var pairs: [(a: UInt32, b: UInt32)] = []
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] {
                guard let ma = mediaOf[a], let mb = mediaOf[b], ma != mb else { continue }
                var shared: [(Ticks, Ticks)] = []
                for x in spans[a] ?? [] {
                    for y in spans[b] ?? [] {
                        let lo = max(x.0, y.0)
                        let hi = min(x.1, y.1)
                        if hi > lo { shared.append((lo, hi)) }
                    }
                }
                let total = shared.reduce(Ticks(0)) { $0 + ($1.1 - $1.0) }
                guard total >= sameSpeechOverlap else { continue }
                let inside = { (word: Word) in shared.contains { word.start >= $0.0 && word.start < $0.1 } }
                let left = tokens(byClip[a, default: []].filter(inside))
                let right = tokens(byClip[b, default: []].filter(inside))
                let shorter = min(left.count, right.count)
                guard shorter >= 1 else { continue }
                guard Double(commonLength(left, right)) >= sameSpeechShare * Double(shorter) else {
                    continue
                }
                pairs.append((a, b))
            }
        }
        return pairs
    }

    /// Words as TR-8's normalised tokens, empties dropped.
    static func tokens(_ words: [Word]) -> [String] {
        words.map { FillerWords.normalized($0.text) }.filter { !$0.isEmpty }
    }

    /// The longest common subsequence's length, two rows at a time.
    static func commonLength(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = previous
        for x in a {
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
