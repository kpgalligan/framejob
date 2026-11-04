import Foundation

/// Word caption pages re-paged from their own words on the current canvas (spec §11 VR-40):
/// what File ▸ Re-lay Captions for This Canvas and `relay_captions` do (VR-45), and step (6) of
/// Make Vertical (`VerticalVersion+Plan.swift`). W-7 and W-10 stand: `CaptionPages.repage` is
/// the measuring pager with lead 0 and `CaptionLayout.place` the one writer, so a re-laid page
/// is built exactly as a generated one is — from the words the pages hold, so every correction
/// is kept (the owner's answer, 2026-11-01).
///
/// `place(replacing:)` removes each replaced track with its clips first, so a track is
/// replaced only when every page on it is recognised: a track holding a page with no timings,
/// or in a style Frame Job does not make, is KEPT and named with its reason. Names no `rc_*`.
enum CaptionRelayout {
    /// The undo step's name (VR-45).
    static let actionName = "Re-lay Captions"

    /// A caption track whose pages are all in one recognised style.
    struct Track: Equatable {
        let track: UInt32
        let name: String
        let style: CaptionStyle
        let looks: CaptionLooks
    }

    /// A caption track left as placed, and why.
    struct Kept: Equatable {
        let track: UInt32
        let name: String
        let reason: String
    }

    /// A track re-laid: the new track's id, the old one's, its name, style and page count.
    struct Relaid: Equatable {
        let track: UInt32
        let replaced: UInt32
        let name: String
        let style: CaptionStyle
        let pages: Int
    }

    /// What the survey found, each list in stack order, back first.
    struct Survey: Equatable {
        let recognised: [Track]
        let kept: [Kept]
    }

    struct Outcome: Equatable {
        var relaid: [Relaid]
        var kept: [Kept]
    }

    /// VR-40 (a): the caption tracks of one container — named as `CaptionLayout` names them,
    /// holding at least one clip and only text clips — each recognised or kept with the first
    /// reason that applies.
    static func survey(_ snapshot: ProjectSnapshot) -> Survey {
        var recognised: [Track] = []
        var kept: [Kept] = []
        for track in snapshot.tracks where CaptionLayout.isCaptionTrackName(track.name) {
            let clips = snapshot.clips(onTrack: track.id)
            guard !clips.isEmpty, clips.allSatisfy(isText) else { continue }
            func keep(_ reason: String) {
                kept.append(Kept(track: track.id, name: track.name, reason: reason))
            }
            if track.matte != .none {
                keep("it is a matte track")
                continue
            }
            let timed = clips.map { Self.words(of: $0) }
            if timed.contains(where: { $0 == nil }) {
                keep("it holds a page with no word timings")
                continue
            }
            if timed.contains(where: { $0?.isEmpty ?? true }) {
                keep("it holds a page none of whose words starts inside it")
                continue
            }
            let styles = clips.map { clip in clip.text.flatMap(recognise) }
            if styles.contains(where: { $0 == nil }) {
                keep("it holds a page in a style Frame Job does not make")
                continue
            }
            guard let first = styles[0],
                styles.allSatisfy({ $0?.style == first.style && $0?.looks == first.looks })
            else {
                keep("its pages are in more than one style")
                continue
            }
            recognised.append(
                Track(track: track.id, name: track.name, style: first.style, looks: first.looks))
        }
        return Survey(recognised: recognised, kept: kept)
    }

    private static func isText(_ clip: ClipSnapshot) -> Bool {
        if case .text = clip.source { return true }
        return false
    }

    /// VR-40 (b): the word style and looks a page was made in — its font the style's and its
    /// `word_style` the style's with those looks — or nil. Subtitles is never a match.
    static func recognise(_ text: TextProps) -> (style: CaptionStyle, looks: CaptionLooks)? {
        for style in CaptionStyle.allCases where style.isWordStyle && text.font == style.font {
            for bits in 0 ..< 8 {
                let looks = CaptionLooks(
                    slide: bits & 1 != 0, fill: bits & 2 != 0, dim: bits & 4 != 0)
                guard looks == looks.live(for: style) else { continue }
                if text.wordStyle == style.wordStyle(looks) { return (style, looks) }
            }
        }
        return nil
    }

    /// VR-40 (c): a page's timed words in TIMELINE ticks, one per whitespace token of
    /// `content`, speaker nil — only those whose start lies inside the clip (a split's or a
    /// trim's half holds the words of the part it lost). Nil for a clip with no text, no
    /// words or a count that differs from the tokens; empty when none starts inside.
    static func words(of clip: ClipSnapshot) -> [CaptionCues.Word]? {
        guard let text = clip.text, !text.words.isEmpty else { return nil }
        let tokens = text.content.split(whereSeparator: \.isWhitespace)
        guard tokens.count == text.words.count else { return nil }
        let inside = clip.start ..< clip.start + clip.duration
        return zip(tokens, text.words).compactMap { token, word in
            let start = clip.start + word.start
            guard inside.contains(start) else { return nil }
            return CaptionCues.Word(
                text: String(token), start: start, end: clip.start + word.end, speaker: nil)
        }
    }

    /// VR-40 (e): each track re-paged on the trial's canvas, back to front, as one batch per
    /// track tried op by op on a scratch copy; a `LayoutError` or a refusal keeps the track
    /// and applies nothing of it. Then the new track back at the old one's index, hidden and
    /// locked as it was. Throws only the core's invalid input.
    static func relay(_ tracks: [Track], on trial: inout SwitchAngle.Trial) throws -> Outcome {
        var outcome = Outcome(relaid: [], kept: [])
        for track in tracks {
            let before = trial.project.snapshot
            guard let index = before.tracks.firstIndex(where: { $0.id == track.track }) else {
                continue
            }
            let old = before.tracks[index]
            let canvas = CGSize(width: before.canvas.width, height: before.canvas.height)
            let frame = max(before.canvas.fps.frameDuration, 1)
            let request = CaptionPages.Request(style: track.style, canvas: canvas)
            var cues: [CaptionLayout.Cue] = []
            for clip in before.clips(onTrack: track.track).sorted(by: { $0.start < $1.start }) {
                cues += CaptionPages.repage(
                    words(of: clip) ?? [], span: clip.start ..< clip.start + clip.duration,
                    frame: frame, request: request, clip: clip.id)
            }
            func keep(_ reason: String) {
                outcome.kept.append(Kept(track: track.track, name: track.name, reason: reason))
            }
            let plan: CaptionLayout.Plan
            do {
                plan = try CaptionLayout.place(
                    cues, in: trial.project, trackBase: track.name, style: track.style,
                    looks: track.looks, replacing: [track.track])
            } catch let error as CaptionLayout.LayoutError {
                keep(error.errorDescription ?? "the captions could not be placed")
                continue
            }
            var scratch = trial
            var refused: String?
            for op in plan.ops {
                if let why = try scratch.require(op) {
                    refused = why
                    break
                }
            }
            if let refused {
                keep(refused)
                continue
            }
            let known = Set(before.tracks.map(\.id))
            guard
                let made = scratch.project.snapshot.tracks.first(where: {
                    !known.contains($0.id)
                })
            else {
                keep("no caption track was made")
                continue
            }
            var follow: [ReelOp] = [.moveTrack(track: made.id, index: index)]
            if old.hidden { follow.append(.setTrack(track: made.id, hidden: true)) }
            if old.locked { follow.append(.setTrack(track: made.id, locked: true)) }
            for op in follow {
                if let why = try scratch.require(op) {
                    refused = why
                    break
                }
            }
            if let refused {
                keep(refused)
                continue
            }
            trial = scratch
            outcome.relaid.append(
                Relaid(
                    track: made.id, replaced: track.track, name: made.name, style: track.style,
                    pages: plan.clips))
        }
        return outcome
    }

    /// VR-45: the survey and the re-lay of one container's handle (the editor's
    /// `editedProject`); the outcome's kept tracks are the survey's, then the re-lay's.
    static func plan(_ project: ReelProject) throws -> (ops: [ReelOp], outcome: Outcome) {
        let found = survey(project.snapshot)
        var trial = SwitchAngle.Trial(project: project)
        var outcome = try relay(found.recognised, on: &trial)
        outcome.kept = found.kept + outcome.kept
        return (trial.ops, outcome)
    }

    /// The answer's `relaid` and `kept`, as both tools spell them.
    static func answerFields(_ outcome: Outcome) -> [String: Any] {
        [
            "relaid": outcome.relaid.map { relaid -> [String: Any] in
                [
                    "track": Int(relaid.track), "replaced": Int(relaid.replaced),
                    "name": relaid.name, "style": relaid.style.rawValue, "pages": relaid.pages,
                ]
            },
            "kept": outcome.kept.map { kept -> [String: Any] in
                ["track": Int(kept.track), "name": kept.name, "reason": kept.reason]
            },
        ]
    }

    /// One kept track's line, as the notice and Make Vertical's summary say it.
    static func keptLine(_ kept: Kept) -> String {
        let why = kept.reason.hasSuffix(".") ? String(kept.reason.dropLast()) : kept.reason
        return "Caption track \"\(kept.name)\" is kept as placed: \(why)."
    }

    /// The menu's informational sheet: nil when nothing was kept.
    static func noticeText(_ outcome: Outcome) -> String? {
        guard !outcome.kept.isEmpty else { return nil }
        let count = outcome.relaid.count
        let head = count == 0
            ? "No caption track was re-laid."
            : "Re-laid \(count) caption track\(count == 1 ? "" : "s") for this canvas."
        return ([head] + outcome.kept.map(keptLine)).joined(separator: "\n")
    }
}
