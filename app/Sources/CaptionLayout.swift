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
    ///
    /// The last three are a word caption's page (road map 8's W4a) and nil
    /// from every other producer: `words`, one per whitespace token of
    /// `text` in TIMELINE ticks; `size`, a lone word's shrunk font size;
    /// `width`, the box a lone word too wide even at the floor wraps in.
    /// `speaker` is nil from every producer but `CaptionCues.build`, and a
    /// Subtitles cue that carries one is placed in its palette colour
    /// (spec §11 R6-22).
    struct Cue: Equatable {
        let start: Ticks
        let end: Ticks
        let text: String
        let tag: String
        let words: [CaptionCues.Word]?
        let size: Double?
        let width: Double?
        let speaker: Speaker?

        init(
            start: Ticks, end: Ticks, text: String, tag: String,
            words: [CaptionCues.Word]? = nil, size: Double? = nil, width: Double? = nil,
            speaker: Speaker? = nil
        ) {
            self.start = start
            self.end = end
            self.text = text
            self.tag = tag
            self.words = words
            self.size = size
            self.width = width
            self.speaker = speaker
        }
    }

    /// Who said a cue: a label within ONE media's transcript (R6-3), since
    /// AssemblyAI letters each file's speakers afresh (spec §11 R6-22).
    struct Speaker: Hashable {
        let media: UInt32?
        let label: String
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
        /// The caption tracks this plan removes, with their clips, before
        /// it adds its own — the restyle step (road map 8 §5e). Empty
        /// unless the caller asked for it.
        let replaced: [UInt32]
        /// Subtitles cues that measure over two lines on a canvas taller than wide (spec §11
        /// VR-41); 0 on every other canvas and for every word style.
        let overTwoLines: Int

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
            if overTwoLines > 0 {
                lines.append(
                    "\(overTwoLines) caption\(overTwoLines == 1 ? " wraps" : "s wrap") to more "
                        + "than two lines on this canvas.")
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
                backdrop: BackdropProps(color: [0, 0, 0, 0.6], padding: 12, radius: 8),
                tallYFraction: 0.25)
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
        let words: [CaptionCues.Word]?
        let size: Double?
        let width: Double?
        let speaker: Speaker?
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
    ///
    /// `style` is the caption style (road map 8's W4a). `.subtitles` is the
    /// Caption preset and the code path this function always had, byte for
    /// byte for a cue with no speaker; a speaker's cue adds its palette
    /// `color` (`CaptionStyle.speakerColors`, spec §11 R6-22). A word
    /// style writes `style.pagePatch` per page — the props the pager measured,
    /// at the page's own size (a shrunk one or the style's), with its wrap
    /// width and its `words` in CLIP time — and puts the batch at the style's
    /// `y`, with the run's `looks` (W-15). `replacing` names caption tracks to remove
    /// WITH their clips in the same ops, first — `replaceableTracks` says
    /// which qualify — and the new track takes their place at the front.
    static func place(
        _ cues: [Cue], problems existing: [Problem] = [], in project: ReelProject,
        track: UInt32? = nil, trackBase: String = "Captions", style: CaptionStyle = .subtitles,
        looks: CaptionLooks = .none, replacing: [UInt32] = []
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
                text: cue.text, words: cue.words, size: cue.size, width: cue.width,
                speaker: cue.speaker)
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
        let removed = Set(replacing)
        let room = Int(RC_MAX_CLIPS) - snapshot.clips.filter { !removed.contains($0.track) }.count
        guard kept.count <= room else {
            throw LayoutError.tooMany(cues: kept.count, room: max(0, room))
        }

        // The replaced tracks go FIRST, clips and all: a removal mints no
        // id, so `next_id` below is still the new track's, and the new
        // track's index counts the stack as it will be once they are gone.
        var ops: [ReelOp] = replacing.map { .removeTrack(track: $0, withClips: true) }
        let destination: UInt32
        let name = trackName(in: snapshot, base: trackBase, excluding: replacing)
        if let track = track {
            destination = track
        } else {
            // A new id is `next_id` from BEFORE the op — the documented
            // contract of the one JSON entry point (§6), since an op returns
            // a project rather than an id. Index `tracks.count` is the front
            // of the stack, so captions draw over everything.
            destination = snapshot.nextId
            ops.append(.addTrack(index: snapshot.tracks.count - replacing.count, name: name))
        }

        let preset = captionPreset
        let height = Double(canvas.height)
        let size = CGSize(width: canvas.width, height: canvas.height)
        var overTwoLines = 0
        if style.isWordStyle {
            let base = style.size(for: CGSize(width: canvas.width, height: canvas.height))
            for cue in kept {
                let words = cue.words.map { words in
                    words.map { TextWord(start: $0.start - cue.start, end: $0.end - cue.start) }
                }
                ops.append(
                    .addTextClip(
                        track: destination, at: cue.start, duration: cue.end - cue.start,
                        text: style.pagePatch(
                            content: cue.text, size: cue.size ?? base, width: cue.width,
                            words: words, looks: looks)))
            }
        } else {
            var base = TextPatch(
                font: preset.font, size: preset.size(on: size),
                align: preset.align, valign: "middle", backdrop: .some(preset.backdrop),
                width: .some(Double(canvas.width) * wrapFraction))
            if canvas.height > canvas.width {
                overTwoLines = kept.filter { measuresOverTwoLines($0.text, preset, on: size) }
                    .count
            }
            let colors = CaptionStyle.speakerColors(kept.map(\.speaker))
            for (cue, color) in zip(kept, colors) {
                base.content = cue.text
                base.color = color
                ops.append(
                    .addTextClip(
                        track: destination, at: cue.start, duration: cue.end - cue.start,
                        text: base))
            }
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
        let at = preset.position(on: size)
        ops.append(
            .setVideo(
                clips: created,
                patch: style.isWordStyle
                    ? VideoPatch(x: 0, y: style.yFraction * height)
                    : VideoPatch(x: at.x, y: at.y, opacity: 1)))

        return Plan(
            ops: ops, clips: created.count, cues: kept.count, trimmed: trimmed,
            problems: problems, trackName: track == nil ? name : nil, replaced: replacing,
            overTwoLines: overTwoLines)
    }

    /// Whether a Subtitles cue, as `place` writes it on `canvas` (the Caption preset, its
    /// wrap box), measures taller than the same props holding two lines (spec §11 VR-41).
    static func measuresOverTwoLines(
        _ content: String, _ preset: TextPreset, on canvas: CGSize
    ) -> Bool {
        func props(_ text: String) -> TextProps {
            TextProps(
                content: text, font: preset.font, size: preset.size(on: canvas),
                align: preset.align, valign: "middle", backdrop: preset.backdrop,
                width: Double(canvas.width) * wrapFraction)
        }
        return LayerRenderers.measuredSize(for: props(content)).height
            > LayerRenderers.measuredSize(for: props("X\nX")).height
    }

    /// The tracks a restyle may replace (road map 8 §5e's three rules): a
    /// track named as this file names caption tracks ("Captions",
    /// "Captions N"), holding at least one clip and only text clips, each overlapping
    /// some job's `span` — so nothing outside the run's scope is removed.
    static func replaceableTracks(
        in snapshot: ProjectSnapshot, jobs: [Transcriber.Job]
    ) -> [UInt32] {
        snapshot.tracks.compactMap { track -> UInt32? in
            guard isCaptionTrackName(track.name) else { return nil }
            guard snapshot.clips.contains(where: { $0.track == track.id }) else { return nil }
            for clip in snapshot.clips where clip.track == track.id {
                guard case .text = clip.source else { return nil }
                let end = clip.start + clip.duration
                guard jobs.contains(where: { $0.span.overlaps(clip.start ..< end) }) else {
                    return nil
                }
            }
            return track.id
        }
    }

    /// A name this file gives a caption track: "Captions" or "Captions N".
    static func isCaptionTrackName(_ name: String) -> Bool {
        if name == "Captions" { return true }
        guard name.hasPrefix("Captions ") else { return false }
        let suffix = name.dropFirst("Captions ".count)
        return !suffix.isEmpty && suffix.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "Captions", then "Captions 2" — so two runs are tellable apart in the
    /// track header. `base` is the producer's word for what it made, and both
    /// producers say "Captions": a transcript and an imported file are the
    /// same thing on the timeline, and a second name would only make the
    /// numbering restart.
    /// A track in `excluding` is one this plan removes, so its name is free.
    static func trackName(
        in snapshot: ProjectSnapshot, base: String = "Captions", excluding: [UInt32] = []
    ) -> String {
        let taken = Set(snapshot.tracks.filter { !excluding.contains($0.id) }.map { $0.name })
        var name = base
        var suffix = 2
        while taken.contains(name) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        return name
    }
}

