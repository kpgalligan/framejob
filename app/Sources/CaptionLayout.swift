import Foundation

/// Cues in, ops out — the half of caption import that has nothing to do with
/// SubRip, factored out of `CaptionImporter.swift` so the speech recogniser
/// (`Transcriber.swift`) lays its captions out exactly as an imported file's
/// are laid out. A caption is an ordinary text clip either way, and
/// `CaptionImporter`'s header doc is still where the reasoning for THAT lives.
///
/// **What is here is PLACEMENT, and only placement.** Road map 2 phase 4 says
/// the cue rules — at most two lines, at most 42 characters a line, at most
/// six seconds a cue, at least a frame between cues, and (road map 6 §5f) no
/// two speakers in one cue: five of them now — are "factored out
/// of `CaptionImporter.swift`". None of them was ever in that file: SubRip
/// supplies its own line breaks, the clip's `text.width` does the wrapping at
/// render time (`LayerRenderers.measure`), and the importer bounds no cue's
/// length. Moving those rules in here would silently re-wrap and re-time every
/// caption file people already import, and would break the 4b round trip
/// outright. So the five rules belong to the producer that has to invent line
/// breaks — the transcriber's cue builder — and this file does what the
/// importer actually did:
///
/// 1. snap each cue to the canvas frame grid (spec §5.1: the model never
///    stores a sub-frame time);
/// 2. give a cue that snapped to nothing its one frame back;
/// 3. sort by start, ties broken by the order the producer emitted them;
/// 4. cut an overlapping cue back to **abut** its successor — never to leave a
///    gap, because `b.start == a.end` is not an overlap (`transition.rs`), so
///    an abutting pair places cleanly and mints no `cross_dissolve`, while a
///    real overlap would both be refused by §6's rule and dissolve between two
///    captions if it were not;
/// 5. drop — and REPORT — whatever is then shorter than a frame;
/// 6. put the survivors on a new front-most track, which is the one placement
///    the overlap rule can never refuse, in the Caption preset.
///
/// **Problems are reported, never dropped.** A caption run half of which
/// vanished without a word is worse than one that did not happen, so every
/// refusal keeps the `tag` its producer gave it — `"line 12"` for a file,
/// `"clip 7"` or a timecode for a transcript — and `Problem.description` is
/// `"<tag>: <reason>"`, which is what `import_captions` already reports under
/// `skipped`.
enum CaptionLayout {

    // MARK: - Vocabulary

    /// One cue as its producer means it, before the frame grid and before its
    /// neighbours have had their say.
    ///
    /// `tag` replaces the SubRip-only line number the importer used to carry:
    /// it is whatever names this cue in a message, and it is the producer's to
    /// spell, so a parser says `"line 12"` and a transcript says `"clip 7 at
    /// 0:04.2"`. Nothing here parses it.
    struct Cue: Equatable {
        let start: Ticks
        let end: Ticks
        let text: String
        let tag: String

        init(start: Ticks, end: Ticks, text: String, tag: String) {
            self.start = start
            self.end = end
            self.text = text
            self.tag = tag
        }
    }

    /// A cue its producer refused, or one placement gave up on.
    struct Problem: Equatable {
        let tag: String
        let reason: String

        var description: String { "\(tag): \(reason)" }
    }

    /// What a caption run will do, before anything is applied: the ops, and
    /// everything the caller has to tell the user about.
    struct Plan {
        /// One `add_track` (unless placing on an existing track), one
        /// `add_text_clip` per surviving cue, and one `set_video` putting the
        /// whole batch where the Caption preset lives.
        let ops: [ReelOp]
        /// Clips this plan really creates — smaller than `cues` if the core
        /// refused a placement on a track the caller chose.
        let clips: Int
        /// Cues that survived the producer and placement.
        let cues: Int
        /// Cues shortened because the next one started before they ended.
        let trimmed: Int
        let problems: [Problem]
        /// The name of the track created for these captions; nil when the
        /// caller named a track to place them on instead.
        let trackName: String?

        /// The human report: what was adjusted and what was skipped. Empty
        /// when everything landed cleanly, which is the signal to say nothing
        /// at all.
        var report: String {
            var lines: [String] = []
            if trimmed > 0 {
                lines.append(
                    "\(trimmed) caption\(trimmed == 1 ? "" : "s") overlapped the next one and "
                        + "\(trimmed == 1 ? "was" : "were") shortened to fit.")
            }
            if !problems.isEmpty {
                lines.append(
                    "\(problems.count) entr\(problems.count == 1 ? "y was" : "ies were") "
                        + "skipped:")
                lines.append(contentsOf: problems.prefix(8).map { "    • " + $0.description })
                if problems.count > 8 {
                    lines.append("    • …and \(problems.count - 8) more.")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Why a placement produced nothing. These carry no file, because the
    /// producer is not always a file: `CaptionImporter` catches them and
    /// rewraps the first two into its own URL-carrying cases so the alert
    /// text and the tool's error string are unchanged.
    enum LayoutError: LocalizedError, Equatable {
        /// Nothing survived. The problems are carried so the message can name
        /// the first few reasons.
        case noCues([Problem])
        /// The core refused the whole batch — an `add_text_clip` onto a track
        /// the caller named, in practice.
        case refused
        /// More captions than the project has room for. Refused HERE rather
        /// than left to `format::check_caps`, which would throw
        /// "too many clips: 4097 (max 4096)" halfway through the batch — a
        /// true sentence that tells a user nothing about captions, when the
        /// count is a fact this plan knows before it builds a single op.
        case tooMany(cues: Int, room: Int)

        var errorDescription: String? {
            switch self {
            case .noCues(let problems):
                let detail = problems.prefix(3).map { $0.description }.joined(separator: "; ")
                return "No captions could be placed on the timeline."
                    + (detail.isEmpty ? "" : " \(detail).")
            case .refused:
                return "The captions could not be placed on the timeline."
            case .tooMany(let cues, let room):
                return "\(cues) captions is more than this project has room for: "
                    + "\(room) more clip\(room == 1 ? "" : "s") would fit, out of "
                    + "\(Int(RC_MAX_CLIPS))."
            }
        }
    }

    // MARK: - Style

    /// The Caption preset of §4.2 — the same row the Text pane's Presets
    /// section applies, looked up by name so the two cannot drift. The
    /// fallback is that row's own values, and exists only so a rename in
    /// `TextPane` is a wrong style rather than a crash.
    static var captionPreset: TextPreset {
        TextPreset.all.first { $0.name == "Caption" }
            ?? TextPreset(
                name: "Caption", font: "SourceSans3-Regular", sizeFraction: 0.035, xFraction: 0,
                yFraction: 0.38, align: "center",
                backdrop: BackdropProps(color: [0, 0, 0, 0.6], padding: 12, radius: 8))
    }

    /// How much of the canvas width a caption may fill before it wraps.
    /// Unlike the Text pane's presets this plan DOES fix a box width: a
    /// caption's words come out of a file or a microphone rather than from
    /// someone watching the canvas, so a long line has to wrap itself.
    static let wrapFraction = 0.8

    // MARK: - Placement

    /// A cue once the frame grid and its neighbours have had their say.
    private struct Placed {
        let tag: String
        /// The cue's index in the input, which is how a tie on `start` is
        /// broken. The importer used to break it on the SubRip line number;
        /// a parser emits its cues in file order and line numbers strictly
        /// increase, so the two orders are the same one — and this one also
        /// works for a producer whose tags are not numbers at all.
        let order: Int
        let start: Ticks
        var end: Ticks
        let text: String
    }

    /// Everything a caption run will do, computed against `project` and
    /// applied by nobody: the UI commits it through `ProjectDocument`, the
    /// agent through `AgentServer.editResult`.
    ///
    /// `existing` is whatever the producer already refused — a malformed SubRip
    /// block, an ineligible clip — and rides along so one report carries both
    /// halves.
    ///
    /// `track` places on an existing track; absent, the captions get a new
    /// front-most track of their own, which is the only placement that can
    /// never be refused by the overlap rule.
    static func place(
        _ cues: [Cue], problems existing: [Problem] = [], in project: ReelProject,
        track: UInt32? = nil, trackBase: String = "Captions"
    ) throws -> Plan {
        let snapshot = project.snapshot
        let canvas = snapshot.canvas
        let frame = max(canvas.fps.frameDuration, 1)
        guard !cues.isEmpty else { throw LayoutError.noCues(existing) }

        // Snap, then give a cue that snapped to nothing its one frame back,
        // THEN resolve overlaps — in that order, so an overlap the minimum
        // length introduces is still one the overlap pass fixes.
        var placed = cues.enumerated().map { index, cue -> Placed in
            let start = ReelTime.snapToFrame(max(0, cue.start), fps: canvas.fps)
            let end = ReelTime.snapToFrame(cue.end, fps: canvas.fps)
            return Placed(
                tag: cue.tag, order: index, start: start, end: max(end, start + frame),
                text: cue.text)
        }
        placed.sort { $0.start == $1.start ? $0.order < $1.order : $0.start < $1.start }

        // Captions are one track, so two cues on screen at once cannot both
        // be honoured: the later one wins its start and the earlier one is
        // cut back to it. That is also what the overlap rule (§6) would
        // otherwise refuse the placement over.
        var trimmed = 0
        for index in placed.indices.dropLast() where placed[index].end > placed[index + 1].start {
            placed[index].end = placed[index + 1].start
            trimmed += 1
        }
        var problems = existing
        for cue in placed where cue.end - cue.start < frame {
            problems.append(
                Problem(tag: cue.tag, reason: "starts less than a frame before the next caption"))
        }
        let kept = placed.filter { $0.end - $0.start >= frame }
        guard !kept.isEmpty else { throw LayoutError.noCues(problems) }

        // Before a single op: every op runs `Project::validate`, so a
        // transcript one clip too long would throw about clips, halfway
        // through, with the earlier ones already applied purely and thrown
        // away. The count is known here.
        let room = Int(RC_MAX_CLIPS) - snapshot.clips.count
        guard kept.count <= room else {
            throw LayoutError.tooMany(cues: kept.count, room: max(0, room))
        }

        var ops: [ReelOp] = []
        let destination: UInt32
        let name = trackName(in: snapshot, base: trackBase)
        if let track = track {
            destination = track
        } else {
            // A new id is `next_id` from BEFORE the op — the documented
            // contract of the one JSON entry point (§6), since an op returns
            // a project rather than an id. Index `tracks.count` is the front
            // of the stack, so captions draw over everything.
            destination = snapshot.nextId
            ops.append(.addTrack(index: snapshot.tracks.count, name: name))
        }

        let preset = captionPreset
        let height = Double(canvas.height)
        var base = TextPatch(
            font: preset.font, size: (height * preset.sizeFraction).rounded(),
            align: preset.align, valign: "middle", backdrop: .some(preset.backdrop),
            width: .some(Double(canvas.width) * wrapFraction))
        for cue in kept {
            base.content = cue.text
            ops.append(
                .addTextClip(
                    track: destination, at: cue.start, duration: cue.end - cue.start, text: base))
        }

        // The preset's position is a `set_video` patch, and a patch needs
        // ids the ops have not minted yet — so the batch is applied PURELY
        // first and the ids read off the throwaway result. Applying the same
        // ops to the same handle mints the same ids, which is what makes
        // appending the patch to this very list correct
        // (`EditorViewController+AddClips.swift` does the same for one clip).
        //
        // The probe is kept rather than replaced by arithmetic on `next_id`:
        // ids ARE sequential when nothing is refused, and that is exactly the
        // invariant a refusal breaks — a caller-named track can refuse any
        // number of these placements, and then the patch would name clips
        // that do not exist.
        guard let probed = try project.applying(ops).project else { throw LayoutError.refused }
        let before = Set(snapshot.clips.map { $0.id })
        let created = probed.snapshot.clips.map { $0.id }.filter { !before.contains($0) }
        guard !created.isEmpty else { throw LayoutError.refused }
        ops.append(
            .setVideo(
                clips: created,
                patch: VideoPatch(
                    x: preset.xFraction * Double(canvas.width), y: preset.yFraction * height,
                    opacity: 1)))

        return Plan(
            ops: ops, clips: created.count, cues: kept.count, trimmed: trimmed,
            problems: problems, trackName: track == nil ? name : nil)
    }

    /// "Captions", then "Captions 2" — so two runs are tellable apart in the
    /// track header. `base` is the producer's word for what it made, and both
    /// producers say "Captions": a transcript and an imported file are the
    /// same thing on the timeline, and a second name would only make the
    /// numbering restart.
    static func trackName(in snapshot: ProjectSnapshot, base: String = "Captions") -> String {
        let taken = Set(snapshot.tracks.map { $0.name })
        var name = base
        var suffix = 2
        while taken.contains(name) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        return name
    }
}

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
    static func build(
        from words: [Word], frame: Ticks, clip: UInt32? = nil
    ) -> [CaptionLayout.Cue] {
        var raw: [(start: Ticks, end: Ticks, lines: [String])] = []
        var lines: [String] = []
        var start: Ticks = 0
        var end: Ticks = 0
        var speaker: String?

        func flush() {
            guard !lines.isEmpty else { return }
            raw.append((start, end, lines))
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
                tag: tag(at: entry.start, clip: clip))
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
