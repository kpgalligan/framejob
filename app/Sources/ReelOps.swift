import AppKit

/// How an edit is SPELLED: `OpArgs`, `ReelOp`, and one static factory per row
/// of the op table in spec §6 and in the module doc of `core/src/edit.rs`.
/// **The two move together** — an op added, renamed or re-argumented in
/// `edit.rs` is changed here in the same commit, and nowhere else in the app
/// is op JSON written by hand.
///
/// A row may have a SECOND factory beside its typed one: a RAW factory that
/// takes the caller's own object and forwards it unread, which is what the
/// agent door does at every op deepening D1 has moved (`setVideoRaw` and the
/// ten beside it, the last of them `setActionEndRaw` and `addZoomActionRaw`;
/// the paste payload factories are the precedent). It is a
/// second SPELLING of one row, not a second row, and it is here for the rule
/// above — the table stays the only place in the app where an op is named.
/// Where the raw and the typed factory differ in ONE argument
/// (`setCanvasRaw`, `addBackgroundRaw`, `addZoomActionRaw` and the two
/// new-clip ops, whose caller-authored part is a colour, a region or a patch
/// beside ordinary arguments) the typed one delegates to the raw one, so a
/// row still has one body.
///
/// The seam is the FFI. `ReelCore.swift` is the only file in the app that
/// names an `rc_*` symbol and nothing here names one: an op is a VALUE — a
/// name, its arguments, and the JSON those two make — that no handle has to
/// exist for. The whole contact surface between the two files is
/// `ReelProject.applying(_:)` reading `op.json`.
///
/// **The struct came with the factories rather than staying with the handle**,
/// and road map 2's phase 9 is the argument: it adds a `scope` to an op and
/// folds it into `json`, which is one edit to the struct and to whichever of
/// the fifty-odd writers below choose to set it. Keeping the field in one file
/// and its writers in another would put the two halves of that edit on either
/// side of a boundary. The handle's own half of the same phase — an
/// `rc_project_scoped` wrapper — stays where every other `rc_*` wrapper is, so
/// each file gets exactly one of them.
///
/// One member did NOT come. `ReelOp.coreNames()` reads `rc_op_names()`, and
/// the root `CLAUDE.md`'s rule that `ReelCore.swift` is the only file calling
/// `rc_*` is not negotiable, so it stays there in an `extension ReelOp` of its
/// own — the one place the op table is read BACK rather than written down.
///
/// The cut is the size payment `ReelCore.swift` owed at 2242 lines against
/// app/CLAUDE.md's ~600 cap, taken before phase 9 adds to it, and it is a pure
/// move: the same declarations, in the same order, with the same bodies.
/// Unlike `ExporterLoudness.swift` and `ExportSheetOptions.swift` it cost NO
/// visibility — a type carries its own scope, `OpArgs` is `private`, and every
/// one of its users is a factory below, so it is still `private` here and
/// nothing widened. That is the property that makes the move checkable.
///
/// What deliberately stayed behind is the op-ARGUMENT vocabulary —
/// `MediaDescriptor`, the `dictionary` extensions on the §5.2 property types,
/// and the four typed patches — which is a different concern with callers of
/// its own (`MediaImporter`, the inspector, `AgentServer`) and is the obvious
/// NEXT cut rather than this one. A file that holds every argument type as
/// well would be no smaller than the one it came out of.

// MARK: - Op arguments

/// Accumulates an op's arguments, DROPPING every nil so the core's serde
/// defaults apply — the rule for every optional argument in §6.
///
/// `put` is generic rather than taking `Any?` on purpose: a nil `Ticks?`
/// coerced to `Any?` can arrive as a non-nil `Any` wrapping a nil, which
/// would send `null` where the op wanted the key absent.
private struct OpArgs {
    private(set) var values: [String: Any] = [:]

    mutating func put<T>(_ key: String, _ value: T?) {
        if let value = value { values[key] = value }
    }

    /// An EXPLICIT JSON null — the spelling that clears a field (`kind:
    /// null` on `set_transition`, a removed key on `set_action_end`).
    mutating func putNull(_ key: String) {
        values[key] = NSNull()
    }
}

/// One edit, as the core's `{"op": "<name>", ...args}`.
///
/// The static factories below are one per row of the op table in spec §6 and
/// in the module doc of `core/src/edit.rs`. **The two move together**: an op
/// added, renamed or re-argumented in `edit.rs` is changed here in the same
/// commit, and nowhere else in the app is op JSON written by hand.
struct ReelOp {
    let name: String
    let args: [String: Any]

    /// The nest this op resolves its ids INSIDE, or nil for the timeline —
    /// the envelope's `scope` key (`core/src/scope.rs`, spec §6), which is
    /// not an argument of any op and is spelled once for all fifty-seven.
    ///
    /// It is a `var` with an initial value so the memberwise initialiser
    /// defaults it, which is what let every factory below stay untouched: an
    /// op is BUILT at the timeline's terms and then re-addressed by
    /// `scoped(_:)` at the one place that knows which container the edit is
    /// for (`ProjectDocument`).
    var scope: UInt32? = nil

    /// The op as the JSON `rc_project_apply` takes. Keys are sorted so two
    /// equal ops compare equal as strings. `"{}"` — which the core rejects
    /// as an unknown op — if a value were not JSON-representable, which the
    /// typed factories make impossible and a RAW one cannot reach either:
    /// its argument came out of a parsed JSON-RPC call, so every value in it
    /// is already one `JSONSerialization` wrote.
    ///
    /// An absent scope writes no key at all rather than an explicit null.
    /// The core reads the two the same way (`scope::read`), but a key that
    /// is only ever there when it means something keeps every unscoped op's
    /// JSON byte for byte what it was — which is what makes the whole phase
    /// invisible to a project that never enters a nest.
    var json: String {
        var object = args
        object["op"] = name
        if let scope = scope { object["scope"] = scope }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}

// MARK: - Scope

extension ReelOp {
    /// Returns this op carrying `scope`, or self when `nest` is nil.
    ///
    /// The one spelling of "this edit is about what is inside that nest".
    /// Every path that reaches the core goes through it —
    /// `ProjectDocument.applyEdit`, `updateLiveEdit`, `performGroupedEdit`
    /// and the MCP handlers' own `scope` argument — so an op's container is
    /// decided once, at the moment it is sent, and never by the factory that
    /// built it.
    func scoped(_ nest: UInt32?) -> ReelOp {
        guard let nest = nest else { return self }
        var copy = self
        copy.scope = nest
        return copy
    }

    /// The seven DOCUMENT-level ops among those `core/src/scope.rs`'s
    /// `refused_inside` answers `"<op> has no meaning inside nest N"` to. The
    /// eighth, `add_adjustment_clip` (spec §11 GR-6), is refused for what it
    /// places, not because it is the document's, so it is sent scoped.
    ///
    /// **The core owns this list and this is a mirror of it**, in the same
    /// sense that the typed factories above mirror the op table: change one,
    /// change both. It is seven names rather than a rule, so it can be
    /// checked by eye, and it is written here rather than at a call site
    /// because two copies of it is what would drift.
    ///
    /// It exists for a reason the road map did not anticipate. A scope is
    /// stamped on every op of an edit uniformly, and one edit can legitimately
    /// mix the two kinds: a Finder drop inside a nest is `add_media` — an act
    /// on the DOCUMENT's one media list, in the document's one id space — plus
    /// an `add_clip` that belongs in the nest, as ONE undo step
    /// (`EditorViewController+AddClips.swift`). Stamping the scope on both
    /// makes the whole drop an error; stamping it on neither drops the clip on
    /// the timeline. So `ProjectDocument` sends a document-level op UNSCOPED
    /// and everything else scoped, which is also why File ▸ Add Media…, a
    /// Relink and a Remove go on working with a nest open instead of being
    /// greyed out.
    ///
    /// Nothing here is a second opinion about what those ops MEAN: the core
    /// refuses a scoped one by name either way, and an agent that asks for one
    /// with a `scope` still gets that refusal, because `scoped(_:)` above is
    /// the plain stamp and this list is consulted only by the app's own edit
    /// paths.
    static let documentLevelNames: Set<String> = [
        "add_marker", "set_marker", "remove_marker", "set_canvas", "add_media", "relink_media",
        "remove_media",
    ]

    /// True for one of the seven above — an edit about the document rather
    /// than about whatever container the timeline is looking at.
    var isDocumentLevel: Bool { Self.documentLevelNames.contains(name) }
}

// MARK: - Op factories: clips

extension ReelOp {
    /// Whole media as one clip at `at`; Fit scale when the canvas says so.
    static func addClip(track: UInt32, media: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("media", media)
        a.put("at", at)
        return ReelOp(name: "add_clip", args: a.values)
    }

    /// A text clip; `duration` defaults to 5 s and `text` to the Title
    /// preset in the core.
    ///
    /// The op's `text` argument is a `set_text` PATCH, not a string — the
    /// core merges it over the Title preset — so the whole of `TextPatch`
    /// is reachable at creation and the caller's words go in under
    /// `content`. Passing a bare string is what the core answers
    /// `text patch must be a json object` to.
    static func addTextClip(
        track: UInt32, at: Ticks, duration: Ticks? = nil, text: TextPatch? = nil
    ) -> ReelOp {
        addTextClipRaw(
            track: track, at: at, duration: duration, text: text.map { $0.dictionary as Any })
    }

    /// The same op with the `text` object the CALLER wrote, forwarded to the
    /// core unread — the agent door's factory (deepening D1·4), beside the
    /// typed one Clip ▸ Add Text and the caption producers keep using.
    ///
    /// `text` is `Any?` for `setVideoRaw`'s reason: a caller who sent a
    /// number or a list where the patch belongs is refused by the CORE, in
    /// the words that name the group (`text patch must be a json object, not
    /// 5`), rather than by a cast on this side that knows less. nil means the
    /// key is ABSENT, which is what gives the core's own Title preset — and
    /// it is why the typed factory above maps rather than passing its
    /// optional straight in: an `Optional<[String: Any]>.none` widened to
    /// `Any?` becomes a non-nil `Any` wrapping a nil, and the key would be
    /// sent as a null.
    static func addTextClipRaw(
        track: UInt32, at: Ticks, duration: Ticks? = nil, text: Any? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        a.put("duration", duration)
        a.put("text", text)
        return ReelOp(name: "add_text_clip", args: a.values)
    }

    /// A shape clip; `duration` defaults to 5 s and `shape` to the core's
    /// default rectangle.
    ///
    /// As with `addTextClip`, the op's `shape` argument is a `set_shape`
    /// patch merged over that default (and over an arrow's head — see the
    /// op table), so the box and the paint are reachable at creation too.
    static func addShapeClip(
        track: UInt32, at: Ticks, duration: Ticks? = nil, shape: ShapePatch? = nil
    ) -> ReelOp {
        addShapeClipRaw(
            track: track, at: at, duration: duration, shape: shape.map { $0.dictionary as Any })
    }

    /// `addTextClipRaw`'s twin for the new shape clip's `shape`, same shape
    /// and same reasons (deepening D1·4).
    static func addShapeClipRaw(
        track: UInt32, at: Ticks, duration: Ticks? = nil, shape: Any? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        a.put("duration", duration)
        a.put("shape", shape)
        return ReelOp(name: "add_shape_clip", args: a.values)
    }

    /// `add_graphic_clip` (road map 10's G2a), raw: `props` and `schema`
    /// travel as the caller's JSON and the core is their one validator. No
    /// typed builder yet — G3's tool and G5's inspector are its callers.
    static func addGraphicClipRaw(
        track: UInt32, at: Ticks, duration: Ticks? = nil, name: String,
        width: UInt32? = nil, height: UInt32? = nil, props: Any? = nil, schema: Any? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        a.put("duration", duration)
        a.put("name", name)
        a.put("width", width)
        a.put("height", height)
        a.put("props", props)
        a.put("schema", schema)
        return ReelOp(name: "add_graphic_clip", args: a.values)
    }

    /// An adjustment clip (spec §11 GR-6): no picture, it grades what is
    /// behind it; `duration` defaults to 5 s.
    static func addAdjustmentClip(track: UInt32, at: Ticks, duration: Ticks? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        a.put("duration", duration)
        return ReelOp(name: "add_adjustment_clip", args: a.values)
    }

    /// The kind-only shorthand for the one caller that wants nothing else:
    /// the Add Shape menu, which picks a kind and takes the core's box,
    /// paint and — for an arrow — its head. An overload rather than a job
    /// for the caller, so `EditorViewController+AddClips` never has to
    /// spell a patch, and so this stays the only file that knows a kind
    /// travels as `{"kind": …}`.
    static func addShapeClip(
        track: UInt32, at: Ticks, duration: Ticks? = nil, shape: ShapeKind
    ) -> ReelOp {
        addShapeClip(track: track, at: at, duration: duration, shape: ShapePatch(kind: shape))
    }

    /// A backdrop on a NEW back-most track, starting at 0 and named
    /// "Background" — Clip ▸ Add Background ▸ Solid Color and ▸ Image….
    ///
    /// With `media`, that file is placed as `add_clip` would place it: the
    /// right source kind, Fit scale, audio props when it has sound. With
    /// `color`, or with NEITHER, it is a canvas-sized filled rectangle with
    /// no stroke at scale 1 — and the plate's default colour is WHITE, not
    /// black, because the canvas is already black and a black plate is a
    /// command that appears to do nothing. `duration` defaults to the
    /// timeline's own length.
    ///
    /// Every argument is optional, so the no-argument call IS the Solid
    /// Color row: it asks for a white plate the length of the cut, which
    /// the user then re-colours in the inspector's Fill row — and that Fill
    /// row is also how a full-canvas GRADIENT is reached, a gradient being
    /// a shape's fill and this clip being a shape.
    ///
    /// A `media` plate takes a FILL scale where `add_clip` takes a Fit one:
    /// a plate that leaves the canvas showing down one side has failed at the
    /// one thing a background is for, and it is the same scale
    /// `add_blurred_background` gives its copy, so the two commands agree.
    ///
    /// A VIDEO or AUDIO plate is held to its own file's length, whatever
    /// `duration` says and whatever the timeline is, so it never outruns
    /// what it shows; an image plate has no source bound and runs as long
    /// as it was asked to (spec §11, D4-4).
    ///
    /// Errors on `media` and `color` together (they are alternatives, and a
    /// caller that named both meant one of them), an unknown media, a media
    /// with no pictures, a colour outside 0–1, a duration under a frame, or
    /// a timed media shorter than one frame — `add_clip`'s own sentence.
    static func addBackground(
        media: UInt32? = nil, color: RGBA? = nil, duration: Ticks? = nil
    ) -> ReelOp {
        addBackgroundRaw(media: media, color: color.map { $0 as Any }, duration: duration)
    }

    /// The same op with the `color` the CALLER wrote, forwarded unread — the
    /// agent door's factory (deepening D1·4). A colour is four numbers each
    /// 0–1 and the core is what says so: the wrong length is its type's
    /// refusal and a component outside the range is `props_check.rs`'s,
    /// naming `shape.fill`, since the plate IS a shape clip.
    static func addBackgroundRaw(
        media: UInt32? = nil, color: Any? = nil, duration: Ticks? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("media", media)
        a.put("color", color)
        a.put("duration", duration)
        return ReelOp(name: "add_background", args: a.values)
    }

    /// The screencast backdrop — Clip ▸ Add Blurred Background. `clip` is
    /// copied onto a NEW back-most track at the same start, duration, speed
    /// and source window, so the two play the same frames, then scaled to
    /// FILL the canvas, centred, uncropped, and blurred at full strength.
    ///
    /// The copy is muted — its `enabled` becomes `{video: true, audio:
    /// false}`, `detach_audio`'s pair read the other way round — and it
    /// composites `normal` however the clip in front of it blends, because a
    /// plate blends with the CANVAS and a mode chosen for the picture would
    /// make the back-most layer multiply itself into black. It drops its
    /// `audio.duck`, its transition, its actions and its label; it is named
    /// "Blurred Background".
    ///
    /// Muting it is the reason this is one op and not a paste: the copy
    /// carries the same media at the same in point, so a mix that played both
    /// would play one source twice, which no still frame can see. **The duck
    /// goes for the same reason one field further in**, and the phase-6
    /// review is what found it: a duck is the one member of the audio group
    /// that lowers OTHER material, and `duckers()` gathers it without asking
    /// whether the clip can be heard — so a muted copy keeping one would duck
    /// the whole mix, the clip it was copied from included. Everything else is
    /// kept, the source window most of all, which is what a re-place through
    /// `add_clip` would have lost.
    ///
    /// Errors on an unknown clip, a NEST (a nest clip's own filters are
    /// dropped by the flattening, so the copy would come out sharp), a source
    /// with no pixel size (a text clip, an audio-only one) or a clip carrying
    /// no video properties.
    static func addBlurredBackground(clip: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        return ReelOp(name: "add_blurred_background", args: a.values)
    }

    /// The insert edit: makes room for the whole media at `at` on `track`
    /// — the clip `at` is inside on that track is cut first, then every
    /// unlocked track opens by the media's length — and places it. One op,
    /// so one undo step and one MCP tool. Refuses when the clip could not
    /// be placed after the room was made (a locked destination track);
    /// errors on an unknown track or media, or a media with no duration.
    static func insertClip(track: UInt32, media: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("media", media)
        a.put("at", at)
        return ReelOp(name: "insert_clip", args: a.values)
    }

    /// The overwrite edit: takes the room instead of making it. The span
    /// the media needs is cleared on `track` ALONE — cut at both bounds,
    /// the middles removed — and nothing shifts.
    ///
    /// A LOCKED destination is cleared like any other: the caller named the
    /// track, exactly as `rippleDelete` removes the clips it was given, and
    /// a lock decides only what may SHIFT — which here is nothing. That is
    /// the one place this differs from `insertClip`, which refuses on a
    /// locked track because the room it promises cannot be made there.
    /// Refuses when the clip could not be placed after the span was
    /// cleared; errors on an unknown track or media, or a media with no
    /// duration.
    static func overwriteClip(track: UInt32, media: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("media", media)
        a.put("at", at)
        return ReelOp(name: "overwrite_clip", args: a.values)
    }

    /// Shifts clips by `delta` ticks and optionally to another track (the
    /// others keep their relative track offsets). Refuses when the overlap
    /// rule fails on the destination.
    static func moveClip(clips: [UInt32], delta: Ticks, track: UInt32? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("delta", delta)
        a.put("track", track)
        return ReelOp(name: "move_clip", args: a.values)
    }

    /// Front trim: the source in-point advances with the start, so later
    /// content stays where it is.
    static func trimStart(clip: UInt32, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to", to)
        return ReelOp(name: "trim_start", args: a.values)
    }

    static func trimEnd(clip: UInt32, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to", to)
        return ReelOp(name: "trim_end", args: a.values)
    }

    /// ⌥-drag on an edge: speed changes so the content fills the new length.
    /// Media sources only.
    static func rateStretch(clip: UInt32, toEnd: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to_end", toEnd)
        return ReelOp(name: "rate_stretch", args: a.values)
    }

    /// ⌥⇧-drag on a clip body: the source slides under a fixed clip.
    /// `delta` is TIMELINE ticks and the source moves by `delta × speed`;
    /// the start and duration do not move at all. Clamped inside the media,
    /// and a delta the clamps reduce to nothing is a refusal. A `still`
    /// moves the frame it holds; any other source is an error.
    static func slip(clip: UInt32, delta: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("delta", delta)
        return ReelOp(name: "slip", args: a.values)
    }

    /// ⌥⇧-drag on a clip edge: the hard cut between this clip and the one
    /// ending exactly at its start moves to `to`, and nothing else does.
    /// Refuses without a hard cut there — a gap, or an overlap, whose
    /// length is `setTransitionDuration`'s.
    static func roll(clip: UInt32, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("to", to)
        return ReelOp(name: "roll", args: a.values)
    }

    /// Splits at `at`. OMITTING `clips` entirely — not passing a flag — is
    /// what means "every unlocked clip under the playhead", the
    /// ⌘T-with-no-selection case: the core's `Op::Split` carries
    /// `clips: Option<Vec<u32>>` and `deny_unknown_fields`, so any extra key
    /// here is an error rather than a silently ignored hint.
    static func split(clips: [UInt32]?, at: Ticks) -> ReelOp {
        var a = OpArgs()
        if let clips = clips, !clips.isEmpty {
            a.put("clips", clips)
        }
        a.put("at", at)
        return ReelOp(name: "split", args: a.values)
    }

    /// Removes clips and LEAVES the gaps.
    static func delete(clips: [UInt32]) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        return ReelOp(name: "delete", args: a.values)
    }

    /// Removes clips and closes the gaps across every unlocked track.
    static func rippleDelete(clips: [UInt32]) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        return ReelOp(name: "ripple_delete", args: a.values)
    }

    /// The in/out-range form: splits every unlocked clip at both bounds,
    /// removes the middles, then shifts.
    static func rippleDeleteRange(from: Ticks, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("from", from)
        a.put("to", to)
        return ReelOp(name: "ripple_delete_range", args: a.values)
    }

    /// Several ranges cut and closed as ONE edit — Clip ▸ Remove Silences…
    /// (`SilenceSheetController`), whose forty little cuts have to be one
    /// undo step.
    ///
    /// The core MERGES the pairs first (touching as well as overlapping) and
    /// then cuts the survivors right to left, so this is deliberately NOT the
    /// same thing as N `ripple_delete_range` ops sent in a row: two ranges
    /// that touch make one shift, not two, and a caller that wanted the
    /// singular's semantics per range would have to send them itself, in
    /// descending order. A reversed pair is the same range, and a list that
    /// merges to nothing changes nothing.
    static func rippleDeleteRanges(ranges: [(from: Ticks, to: Ticks)]) -> ReelOp {
        var a = OpArgs()
        // `[[from, to], …]`, the wire shape the op parses — arrays rather
        // than objects, as `Color` and `Fps` are.
        a.put("ranges", ranges.map { [$0.from, $0.to] })
        return ReelOp(name: "ripple_delete_ranges", args: a.values)
    }

    /// The same cut without the close: ⌫ with a range and nothing
    /// selected. Every clip after the range keeps the moment it had.
    static func liftRange(from: Ticks, to: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("from", from)
        a.put("to", to)
        return ReelOp(name: "lift_range", args: a.values)
    }

    /// Shifts every unlocked clip starting at or after `at` right by
    /// `length`; straddling clips stay put.
    static func insertTime(at: Ticks, length: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("at", at)
        a.put("length", length)
        return ReelOp(name: "insert_time", args: a.values)
    }

    /// Closes the empty span on `track` that contains `at`, shifting
    /// everything past it left across every unlocked track. Refuses on a
    /// locked track, on an `at` that is on a clip, with nothing after the
    /// gap, and when the shift would break the overlap rule — a gap closes
    /// fully or not at all.
    static func closeGap(track: UInt32, at: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("at", at)
        return ReelOp(name: "close_gap", args: a.values)
    }

    /// Media sources only; actions keep their clip-relative fraction.
    ///
    /// Give a `rate` or a `duration`, exactly one: the core answers both or
    /// neither with an error (spec §11 #190). A `duration` is the Fit arm —
    /// the rate becomes whatever plays the clip's content in that length.
    /// Either rate is clamped to `ReelSpeed.limits`.
    ///
    /// The duration the core writes is `source length / rate` snapped to a
    /// frame and then held to what the file still holds AT THE NEW RATE
    /// (spec §11, D4-3), so a clip sitting at the tail of its file can come
    /// back up to a frame shorter than the arithmetic asked for — and ×2
    /// then ×1 there is not an identity.
    static func setSpeed(
        clip: UInt32, rate: Double? = nil, duration: Ticks? = nil, keepPitch: Bool? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("rate", rate)
        a.put("duration", duration)
        a.put("keep_pitch", keepPitch)
        return ReelOp(name: "set_speed", args: a.values)
    }

    /// Plays a media clip back to front, or forward again.
    ///
    /// A FACT about the clip and not a plan change: the core's recipe and
    /// composition plan come out identical either way, and it is Swift that
    /// resolves it by substituting a pre-rendered reversed asset for that
    /// media's segments (spec §11). The in point is measured in the direction
    /// the clip plays, so flipping this keeps `in` and therefore shows
    /// different frames — the tail of the file instead of its head.
    ///
    /// Media sources only: any other kind is an `Err`, not a refusal (the
    /// non-media rule, §6).
    static func setReversed(clip: UInt32, reversed: Bool) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("reversed", reversed)
        return ReelOp(name: "set_reversed", args: a.values)
    }

    /// Split, insert time, then a one-source-frame `still` filling the gap.
    /// `duration` defaults to 2 s.
    static func freezeFrame(clip: UInt32, at: Ticks, duration: Ticks? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("at", at)
        a.put("duration", duration)
        return ReelOp(name: "freeze_frame", args: a.values)
    }

    /// Mutes the clip's audio and puts it on its own clip below. Refuses
    /// when the media has no audio or the audio is already detached.
    static func detachAudio(clip: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        return ReelOp(name: "detach_audio", args: a.values)
    }

    /// Copies placed after the originals' span on the same tracks.
    static func duplicate(clips: [UInt32]) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        return ReelOp(name: "duplicate", args: a.values)
    }

    /// Inserts a clipboard payload's clips with fresh ids, the earliest one
    /// landing exactly at `at` and the rest keeping their offsets from it.
    ///
    /// `payload` is what Copy wrote to the pasteboard —
    /// `{"clips": [...], "media": [...]}` — and
    /// `EditorViewController+Clipboard.swift` is the only place that builds
    /// one. **A payload clip's `track` is a DEPTH from the front of the stack**
    /// (0 = front-most), not a track id: the ids in it belong to whichever
    /// document was copied from. `track` here, by contrast, IS an id of this
    /// project, naming where depth 0 lands; omitted, that is the front track.
    static func paste(at: Ticks, track: UInt32? = nil, payload: [String: Any]) -> ReelOp {
        var a = OpArgs()
        a.put("at", at)
        a.put("track", track)
        a.put("payload", payload)
        return ReelOp(name: "paste", args: a.values)
    }

    /// Copies the payload's EARLIEST clip's property groups onto each of
    /// `clips` — ⌥⌘V. Earliest by start, at one start the front-most
    /// track and then the lower id; never the array's first, which is
    /// Copy's creation order. `payload` is the same Copy payload `paste` takes.
    /// `groups` names which of the five groups travel — `video`, `audio`,
    /// `text`, `shape` and `graphic`; omitted, each of the FIRST FOUR both
    /// sides have does, silently skipping the rest and never `graphic`, where
    /// a named group either side lacks is an error. Video and audio paste
    /// whole, text keeps its content, a shape keeps its kind and geometry,
    /// and `graphic` copies the props whole between clips drawn by one
    /// module, the target keeping its module, size, in point and length
    /// (spec §11 G-32); speed, enabled, actions, the transition and the
    /// clip's own name and label stay. `skipMissing` (with `groups` named)
    /// drops a named group the payload clip lacks and skips a target that
    /// cannot take one, instead of the error — Edit ▸ Paste Graphic
    /// Properties sends it. An identity when nothing changes.
    static func pasteAttributes(
        clips: [UInt32], payload: [String: Any], groups: [String]? = nil,
        skipMissing: Bool? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("payload", payload)
        a.put("groups", groups)
        a.put("skip_missing", skipMissing)
        return ReelOp(name: "paste_attributes", args: a.values)
    }

    /// Collapses `clips` into ONE clip showing a nest — ⌘G.
    ///
    /// The clips move whole (ids, props, actions, transitions) into the
    /// nest's own tracks, keeping their relative times with the earliest at
    /// 0; the nest clip lands on the front-most track the selection occupied
    /// and covers exactly the span the selection covered. `name` defaults to
    /// `Nest <n>` in the core. Refused on an empty selection, on a lone nest
    /// clip, and when the nest clip would break the overlap rule.
    static func nest(clips: [UInt32], name: String? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("name", name)
        return ReelOp(name: "nest", args: a.values)
    }

    /// Puts a nest clip's contents back on the timeline and removes it —
    /// ⇧⌘G. The inverse of `nest`, ids aside: each clip returns at
    /// `clip.start +` its own start, on tracks counted back from the nest
    /// clip's own, and a clip the overlap rule refuses goes on a new track in
    /// front rather than being dropped.
    ///
    /// A nest clip trimmed shorter than its contents gives ALL of them back —
    /// `Source::Nest` has no in point, so trimming one hid content rather
    /// than cutting it. An `Err` on any other kind of clip.
    static func unnest(clip: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        return ReelOp(name: "unnest", args: a.values)
    }

    /// Merges `patch` into the clips' base video props. Refuses when
    /// nothing changes, which is what keeps a live gesture from registering
    /// undo steps for frames that moved nowhere.
    static func setVideo(clips: [UInt32], patch: VideoPatch) -> ReelOp {
        setVideoRaw(clips: clips, patch: patch.dictionary)
    }

    /// The same op with the patch object the CALLER wrote, forwarded to the
    /// core byte for byte — the agent door's factory (deepening D1,
    /// `archive/reelcut-roadmap-7.md` §1), beside the typed one the
    /// inspector, the canvas sessions and the menus keep using.
    ///
    /// **`patch` is `Any` rather than `[String: Any]`** so that a caller who
    /// sent a number, a list or `null` where the object belongs is refused by
    /// the CORE, in the words that name the group — `video patch must be a
    /// json object, not 5` — instead of by a cast on this side that knows
    /// less. `ReelOp.json` serialises whatever it is; a value JSON cannot
    /// carry is impossible here, since the argument came out of a parsed
    /// JSON-RPC call.
    ///
    /// The paste payload factories are the precedent for a factory that takes
    /// a foreign object whole (`paste`, `pasteAttributes`), and the rule they
    /// keep is the point of putting this here: the op table stays the ONLY
    /// place in the app where an op is spelled, raw patch or not. #5's and
    /// #6's doors copy this shape.
    static func setVideoRaw(clips: [UInt32], patch: Any) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch)
        return ReelOp(name: "set_video", args: a.values)
    }

    /// `setVideoRaw`'s twin for the audio group (deepening D1·4). The three
    /// below and `setClipRaw` are the same five lines with another op name,
    /// deliberately: the group a refusal names is the one the OP name picks,
    /// so there is nothing here to get right per group.
    static func setAudioRaw(clips: [UInt32], patch: Any) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch)
        return ReelOp(name: "set_audio", args: a.values)
    }

    static func setAudio(clips: [UInt32], patch: AudioPatch) -> ReelOp {
        setAudioRaw(clips: clips, patch: patch.dictionary)
    }

    static func setTextRaw(clips: [UInt32], patch: Any) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch)
        return ReelOp(name: "set_text", args: a.values)
    }

    static func setText(clips: [UInt32], patch: TextPatch) -> ReelOp {
        setTextRaw(clips: clips, patch: patch.dictionary)
    }

    static func setShapeRaw(clips: [UInt32], patch: Any) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch)
        return ReelOp(name: "set_shape", args: a.values)
    }

    static func setShape(clips: [UInt32], patch: ShapePatch) -> ReelOp {
        setShapeRaw(clips: clips, patch: patch.dictionary)
    }

    /// `set_graphic` (road map 10's G2a), raw like `addGraphicClipRaw`.
    static func setGraphicRaw(clips: [UInt32], patch: Any, schema: Any? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch)
        a.put("schema", schema)
        return ReelOp(name: "set_graphic", args: a.values)
    }

    /// The fifth patch's raw factory (deepening D1·4). Its group has no
    /// nesting to merge, so what the forwarding buys here is the wrong TYPE:
    /// `ClipPatch`'s two keys are `String??`, which a lenient decode reads as
    /// a CLEAR, so `{"label": 7}` used to need a hand check on this side and
    /// is now `"label" in a clip patch must be a string or null, not 7`.
    static func setClipRaw(clips: [UInt32], patch: Any) -> ReelOp {
        var a = OpArgs()
        a.put("clips", clips)
        a.put("patch", patch)
        return ReelOp(name: "set_clip", args: a.values)
    }

    /// Sets or clears the clips' own name and label — the fifth patch op,
    /// shaped like `set_video` so the agent reaches it the same way, through
    /// the raw factory above. Each key is three-state (`ClipPatch`): absent
    /// keeps, null clears, a string sets. The core trims a name and treats
    /// an empty one as a clear, so the app may send what the user typed.
    /// Refuses when nothing changes.
    static func setClip(clips: [UInt32], patch: ClipPatch) -> ReelOp {
        setClipRaw(clips: clips, patch: patch.dictionary)
    }

    /// Per-clip visibility and mute — the two halves Detach Audio flips.
    static func setEnabled(clip: UInt32, video: Bool? = nil, audio: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("video", video)
        a.put("audio", audio)
        return ReelOp(name: "set_enabled", args: a.values)
    }

    /// Sets the transition INTO `clip`; nil sends an explicit null, which
    /// clears it. The duration is the overlap, not an argument here.
    static func setTransition(clip: UInt32, kind: TransitionKind?) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        if let kind = kind {
            a.put("kind", kind.rawValue)
        } else {
            a.putNull("kind")
        }
        return ReelOp(name: "set_transition", args: a.values)
    }

    /// Moves the clip so the overlap equals `duration`, subject to the
    /// overlap rule.
    static func setTransitionDuration(clip: UInt32, duration: Ticks) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("duration", duration)
        return ReelOp(name: "set_transition_duration", args: a.values)
    }

    /// Makes an overlap at the hard cut BEFORE `clip` out of the two clips'
    /// unused handles (format version 7, §6 `add_transition`).
    ///
    /// A nil `kind` and a nil `align` are OMITTED rather than sent as null:
    /// the core's defaults are "the clip's own stored kind, else a cross
    /// dissolve" and `center`, and an explicit null would be a parse error
    /// in the first case and a wrong argument in the second. That is the
    /// opposite of `setTransition`, where a nil kind is a CLEAR and has to
    /// be spelled out. `ripple` makes the overlap by sliding the incoming
    /// clip and everything after it left instead, and is sent only when true.
    static func addTransition(
        clip: UInt32, kind: TransitionKind?, duration: Ticks, align: TransitionAlign? = nil,
        ripple: Bool = false
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("kind", kind?.rawValue)
        a.put("duration", duration)
        a.put("align", align?.rawValue)
        a.put("ripple", ripple ? true : nil)
        return ReelOp(name: "add_transition", args: a.values)
    }

    /// The transition's easing and whether it crossfades the two clips'
    /// sound (§6 `set_transition_style`). A nil argument is omitted, which
    /// the core reads as "keep"; both nil changes nothing.
    static func setTransitionStyle(clip: UInt32, curve: Curve?, audio: Bool?) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("curve", curve?.rawValue)
        a.put("audio", audio)
        return ReelOp(name: "set_transition_style", args: a.values)
    }
}

/// Where the overlap `add_transition` makes is taken FROM —
/// `core/src/edit_transition.rs`'s `TransitionAlign`, spelling for spelling.
///
/// It lives beside the op that takes it, as `ZoomFit` does, and is
/// `CaseIterable` so the MCP handler can list the three legal values when
/// it refuses a fourth by name.
enum TransitionAlign: String, CaseIterable {
    /// Half from each side, the odd frame to the incoming clip.
    case center
    /// All of it out of the incoming clip's head.
    case before
    /// All of it out of the outgoing clip's tail.
    case after
}

// MARK: - Op factories: actions

/// The rectangle `add_zoom_action` zooms to, in the SPOTLIGHT'S frame:
/// `x` and `y` are its **CENTRE** as an offset in source pixels from the
/// centre of the layer's cropped rect, and `width`/`height` are its size in
/// source pixels. `ZoomRegion` in `core/src/edit_zoom.rs` is the same four
/// numbers, and its module doc carries the placement equation.
///
/// Centre-and-size because that is what `SpotlightProps` and `ObscureProps`
/// already are, and three region types where one reads its `x` differently
/// from the other two is a wrong picture found months later. A drag gives
/// two corners; converting them is one subtraction at the call site.
///
/// An op ARGUMENT, not model state — it never reaches a project file — so it
/// lives here beside the builder that sends it rather than in
/// `ProjectSnapshot.swift`, exactly as `MediaDescriptor` does.
struct ZoomRegion: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The region a rect in that same source-pixel frame describes —
    /// `SpotlightProps.box` read backwards, for a gesture that has two
    /// corners rather than a centre.
    init(box: CGRect) {
        self.init(x: box.midX, y: box.midY, width: box.width, height: box.height)
    }

    var dictionary: [String: Any] { ["x": x, "y": y, "width": width, "height": height] }
}

/// How the region is made to meet the canvas. `ZoomFit` in
/// `core/src/edit_zoom.rs`; both readings are measured THROUGH the clip's
/// rotation, so a rotated clip zooms to the rectangle the user drew.
enum ZoomFit: String, CaseIterable {
    /// The whole region visible — the core's default, because a zoom the
    /// user drew a box for should show the box.
    case fit
    /// The region covers the canvas, so nothing outside it is on screen.
    case fill

    var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        }
    }
}

extension ReelOp {
    /// `at` is CLIP time. Refuses on an overlap with another action or a
    /// span past the clip end. The end patch starts empty.
    static func addAction(clip: UInt32, at: Ticks, duration: Ticks? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("at", at)
        a.put("duration", duration)
        return ReelOp(name: "add_action", args: a.values)
    }

    /// The screencast zoom: an `add_action` whose end patch is the `scale`,
    /// `x` and `y` that bring `region` to the canvas — `Z`'s rubber band on
    /// the canvas (`ZoomRegionSession`) and the Actions section's two
    /// buttons. `at` is CLIP time, like `add_action`'s.
    ///
    /// A `nil` region is a zoom BACK: the end patch is the clip's own base
    /// `scale`, `x` and `y`. It is sent as an EXPLICIT null rather than as an
    /// omitted key — the core reads the two the same way, and the op's JSON
    /// should say what it meant, since a reader of a saved call cannot tell a
    /// deliberate zoom back from a forgotten argument otherwise. The MCP tool
    /// makes the same distinction the only place it can be made, by requiring
    /// the key (`AgentServer.addZoomAction`).
    ///
    /// `fit` and `curve` are omitted when nil so the core's own defaults
    /// apply — `fit`, and `ease_in_out` rather than `Curve.default`'s
    /// `linear`, because a zoom that starts and stops abruptly is the one
    /// thing this feature exists to avoid.
    static func addZoomAction(
        clip: UInt32, at: Ticks, duration: Ticks? = nil, region: ZoomRegion?,
        fit: ZoomFit? = nil, curve: Curve? = nil
    ) -> ReelOp {
        addZoomActionRaw(
            clip: clip, at: at, duration: duration,
            region: region.map { $0.dictionary as Any } ?? NSNull(), fit: fit, curve: curve)
    }

    /// The same op with the `region` the CALLER wrote, forwarded unread — the
    /// agent door's factory (deepening D1·5, `archive/reelcut-roadmap-7.md`
    /// §2.5). Only the region differs from the typed factory above, which is
    /// why that one delegates here, as `setCanvasRaw`'s twin does.
    ///
    /// **`region` is `Any` and not `Any?`**, because at this argument an
    /// absent key and an explicit null are opposite intentions and the core
    /// cannot tell them apart: a null is the zoom BACK, and the key is
    /// REQUIRED by the tool (`AgentServer.addZoomAction`) so that a forgotten
    /// rectangle cannot become one. Both callers therefore always have a
    /// value to send, `NSNull` for the zoom back — which is what the typed
    /// factory wrote here before, and the reason the `map` is explicit: an
    /// `Optional<ZoomRegion>.none` widened straight to `Any?` is a non-nil
    /// `Any` wrapping a nil.
    ///
    /// The core reads the object as a TYPE (`edit_zoom.rs`'s `ZoomRegion`),
    /// so an unknown member, a missing one and a wrong-typed one are each
    /// refused by name and a four-number LIST is refused rather than read
    /// positionally — which is what let the hand reader here go.
    static func addZoomActionRaw(
        clip: UInt32, at: Ticks, duration: Ticks? = nil, region: Any,
        fit: ZoomFit? = nil, curve: Curve? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("at", at)
        a.put("duration", duration)
        a.put("region", region)
        a.put("fit", fit?.rawValue)
        a.put("curve", curve?.rawValue)
        return ReelOp(name: "add_zoom_action", args: a.values)
    }

    /// Moves or re-curves an action; the same overlap checks apply.
    static func setAction(
        clip: UInt32, action: UInt32, start: Ticks? = nil, duration: Ticks? = nil,
        curve: Curve? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("action", action)
        a.put("start", start)
        a.put("duration", duration)
        a.put("curve", curve?.rawValue)
        return ReelOp(name: "set_action", args: a.values)
    }

    /// The end patch the CALLER wrote, forwarded to the core byte for byte —
    /// the sixth and last patch door deepening D1 moved (D1·5,
    /// `archive/reelcut-roadmap-7.md` §2.5), and `setVideoRaw`'s five lines
    /// with another op name.
    ///
    /// What is different about this one is the SUBJECT the core's refusals
    /// name: the object spans three groups, so a path carries the group
    /// (`video.filters[1].kind`) and the sentence says `an action end patch`
    /// rather than any one group's. `video.motion` is refused by the core
    /// too, because a preset is anchored to the clip's two ends and an
    /// action is a ramp between two states.
    ///
    /// `off` is `"group.key"` paths the core writes as `null` after the
    /// merge — the property keyed OFF at the end (spec §11 CI-14) — and is
    /// written only when non-empty, so every call without it is the JSON it
    /// always was. A null in `patch` stays a REMOVAL (`clearOps`, agents).
    /// `schema` is the module's current revision, which the agent door fills
    /// when the patch names `graphic` (spec §11 G-34); nil writes no key.
    static func setActionEndRaw(
        clip: UInt32, action: UInt32, patch: Any, off: [String] = [], schema: Any? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("action", action)
        a.put("patch", patch)
        if !off.isEmpty { a.put("off", off) }
        a.put("schema", schema)
        return ReelOp(name: "set_action_end", args: a.values)
    }

    /// Merges into the action's end patch. A typed `.some(nil)` — a switch
    /// the inspector turned OFF (`VideoPatch.shadow`'s double optional) — is
    /// LIFTED out of the patch into `off`, so the end state holds the
    /// property off rather than losing the key (spec §11 CI-14). Removal
    /// keeps its one spelling: `InspectorBinding.clearOps`' raw nulls.
    /// `graphic`'s one value is its `props` map, so the lift never touches
    /// it; `schema` is the module's current revision, which a graphic end
    /// needs (spec §11 G-34 (c), (l)).
    static func setActionEnd(
        clip: UInt32, action: UInt32, patch: ActionPatch, schema: [String: Any]? = nil
    ) -> ReelOp {
        var groups = patch.dictionary
        var off: [String] = []
        for (group, body) in groups {
            guard var fields = body as? [String: Any] else { continue }
            for (key, value) in fields where value is NSNull {
                off.append("\(group).\(key)")
                fields[key] = nil
            }
            groups[group] = fields
        }
        return setActionEndRaw(clip: clip, action: action, patch: groups, off: off.sorted(), schema: schema)
    }

    static func removeAction(clip: UInt32, action: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("clip", clip)
        a.put("action", action)
        return ReelOp(name: "remove_action", args: a.values)
    }
}

// MARK: - Op factories: tracks, markers, canvas, media

extension ReelOp {
    /// Inserts a track; index 0 is the BACK of the stack.
    static func addTrack(index: Int, name: String? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("index", index)
        a.put("name", name)
        return ReelOp(name: "add_track", args: a.values)
    }

    /// Refuses on a non-empty track unless `withClips`.
    static func removeTrack(track: UInt32, withClips: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("with_clips", withClips)
        return ReelOp(name: "remove_track", args: a.values)
    }

    static func moveTrack(track: UInt32, index: Int) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("index", index)
        return ReelOp(name: "move_track", args: a.values)
    }

    /// Omitted fields keep their value. `solo` is the fourth switch: while
    /// any track in a container is soloed, every track that is not is
    /// silent; mute wins over solo on the same track, and pictures are
    /// untouched either way.
    static func setTrack(
        track: UInt32, name: String? = nil, hidden: Bool? = nil, muted: Bool? = nil,
        locked: Bool? = nil, solo: Bool? = nil, matte: TrackMatte? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("track", track)
        a.put("name", name)
        a.put("hidden", hidden)
        a.put("muted", muted)
        a.put("locked", locked)
        a.put("solo", solo)
        a.put("matte", matte?.rawValue)
        return ReelOp(name: "set_track", args: a.values)
    }

    static func removeEmptyTracks() -> ReelOp {
        ReelOp(name: "remove_empty_tracks", args: [:])
    }

    /// Markers snap to frames and two may not share a time.
    static func addMarker(
        at: Ticks, name: String? = nil, chapter: Bool? = nil, color: String? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("at", at)
        a.put("name", name)
        a.put("chapter", chapter)
        a.put("color", color)
        return ReelOp(name: "add_marker", args: a.values)
    }

    static func setMarker(
        marker: UInt32, time: Ticks? = nil, name: String? = nil, chapter: Bool? = nil,
        color: String? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("marker", marker)
        a.put("time", time)
        a.put("name", name)
        a.put("chapter", chapter)
        a.put("color", color)
        return ReelOp(name: "set_marker", args: a.values)
    }

    static func removeMarker(marker: UInt32) -> ReelOp {
        var a = OpArgs()
        a.put("marker", marker)
        return ReelOp(name: "remove_marker", args: a.values)
    }

    /// `rescaleClips` multiplies every clip's `x`, `y` and `scale` by the
    /// size ratio; changing `fps` re-snaps every clip start and duration.
    static func setCanvas(
        width: Int? = nil, height: Int? = nil, fps: Fps? = nil, background: RGBA? = nil,
        rescaleClips: Bool? = nil, fitNewClips: Bool? = nil, timecodeFrames: Bool? = nil
    ) -> ReelOp {
        setCanvasRaw(
            width: width, height: height, fps: fps, background: background.map { $0 as Any },
            rescaleClips: rescaleClips, fitNewClips: fitNewClips,
            timecodeFrames: timecodeFrames)
    }

    /// The same op with the `background` the CALLER wrote, forwarded unread
    /// — the agent door's factory (deepening D1·4). Only the colour differs
    /// from the typed factory above, which is why that one delegates here
    /// rather than keeping a second copy of the seven arguments; the `map` is
    /// what keeps an absent background absent, since an `Optional<RGBA>.none`
    /// widened straight to `Any?` is a non-nil `Any` wrapping a nil.
    static func setCanvasRaw(
        width: Int? = nil, height: Int? = nil, fps: Fps? = nil, background: Any? = nil,
        rescaleClips: Bool? = nil, fitNewClips: Bool? = nil, timecodeFrames: Bool? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("width", width)
        a.put("height", height)
        a.put("fps", fps.map { [$0.num, $0.den] })
        a.put("background", background)
        a.put("rescale_clips", rescaleClips)
        a.put("fit_new_clips", fitNewClips)
        a.put("timecode_frames", timecodeFrames)
        return ReelOp(name: "set_canvas", args: a.values)
    }

    /// Adds a probed file to the media list. The new id is read back from
    /// the resulting snapshot (`nextId` before the op), because the op
    /// entry point returns a project, not a value.
    static func addMedia(descriptor: MediaDescriptor) -> ReelOp {
        var a = OpArgs()
        a.put("descriptor", descriptor.dictionary)
        return ReelOp(name: "add_media", args: a.values)
    }

    /// Points a media entry at a new file after a move — the Relink… path.
    /// `probe` is the new file's descriptor (spec §11, #63): the entry takes
    /// its duration, size, rate and flags, and a clip past a shorter file's
    /// end is held to it. Without one the record is kept.
    static func relinkMedia(
        media: UInt32, path: String, bookmark: String? = nil, probe: MediaDescriptor? = nil
    ) -> ReelOp {
        var a = OpArgs()
        a.put("media", media)
        a.put("path", path)
        a.put("bookmark", bookmark)
        a.put("probe", probe?.probeDictionary)
        return ReelOp(name: "relink_media", args: a.values)
    }

    /// Refuses while the media is in use unless `withClips`.
    static func removeMedia(media: UInt32, withClips: Bool? = nil) -> ReelOp {
        var a = OpArgs()
        a.put("media", media)
        a.put("with_clips", withClips)
        return ReelOp(name: "remove_media", args: a.values)
    }
}
