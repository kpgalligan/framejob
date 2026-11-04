import Foundation

// MARK: - Words into cues

/// The five cue rules, and the ONLY place they live: at most two lines, at
/// most 42 characters a line, at most six seconds a cue, at least a frame
/// between cues, and never two speakers in one cue. Recognised words in,
/// `CaptionLayout.Cue`s out.
///
/// **It is beside `CaptionLayout` and it is not part of it.** `CaptionImporter`
/// must never reach this: a SubRip file supplies its own line breaks and its
/// own cue lengths, and re-wrapping what somebody already wrote would change
/// every caption file that imports correctly today and break the export's
/// round trip. Only a producer that has to INVENT line breaks — the
/// transcriber — calls it. It sits in this file rather than in
/// `Transcriber.swift` because that file is already at the size where the
/// engine is all it should hold, and because everything here is arithmetic
/// over values with no `Speech` in it at all: hand it a word list with times
/// and it is testable with no recogniser, no grant and no machine.
///
/// **The rules are the producer's, so the layout's trim pass never fires on a
/// transcript.** The frame of gap is the point: `CaptionLayout.place` cuts an
/// overlapping cue back to abut its successor, and a transcript that arrived
/// needing that would be a transcript whose captions had been silently
/// retimed. Snapping cannot undo it either — a whole frame subtracted from a
/// time survives being rounded to the frame grid — so a cue built here is a
/// cue that lands.
enum CaptionCues {

    /// One recognised word, already mapped to PROJECT time by whoever
    /// recognised it. `end` is one tick past its last, like every other span
    /// in this app.
    struct Word: Equatable {
        let text: String
        let start: Ticks
        let end: Ticks
        /// Who said it, when the producer knows — AssemblyAI's `speaker`
        /// with `speaker_labels` on (road map 6 §5f). Nil everywhere else,
        /// which is what keeps every existing caller and the harness's
        /// `cues` mode byte-identical to what they were: the fifth rule
        /// compares nil to nil and never fires.
        let speaker: String?

        init(text: String, start: Ticks, end: Ticks, speaker: String? = nil) {
            self.text = text
            self.start = start
            self.end = max(start, end)
            self.speaker = speaker
        }
    }

    /// Two lines is what a viewer reads without looking away from the
    /// picture, and 42 characters is the line length every broadcast caption
    /// guideline lands on; six seconds is about as long as one screenful of
    /// words stays useful. The fifth rule has no constant: a speaker change
    /// is a change, and there is no threshold to tune.
    static let maxLines = 2
    static let maxCharacters = 42
    static let maxLength: Ticks = ReelTime.ticks(seconds: 6)

    /// Words into cues. `frame` is the canvas frame duration — the gap.
    ///
    /// A word too long for a line of its own is left over-long rather than
    /// broken: a hyphen inserted in the middle of a word is a worse caption
    /// than a wide one, and the clip carries `text.width` anyway, so CoreText
    /// soft-wraps it on the canvas. For the same reason the hard `"\n"` this
    /// puts between the two lines is advisory: it is a break CoreText will
    /// honour, inside a box that may add more.
    ///
    /// Each cue carries its words' speaker with `media`, the transcript's
    /// own, so `place` can colour it (spec §11 R6-22).
    static func build(
        from words: [Word], frame: Ticks, clip: UInt32? = nil, media: UInt32? = nil
    ) -> [CaptionLayout.Cue] {
        var raw: [(start: Ticks, end: Ticks, lines: [String], speaker: String?)] = []
        var lines: [String] = []
        var start: Ticks = 0
        var end: Ticks = 0
        var speaker: String?

        func flush() {
            guard !lines.isEmpty else { return }
            raw.append((start, end, lines, speaker))
            lines = []
        }

        for word in words.sorted(by: { $0.start < $1.start }) {
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard !lines.isEmpty else {
                lines = [text]
                start = word.start
                end = word.end
                speaker = word.speaker
                continue
            }
            // The fifth rule (road map 6 §5f): a word whose speaker differs
            // from the open cue's flushes it, so no cue ever carries two
            // voices. It is tested BEFORE placement rather than inside the
            // placement test, because a speaker change that happened to fit
            // the line and the six seconds would otherwise be placed and the
            // rule would never fire. One break, never an empty cue: the flush
            // is followed by opening a new cue on this word, exactly as the
            // length and the line rules do.
            if word.speaker != speaker {
                flush()
                lines = [text]
                start = word.start
                end = word.end
                speaker = word.speaker
                continue
            }
            var placed = false
            // The six-second rule is tested against the word's END, because a
            // cue is on screen until its last word has been said.
            if word.end - start <= maxLength {
                let last = lines[lines.count - 1]
                if last.count + 1 + text.count <= maxCharacters {
                    lines[lines.count - 1] = last + " " + text
                    placed = true
                } else if lines.count < maxLines {
                    lines.append(text)
                    placed = true
                }
            }
            if placed {
                end = max(end, word.end)
            } else {
                flush()
                lines = [text]
                start = word.start
                end = word.end
                speaker = word.speaker
            }
        }
        flush()

        // The gap. A cue ends a frame before the next one starts, or where its
        // last word ended, whichever is earlier. A pair of cues that starts
        // less than two frames apart cannot have both — recognised words do
        // not do that, but if one ever did, the cue is left short and
        // `CaptionLayout.place` reports and drops it by the rule it already
        // has, rather than being silently dropped here.
        for index in raw.indices.dropLast() {
            raw[index].end = min(raw[index].end, raw[index + 1].start - frame)
        }

        return raw.map { entry in
            CaptionLayout.Cue(
                start: entry.start, end: entry.end, text: entry.lines.joined(separator: "\n"),
                tag: tag(at: entry.start, clip: clip),
                speaker: entry.speaker.map { CaptionLayout.Speaker(media: media, label: $0) })
        }
    }

    /// How a cue names itself in a problem message. A transcript has no line
    /// numbers, so it says where in the timeline it came from and, when the
    /// producer knew, which clip.
    private static func tag(at start: Ticks, clip: UInt32?) -> String {
        let when = String(format: "%.1f s", ReelTime.seconds(start))
        guard let clip = clip else { return "caption at \(when)" }
        return "clip \(clip) at \(when)"
    }
}
