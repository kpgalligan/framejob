# Spec §11 — decisions: Creator jobs, the Layout section onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-8.md`](creator-jobs-8.md), so a citation never has to
say which file. This file holds CO-70…CO-73 (CO7), SW-10…SW-16 (SW1) and CO-90…CO-95 (CO9). The
series goes on in [`creator-jobs-9.md`](creator-jobs-9.md), which is why this file is lettered. It
is new because `creator-jobs-8.md` had passed the spec's ~500-line split rule (#548, 2026-11-11);
the entries moved here unchanged, and an "above" or "below" in one may now point into a sibling
file.

## CO7 — the Layout section, the nest offer and the crop on the person (2026-11-03)

Recorded before the code. CO-70…CO-73 are CO7's: the camera's crop in Circle, Side by Side and
Stacked centres on the person when the camera clip's person masks are cached for every frame it
plays; a Layout section in the Picture sub-tab sends the menu's op; a switch refused for a zoom
offers Nest and Switch as one undo step. No core change, no persisted field, no format bump, no
`rc_*` export and no new tool; nothing is sent anywhere, so nothing is keyed (CJ-3). The road map
asks the owner nothing at this phase.

- **CO-70 — The crop on the person.** The menu, the Layout section and the `switch_layout` tool
  send the same `focus` (CO-65). The camera clip's windows are `CutoutWants.windows(of:)`: its
  plan video segments whatever its cutout, mirrored about the pivot when reversed, over
  `CutoutStatus.detail`'s handles (`project`, plus `editedProject` with a nest open). The need is
  CO-22's rule (`CutoutWants.need`); the coverage is the `masks` marker that `answers(for:)` the
  stamp (`CutoutStatus.stamp`), its pack the payload. Focus is sent only when every needed index
  is covered: the mean, over found frames, of `CutoutStatus.centroid` (the number
  `analyze_cutout` answers as `centroid`), minus (w/2, h/2) of the media; otherwise none, and the
  crop centres on the source (CO-65). Only what is cached is read and no job is started (CO-6);
  the read is never keyed (CJ-3). The centroid is read off main and memoised on (pack path, file
  size, modification date, need, media size), at most 64 entries, cleared whole when full. The
  menu and the section read on `CameraLayoutFocus.queue` and apply on main only if
  `document.project` and `document.scope` are unchanged, else beep and change nothing. The tool
  fills `focus` when it is omitted or null (an explicit `[x, y]` wins), on the server thread with
  three hops as `auto_zoom` does, and refuses a changed project: "the project changed while
  switch_layout read the camera's person masks, so nothing was laid out. Call switch_layout
  again." Its answer carries `focus`, `[x, y]` or null. **A filled focus never reaches a nest
  clip:** `focus` is in the camera MEDIA's pixels, and `nest_then_switch` re-points the switch at
  the nest clip that replaces a moving camera, keeping `focus`; so a filled focus sent with
  `nest: true` goes only when `CameraLayoutCommand.keepsFocus` answers true — false only when the
  `nest: true` trial applies and the camera's id is absent from the applied project's view (the
  scoped view when the op is scoped) — and otherwise the op goes without it. Both senders call it
  on main: the offer sheet when it builds its op, the tool in its last hop. A caller's explicit
  focus is never dropped.
- **CO-71 — The Layout section** (`video.layout`, the Picture sub-tab). Offered when exactly one
  clip is selected and it is a `.media` clip with `video` and a source size; after Transform and
  Behind Subject, before Crop; shut by default. Rows: Layout (Corner, Side by Side, Stacked,
  Camera Full, Screen Only), Shape (Square, Rounded, Circle), Corner (Bottom Right, Bottom Left,
  Top Right, Top Left), Duration (s, 2 decimals, 0.01–10, quick 0.25 0.5 1 2, 0.5 by default),
  and Switch at Playhead. Shape and Corner are enabled only for Corner. The choices are per
  window (`ClipPane`), not persisted, not undoable, no Reset; the summary is the choice
  ("Circle, Bottom Right", "Side by Side"). Switch at Playhead is enabled while the window has no
  sheet and does not read the playhead (`inspectorPlayheadMoved()` refreshes only a clip with
  actions); pressed off the clip, the core's "clip N does not play at …" reaches the refusal
  strip through `performGroupedEdit`, with no undo step. It sends exactly the menu's op with the
  clip as camera and no screen, `duration` only when it is not 0.5 s.
- **CO-72 — The nest offer.** `CameraLayoutCommand.run`, which the menu and the section share,
  trials the op (no `nest`) on `document.project`, scoped as `ProjectDocument.addressed` scopes
  it. When it is refused and the same op with `nest: true` trials applied, a sheet goes up: "Lay
  out the clips in a nest?", the core's sentence verbatim, then "Nest and Switch puts those clips
  in a nest first, so the layout moves the nest and the zoom keeps playing inside it. One Undo
  takes both back.", buttons Nest and Switch and Cancel (Escape). Nest and Switch commits the ONE
  `switch_layout {nest: true}` through `performGroupedEdit` as one undo step "Camera Layout";
  Cancel changes nothing. Otherwise, and with no window, the op is committed through
  `performGroupedEdit`, whose arms beep, post the refusal strip or apply. The tool never offers:
  an agent sends `nest: true`. Because the item can now raise a sheet, `switchCameraLayout:`'s
  verdict in the menu inventory and `UIMenu.verdicts` is `sheet` (as `setTransitionKind:`'s is),
  so the screen catalog can reach the sheet.
- **CO-73 — The proof.** `tools/proof/co7_proof.py` (Release) with `co7_probe.swift`: Z1 no
  `Frame Job: ` line; P1 (probe) the section's place, its Switch at Playhead equal to the menu's
  Circle ▸ Top Left on a twin, one undo step each, Duration 1.00 a 600000-tick action, and a
  press off the clip refused at the strip with no step; P2 (canned masks of a person left of
  centre) the circle's crop centre at the masks' centroid within a pixel, P2b with half the
  window analysed the source's centre, P2c `analyze_cutout`'s centroid the same point; P3 no
  masks, the source's centre; P4 (probe, an editor in a window) the offer sheet, Cancel, and Nest
  and Switch equal to `switch_layout {nest: true}` and undone in one step; P5 the tool's filled
  focus equal to the menu's project and answered; P6 a filled focus dropped when `nest: true`
  nests the camera. Four mutants, each caught: the coverage guard dropped (P2b), the sheet's
  edits as two steps (P4), the fill skipped (P5), `keepsFocus` always true (P6). No new JOB row
  (JOB-64 stands).

## SW1 — copy pieces to a track, and Switch Angle (2026-11-03)

Recorded before the code. SW-10…SW-16 are SW1's: agents get `copy_pieces`, a core op that copies
a clip's pieces between given project times onto another track, each piece exactly the middle two
`split`s would leave; people get Clip ▸ Switch Angle ▸, and agents `switch_angle`, either of which
re-picks one shot from a covering camera track as one undo step. No persisted field, no format
bump (42 stands) and no `rc_*` export; nothing is sent anywhere, so nothing is keyed (CJ-3). The
owner's answers (2026-11-01): no ⌥1–⌥9 keys for Switch Angle (bare 1–9 come with the viewer in
SW9b), and a re-pick does not keep the shot's own video settings. SW1 ran in lane A (the road map
says lane C; nothing depends on the lane).

- **SW-10 — The switch writes a program track; it does not cut the cameras in place.**
  Picture-only cuts on the stacked cameras make two to three clips per shot where the program
  track makes one (a four-camera three-hour show at 8 s shots is about 5,400 against 1,350, past
  `MAX_CLIPS`); moving one cut there is trimming pieces on several tracks, here an ordinary roll;
  both decode one camera at a time.
- **SW-11 — `copy_pieces {clip, track, ranges, video?, audio?}`** copies the pieces of `clip`
  between each range's ends onto `track` at the same times, with fresh ids (the clip's and every
  action's). `ranges` are project times; `video` and `audio`, when given, set each piece's
  `enabled` switches. A copy has no transition and its link is cleared. Allowed inside a nest.
  As built (`core/src/edit_pieces.rs`), in this order:
  - `Err("no clip with id N")` for an unknown clip, then `Err("no track with id N")` for an
    unknown track.
  - Each pair is put in order (a reversed pair is the same range) and both ends are snapped by
    `snapped`, as `split` snaps. A range empty on the grid is dropped; nothing left is an
    identity (an empty `ranges` too). The ranges are sorted by start.
  - Then the refusals, each in its own sentence: a nest clip ("clip N is a nest: a piece of it
    would replay the nest from its first frame"); a range outside the clip ("range [a, b] is
    outside clip C, which runs from S to E"); overlapping ranges ("ranges [a, b] and [c, d]
    overlap"; ranges that only touch are allowed); a locked destination (`locked_track(T, "no
    piece can be copied onto it")`); a destination holding a clip over a range ("track T holds
    clip X between S and E", the clip's own ends, the first by start).
- **SW-12 — A piece is exactly the middle a `split` at its two ends would leave:** source window,
  a ramp's map and rate (SR-18), its actions clipped, a graphic's `in` and `length` (G-9), its
  words rebased (W-3), all from `split_clip`'s own arithmetic (`edit_split.rs`) on a scratch copy
  — `self` cloned with `clips` holding only the source clip, cloned again per range, split at
  `from` when `from` is past the clip's start and the middle split again at `to` when `to` is
  before its end. `split_clip` and its callers do not change. The middle is written into the
  result with a fresh id and fresh action ids from the result's own counter, never the scratch's;
  `track` the destination, `start` = `from`, `transition_in` and `linked` cleared, `enabled`
  overridden by `video`/`audio` where given; the exit is `finish`.
- **SW-13 — An angle is a TRACK; Clip ▸ Switch Angle ▸ re-picks one shot.** A track COVERS a span
  when its media clips with pictures together leave no part of it uncovered (a clip with its
  picture off, or on a hidden track, still counts). The submenu lists, for the one selected clip,
  every other track of its container covering the clip's whole span, front first, by name, up to
  nine; choosing one re-picks by SW-14's sequence, one `copy_pieces` per angle clip the span
  crosses, as one step "Switch Angle". `switch_angle {clip, angle}` does the same and refuses an
  angle not covering the shot, naming the first uncovered tick. No key (the owner, 2026-11-01).
- **SW-14 — A re-picked shot keeps its span, its switches and both its transitions, and nothing
  else** (a punch-in, grade or action on the old shot does not carry: the owner, 2026-11-01).
  With B between A and C: record B's span, switches and `transition_in`, A's end and C's start
  and `transition_in`; `delete` B; `trim_end` A to B's start and `trim_start` C to B's end, each
  `alone`; `copy_pieces` the angle over B's span with B's switches; trim A and C back to their
  old edges, re-forming both overlaps as they were; `set_transition` and `set_transition_style`
  give the new first piece B's `transition_in` and C its own. When the angle's clips cut the span
  into pieces and an overlap would break the overlap rule against a short piece, that transition
  is dropped and the step is "Switch Angle (transition removed)".
- **SW-15 — The menu and the tool.**
  - (a) Clip ▸ Switch Angle ▸ sits after Camera Layout ▸ and has no key. `SwitchAngleMenuFiller`
    fills it on open (the `LookMenuFiller` pattern), one item per `SwitchAngle.angles`: its title
    the track's name, a name two listed tracks share getting " (n)", n the track's 1-based
    position from the back; its tag the row index, its `representedObject` `NSNumber(track id)`,
    its selector `switchAngle(_:)`. With not exactly one selected clip, or no angle, the menu holds
    the single item "No Covering Angle", always disabled: it carries `switchAngle(_:)` with no
    track, which the validator turns off, and the menu is built holding it, so the selector is a
    live leaf before any project opens (the menu's three-way check, `v2_menu.py` H1; as built —
    the spec drafted it with no action).
  - (b) An item is enabled when exactly one clip is selected, its track is unlocked, it has no
    `linked`, the item's track is still in `angles`, and no sheet is up. Allowed inside a nest.
  - (c) `SwitchAngle.plan`'s refusals, in this order: the angle is the clip's own track ("track T
    is clip C's own track; an angle is another track"); the clip's track is locked ("track T is
    locked, so clip C cannot be re-picked"); a linked clip ("clip C is linked to clip P (Detach
    Audio's pair); Switch Angle re-picks a clip with no link"); not covering ("track T does not
    cover clip C: nothing with a picture plays on it at tick X"). An unknown clip or track
    throws.
  - (d) Covering counts only clips with `.media` sources whose media has a picture
    (`sourceSize(of:) != nil`); `enabled.video` and the track's `hidden` are ignored. The pieces
    are those angle clips sorted by start, each taking `[max(start, s), min(end, next angle
    clip's start, e))`, so where two angle clips overlap the later one takes over at its own
    start. Empty pieces are skipped, and each angle clip gets one `copy_pieces` with
    `video`/`audio` set to B's `enabled`.
  - (e) SW-14's ops are tried one at a time on the container's handle
    (`ReelProject.applying(_ op:)`), because `applying([ReelOp])` does not stop at a refusal.
    The new piece ids are read from the snapshot after the copies (a scoped view shares its
    parent's `next_id`). After `delete` B and the two trims away, A's end and C's start are read
    back. If any op before the trim-backs (`delete`, a trim away, a `copy_pieces`) answers
    refused, or a trim away is held short of its target (A's end is not exactly s, or C's start
    not exactly e, as a ramp's held edge leaves it, `source_window.rs`'s `front_edge_held`), the
    plan is refused and nothing is committed: a refusal gives that op's own sentence, a held trim
    "clip X's edge is held at tick Y, short of tick Z, so clip B cannot be re-picked". A
    trim-back that is refused, or held short of its old edge, is left out together with the
    transition ops for that edge; if the clip of that edge still holds a `transition_in`, it gets
    `set_transition` to none. When anything is left out, the step is "Switch Angle (transition
    removed)". A is the clip before B on its track ending after s, and C the clip after B
    starting before e; only these are trimmed. The menu commits through `applyEdit` and selects
    the pieces; the tool commits through `performGroupedEdit` and answers `{ok, step, pieces,
    transitions_removed, project}`, `pieces` in time order. `switch_angle` takes no `scope`: it
    reads the container `set_scope` has open, as `text_behind_subject` does, and runs on main.
- **SW-16 — The proof.** `tools/proof/switch_pieces_proof.py` (Release), P1–P5 and six mutants,
  with no manual check. P1 `copy_pieces` of a ×0.999 drift-corrected angle onto a new track:
  `render_frame` at five times byte-identical to the angle shown alone; P2 Switch Angle by
  `perform_menu_item` replaces the shot's media over the same span and one undo restores it; P3
  `switch_angle` the same, a non-covering angle refused in its sentence, and an angle of two
  abutting files re-picking a shot crossing their join as two pieces; P4 a shot with a dissolve on
  its incoming edge, its outgoing edge and both, every overlap's span, kind, curve and audio shape
  read back equal, a two-piece re-pick breaking the overlap rule named "Switch Angle (transition
  removed)", and P4d, a ramp-down C reaching its media's end, refused in the held-edge sentence
  with the project unchanged; P5 `copy_pieces` of 1,000 ranges on a two-hour angle within 0.5 s
  (median of five; over it, the figure in the guide and a Performance candidate). P5's fixture is
  generated into `tools/proof/media/creator/sw1/`: a two-hour 320×180 H.264 file stream-copied
  from repeats of one encoded minute, never committed. The mutants: the piece's `in` without the
  clip's speed (core); the occupancy refusal removed (core); the link kept on the copy (core);
  candidates not required to cover (P3); delete and copy as two steps (P2); neighbours not
  trimmed back (P4). The core mutants run against `cargo test --test copy_pieces`.

## CO9 — hide the camera while silent (2026-11-03)

Recorded before the code. CO-90…CO-95 are CO9's: a picture clip carries `video.hide_silent`
(format 43, provisional until the phase lands), the recipe multiplies its layer's opacity by a
gate read from a media's saved speech spans, so the camera fades out in pauses and back in just
before speech; a Hide While Silent section in the Picture sub-tab and `set_video` set it, both
saving the media's spans in the same undo step, and the timeline draws the gate's line on the
clip. No new op, tool or `rc_*` export. The spans come from the on-device Silero VAD cache, so
nothing is keyed (CJ-3). The owner's answer (2026-11-01): on silence, the camera FADES — not a
switch to Screen Only.

- **CO-90 — Hide while silent is a presentation term.** `video.hide_silent` is `null` or
  `{media, pre_roll, hold, fade}`. At project time `t` the core multiplies the layer's placed
  opacity by a gate:
  - **The containers** of a layer are its own (the innermost enclosing nest, or the timeline)
    and then each enclosing one outward. An instance of `media` is IN a container when its
    `inside` clip-id path starts with that container's path, at any depth.
  - **The container read** is the NEAREST one in which an instance of `media` covers `t`
    (`Side::Right`: `start ≤ t < end`; `Side::Left`: `start < t ≤ end`, the limit from the
    left the plan's ramp ends read).
  - **The spans:** every instance of `media` in that container whose played window meets
    `[t − hold − fade, t + pre_roll + fade]` gives its played speech (`played_speech`: the
    media's spans in clip time, moved to the instance's origin, kept to `[start, end)`); they
    are sorted, widened by `pre_roll` before and `hold` after, and merged where they overlap or
    touch. The window is exact: a widened span outside it cannot reach `t`.
  - **The gate** is the maximum over the merged spans `[s, e]` of 1 inside, `1 − (s − t)/fade`
    before and `1 − (t − e)/fade` after, floored at 0; a `fade` of 0 is a step (`[s, e)` on
    the right, `(s, e]` on the left). It is 1 when no container has an instance of `media`
    covering `t`, when `media` is not in the project or has no saved `speech`, and for a clip
    with none; a media whose `speech` is the empty list hides the clip wherever it plays.
  - A clip's `enabled`, its track's mute and its track's `hidden` do not matter: the speech is
    the media's. It reads the media's default source (`media.speech`); SW4b adds `stream` and
    `channel`.
  - Like `video.motion` (R5-4), every edit, `clip_state`, `get_project` and the inspector read
    the clip UN-gated; only the recipe's layer opacity and the plan's `gates` see it. The gate
    is applied in `recipe.rs`'s `layer` only, right after `moved`: `placement` (a routed
    dissolve's and the blur's sub-frame placements) reads only position, so gating there would
    change nothing.
  - Amends **AU-110** ("a second reader, `video.hide_silent`, reads a media's spans to show a
    picture while that media's speech plays") and **R5-4** ("`video.hide_silent`'s gate is the
    third place the recipe draws what the model does not say").
- **CO-91 — The numbers.** Defaults: `pre_roll` 0.2 s (120,000 ticks), `hold` 1.5 s
  (900,000), `fade` 0.3 s (180,000). Each of the three is 0…5 s (0…3,000,000 ticks), the Duck's
  range, refused outside in `ticks_in_range`'s sentence: "video.hide_silent.pre_roll must be
  between 0 and 3000000 ticks, not N". They are envelope lengths, stored as typed and off the
  frame grid (#355's rule). `media` 0 means not named. All four keys are always written; the
  key itself is written only when set, after `motion_blur`, so every other file's text is what
  it was.
- **CO-92 — Refusals and carries.**
  - `set_video` (and every pasted video group, through `settle_video`) refuses, each in its own
    sentence: the three ranges (`check_video`); then on the clip (`settle_video`) "video.
    hide_silent.media is required: the media whose speech the clip follows" (media 0), "video.
    hide_silent.media 9 is not a media of this project", "video.hide_silent.media 4 has no sound
    to follow" (`has_audio` false), and "clip 9 shows a nest and cannot hide while silent: set
    it on the clips inside".
  - Not animatable: `set_action_end` refuses a patch naming `video.hide_silent` (a `null`
    included) and an `off` naming it, "video.hide_silent is not an animation target"; the
    evaluator puts the base's value back over any end (`restore_base_video_keys`, beside the
    cutout's restore).
  - Carries: `split` (both halves), paste, Paste Attributes and `add_blurred_background`'s
    copy keep it (a backdrop leaves with its picture). Paste and Paste Attributes carry the
    gate's media as a NON-shown id, the look LUT's rule (GR-8): the clipboard payload carries
    its row, `absorb_media` matches it by path or appends it, and a payload without the row
    drops the gate to `None`, never a refusal; a pasted gate never follows a target media of
    the same id that the payload did not name.
  - `remove_media` clears every gate naming the media, on the timeline and in every nest, with
    no new refusal (a gate does not "use" its media). `keep_range` keeps a kept clip's gate
    media.
- **CO-93 — The plan's `gates` and the timeline's line.** The plan carries `"gates"` only when
  non-empty, after `ducks`: one entry `{clip, ramps}` per TIMELINE-level instance (empty
  `inside`) of a gated clip, its ramps tiling `[start, end)` in the handle's time and
  `coalesce`d — breakpoints at the instance's ends, every instance of the media's ends, each
  merged span's `s − fade`, `s`, `e` and `e + fade`, and the midpoint of two spans less than
  `2·fade` apart; each ramp's `from` read on the right and its `to` on the left. The timeline
  draws it as a teal 1 pt polyline over the clip's VIDEO region, gate 1 at the top, after the
  audio block. Inside an open nest it reads the scope's handle, so a gate from a container
  outside the nest is not drawn there (the recipe still applies it).
- **CO-94 — The section and the tool.**
  - **Hide While Silent** (`video.hide_silent`), the Picture sub-tab, after Layout, shut by
    default; offered when every selected clip has pixels and none is a nest clip (inside a nest
    scope too). Every row is one undo step "Hide While Silent", written to the base
    (`structural`), each writing the WHOLE props (Duck's rule).
  - Rows: the checkbox "Hide while silent" (on gives each clip without one
    `{media: the first candidate}` with the defaults, prefixed by `DuckSpeech.ops(forMedia:)`;
    off and Reset write `null`; enabled when on, or when a first candidate exists and
    `problem(forMedia:)` is nil, else its tooltip is the problem); the popup "Speech from" (the
    candidates by name, plus a set media outside them); Pre-roll, Hold and Fade (seconds, two
    decimals, 0–5; quick picks 0, 0.1, 0.2, 0.5 · 0.5, 1, 1.5, 3 · 0, 0.15, 0.3, 0.5). A thrown
    `ops(forMedia:)` makes the row's ops empty and the section's note shows the sentence. The
    summary is "off", the media's name, or "on" when mixed.
  - **Candidates:** the media with sound of any clip in the snapshot (selected clips included)
    overlapping a selected clip's span; picture-less media first ("the microphone first"),
    then by total overlap descending, then by id.
  - **`DuckSpeech.ops(forMedia:)`** answers `[]` for a media that already has `speech` (AU-111
    frozen) or is not in the snapshot (the core then refuses by name), else one
    `set_media_speech` from `spans(_:duration:)`; it refuses "<name> has no sound, so a clip
    cannot hide while it is silent." and "<name>'s speech has not been detected yet, so a clip
    cannot hide while it is silent. Try again in a moment." `problem(forMedia:)` is the same
    answer without reading the cache.
  - **`set_video`** reads one key: when `patch.hide_silent` is an object with a numeric
    `media`, it prepends `DuckSpeech.ops(forMedia:)` over the document's project, its refusal
    the tool's error, in the same undo step "Video Properties". Its description names
    `hide_silent`, its keys, defaults, ranges, the gate rule, that it is not animatable, the
    prepend and its refusals, and the UI path (the Picture sub-tab's Hide While Silent section).
- **CO-95 — The proof.** `tools/proof/co9_proof.py` (Release) with `co9_probe.swift`: Z1 no
  `Frame Job: ` line; H1 the rendered opacity 1 inside each widened span, 0 in a gap longer than
  pre-roll + hold + 2·fade, 0.5 at `e + hold + fade/2` and at `s − pre_roll − fade/2`; H2 after
  a `ripple_delete_ranges` through both tracks the gate follows the moved speech; H3 1 where no
  clip of the media plays; H4 `get_project`'s opacity un-gated where the render is 0; H5
  `remove_media {with_clips: true}` clears the gate and the camera shows; H6 `set_action_end`'s
  patch and `off` naming `video.hide_silent` refused in the sentence; H7 a camera nested apart
  from its microphone gated by the microphone in the enclosing container; H8 `set_video
  {hide_silent: {media}}` on a voice file saves `media[].speech` in the same step (one `undo`
  removes both), and a media with no sound refused in its sentence; probe P1 `ops(forMedia:)`'s
  four answers, P2 the candidates' order, P3 the section after Layout and its checkbox one undo
  step with the spans first. Seven mutants, each caught: pre-roll applied after the span (H1);
  spans projected at the gated clip's origin (H2); the gate multiplied in `evaluate_clip` (core,
  H4); `not_a_target`'s arm dropped (H6); only the layer's own container read (H7); the tool not
  prepending (H8); `remove_media` not clearing (H5). JOB-65 is the person's check of the fade.
