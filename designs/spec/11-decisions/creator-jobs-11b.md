# Spec §11 — decisions: Creator jobs, graphics re-laid onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-11.md`](creator-jobs-11.md), so a citation never has
to say which file. This file holds VR-42, VR-43, VR-44 and VR-47 (VR4b) and VR-50, VR-51, VR-52 and
VR-55 (VR5). The series goes on in [`creator-jobs-12.md`](creator-jobs-12.md), which is why this
file is lettered. It is new because `creator-jobs-11.md` had passed the spec's ~500-line split rule
(#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below" in one may now point
into a sibling file.

## VR4b — graphics re-laid (2026-11-03)

Recorded before the code. VR4b is the second half of VR4's split (VR4a's paragraph above): a
graphic the old canvas's size re-sized, the six road-map-10 templates measured by the short side,
a project's own old copies of them updated in a vertical copy, `make_vertical_version`'s graphic
counts, JOB-34's graphics half and JOB-35. No core, FFI, header, op, tool, `Kind` or format change
(43 stands; `OP_COUNT` 70; 125 product tools); nothing is sent anywhere, so nothing is keyed
(CJ-3). **The owner's answer of 2026-11-01 for VR4 (3):** a project's old template copies are
updated in a vertical copy, not only listed — VR-44.

- **VR-42 — A graphic the size of the old canvas becomes the size of the new one**
  (`VerticalVersion.swift`'s class 5, `VerticalVersion+Layers.swift`'s `graphicOps`).
  (a) **Class 5** (VR-33): a top-level clip whose source is `graphic` and whose graphic's
  `width` and `height` are EXACTLY the old canvas's W and H, each side compared, never the area
  (a 1080 × 1920 graphic on a 1920 × 1080 canvas is not class 5). It is tested in `role(of:)`'s
  first switch, after the backdrop test; every other graphic is class 6 and takes `keep` as
  before.
  (b) **The ops**, in step (4) (VR-34), each through `trial.require`, with rx = W′/W and
  ry = H′/H: `set_graphic {width: W′, height: H′}`; when the base x or y is non-zero,
  `set_video {x: x·rx, y: y·ry}`; for each action whose end's `video` names x or y,
  `set_action_end {video: {the named keys only, x·rx and y·ry}}` (no schema: the patch names no
  `graphic`). Scale, on the base and in every end, is never touched: the graphic is now the
  canvas's size, so its scale means what it meant. Step (3) skips class 5. A refusal answers
  "Make Vertical was refused at <op> for clip C: <reason>" and nothing is made. The entry is
  `resized`, with no reason.
  (c) Top-level clips only (VR-33): a nest's graphics are untouched. `set_canvas` still never
  re-lays out a graphic; only Make Vertical re-sizes one (amends **G-7**).
- **VR-43 — The six road-map-10 templates measure by the short side** (`lower-third`,
  `title-card`, `callout`, `bar-chart`, `counter`, `kinetic-type` in `graphic/tests/graphics/`).
  Each one's unit line `const u = ctx.height / 1080;` becomes `const u =
  Math.min(ctx.width, ctx.height) / 1080;` and nothing else changes. On a canvas at least as wide
  as tall `Math.min(w, h)` is `h`, so every landscape and square render is byte-identical
  (`graphic/tests/pins.rs` and `sandbox.rs` pass with no `GRAPHIC_REPIN`). The six stay in
  `common::FIXTURES`, outside G-44's title-safe tests (they enter from off-frame).
  `docs/graphics-api.md` recommends the same line. If a template with only its unit line changed
  still draws text outside a 1080 × 1920 frame, its fix is a branch on `ctx.height > ctx.width`
  that leaves every landscape and square value unchanged, recorded as a deviation.
- **VR-44 — A project's own copy of an old bundled template is brought up to date in a vertical
  copy** (`GraphicTemplates+Revisions.swift`, `VerticalVersion+Layers.swift`,
  `ProjectDocument+VerticalCopy.swift`).
  (a) **The table**, `GraphicTemplates.shippedRevisions`: the SHA-256 (lowercase hex) of every
  text of the six the app has bundled → its stem — each file at 601f4ee3 (G1c, unchanged through
  b0091535, G5b, the first bundling), at b71e20b5 (G-45's `meta`) and VR-43's text: 18 rows. The
  current text is in the table too, so a module already current is matched and skipped by its
  digest, and a test can hold the table to the tree. `measuresByHeight` is the regex
  `ctx\.height\s*/\s*1080\b` over a module's text.
  (b) **The survey** (`templateSurvey`, main): over `DerivedCarry.drawnGraphicNames` of the
  project, each name's scanned module. It is **outdated** when its revision is a table row for
  stem S and differs from the SHA-256 of the readable bundled `GraphicTemplates/<S>.js` — matched
  by revision, never by name. It **sizes by height** when no table row matches and
  `measuresByHeight` is true. No store: an empty survey.
  (c) **In a copy** (`verticalCopy`, after the unchanged-copy guard): each outdated module is
  rewritten with the bundled text through `GraphicStore.write(name:source:)`, then ONE
  `rescan()`, whose pass keeps the replaced text in the module's history (`keepReplaced`, G-29);
  a write that throws lists the module, "it could not be updated: <description>". Its doors are
  every door of the copy: File ▸ Make Vertical Version…, `make_vertical_version` and, later,
  FC9's short. **In place** (`copy: false`) nothing is written (a module write is not part of the
  step's undo, G-3) and each outdated module is listed, "it is an older copy of the bundled
  template "<S>"; Make Vertical updates it only in a copy". Both list each module that sizes by
  height, "it sizes itself by the canvas's height, so it may not fit the narrow frame". Nothing
  else is rewritten: a module matching no row, and the seventeen G-44 templates (already by the
  short side).
  (d) **The report** (`TemplateReport`): `updated` (names) and `listed` (`{name, reason}`), both
  by name. The sheet shows the predicted report (`templateReport(survey, copy:)`, the survey made
  once at `viewDidAppear`), the tool the one the copy made, or in place the predicted one.
- **VR-47 — VR4b's proof** (`vr4b_proof.py`; `graphic/tests/vertical_templates.rs`). **G1**
  `portrait_text_inside_the_frame`: each of the six with its default props at 1080 × 1920,
  frames 0, ⌊d/2⌋ and d−1, parsed by usvg over a font database holding exactly the bundled
  faces, the group opacities multiplied down the tree; a text node whose accumulated opacity is
  above 0 and whose stroke bounding box meets the frame lies inside [24, W−24] × [24, H−24].
  **G2** `landscape_and_square_unchanged`: each shipped text is the new text with the unit line
  put back, its SHA-256 the b71e20b5 digest; both drawn at 1920 × 1080 and 1080 × 1080 at every
  fifth frame and the last, BGRA byte-identical. **The trap**
  `revision_table_holds_every_current_template`: each of the six's current digest is a row of
  `GraphicTemplates+Revisions.swift` mapped to its stem. **G3** in place: one undo step "Make
  Vertical", a canvas-size graphic `resized` to 1080 × 1920 with its base and end x and y by the
  axis ratios and its scale unchanged, a 1080 × 1920 graphic (same area) and a 640 × 360 one
  `kept`, the summary's "Re-sizes 2 graphics". **G4** a copy: `graphics.updated` the two old
  copies, the module sizing by height listed, the copy's modules the tree's text with the old
  one kept, the source's modules byte-unchanged, a current one not updated. **G5** in place: none
  updated, the old copies listed with the in-place reason. **G6** (no app) the table's rows per
  stem are exactly the digests of the file at b0091535 and every later commit touching it, and
  of the working file. **Z0** the parity grep. Six mutants, each caught by its row:
  `graphic-area` (G3), `unit-line-left` (G1), `matched-by-name` (G4), `scale-by-keep` (G3),
  `in-place-rewrite` (G5), `current-outdated` (G4). **JOB-34**, its graphics half: re-sized
  graphics and updated templates look intended on 9:16 and 1:1. **JOB-35**: the vertical trial,
  VR-38's verdict.

**The answer and the summary** (VR-35, VR-36 as amended here). The summary adds, after " Removes
… ", " Re-sizes N graphic[s] to the new canvas." and " Updates N graphic module[s] to the
current template.", each only when non-zero, and after the caption lines one line per listed
module, `Graphic module "<name>" is left as it is: <reason>.` `make_vertical_version`'s answer
always has `graphics {resized, updated, listed [{name, reason}]}`, and `clips[].treatment` may be
`resized`.

**Amendments recorded by VR4b.**
- **VR-33** (5): built — a graphic exactly the old canvas's size is class 5 (VR-42 (a)).
- **VR-34**: step (4) gains class 5's ops (VR-42 (b)); step (6)'s graphics are VR-42 and VR-44.
- **VR-35**: the graphic counts and lines above.
- **VR-36**: treatment `resized`, and the answer key `graphics`.
- **G-7**: Make Vertical re-sizes a graphic whose size is the old canvas to the new canvas, as an
  explicit `set_graphic`; `set_canvas` still never re-lays out a graphic (VR-42).

**Deviations from the road map's draft, recorded before the code.** (1) VR-42's ends compose x
and y by `keep`'s axis ratios and leave scale as it is (the draft's "composed by keep" would apply
keep's min-ratio scale and shrink a graphic that already fills the new canvas). (2) The table
holds the current text too, so a module already current is skipped by digest and the trap can
check it. (3) G1 skips a text wholly outside the frame or at opacity 0 (lower-third's frame 0,
the outros' last frames). (4) The proof is VR-47 (`vr4b_proof.py`), not rows 7–9 of
`vr4_proof.py`; six mutants, not three.

## VR5 — screen recordings follow the cursor (2026-11-03)

Recorded before the code. A vertical version of a recording that carries a cursor file (CU1a,
CU-10) follows the pointer instead of a face; Follow Subject leaves such a clip out of what it
analyses. No FFI, header, `Kind` or format change (43 stands; `OP_COUNT` 70; the product tool
count unchanged); `reframe_clip`'s `follow` gains a member and `subjects` an optional key.
Nothing is sent anywhere, so nothing is keyed (CJ-3). **The owner's answers of 2026-11-01 for
VR5:** (1) a cursor-followed clip's own 16:9 auto zooms are REPLACED, not composed (VR-52); (2)
a screen and its camera in CO's layouts are re-laid in VR5b, not here — a screen behind a camera
takes VR-33's classes as before. VR-53 and VR-54 are VR5b's.

- **VR-50 — `follow: cursor`** (`reframe_cursor.rs`, new; `reframe_subjects.rs`, new;
  `edit_reframe.rs`). `subjects` gains an optional `cursor: [{t, x, y, click?, typing?}]`: `t`
  in forward-media source ticks, `x`, `y` 0…1 of the upright picture from its top-left (CJ-22),
  `click` and `typing` false when absent; `samples` and `shots` stay required, and a `cursor`
  entry that is not an object is refused by its path, as a box is. VR-26 (8) gains three
  refusals, each naming `cursor[i]`: more than `MAX_SUBJECT_SAMPLES` points, times not strictly
  increasing, and `x` or `y` outside 0…1.
  (a) **Points in clip time.** `cursor_in_clip_time` keeps the points in the clip's played window
  (`in_played_window`), maps each through `clip_time_of_source(…, Round::Down)`, sorts by (clip
  tick, media tick) and keeps one point per clip tick, the earliest media tick's, with `click`
  and `typing` OR'ed over the points merged into it.
  (b) **The window.** A point's source-canvas position is `Frame::point(t, x, y)` (the placement
  in force, VR-27 (a)); the desired window centre is `Frame::clamp` of it, with no headroom and
  no offset. The frame is `Frame::of` with `FramingRequest {zoom, from_* = the canvas}`;
  `frame.placed` is filled at the points' ticks as `plan_framing` fills it when the clip has
  actions.
  (c) **The first key** is at 0 on the first point's desired centre.
  (d) **The dead zone** (`CURSOR_TUNING`): ±0.20 of the window's width and ±0.12 of its height
  around the window's target (the centre the last key moves to), at 0.8 window widths a second,
  no headroom. `FRAMING_TUNING` is unchanged.
  (e) **A click arrives.** A point with `click` (a down click) whose desired centre lies outside
  the dead zone gets a move that ENDS on the click's frame (`snap_to_frame`), lasting
  `max(0.4 s, distance ÷ (0.8 window widths a second))`, planned to start no earlier than the
  last move's end, or 0. It starts at the first point at or after its planned start, so a move
  still running there shortens it; one that cannot last a frame is dropped, and the click is
  followed as any other point.
  (f) **Any other point** outside the dead zone starts VR-23's move (`ease_in_out`, `max(0.4 s,
  d ÷ speed)`) unless a move is running, it lies within 0.5 s of the last move's end with the
  point inside the window, the move would end after a pending click arrival's start, or the
  point is `typing` — a typing stretch holds the window; a click inside one still arrives.
  (g) **The keys** are on the canvas's grid, strictly increasing, none past the clip's end
  (`reframe_path.rs`'s `span`); `shows_fit` is false and `cuts` empty, so `where_empty` and
  `backdrop` never act on a cursor framing.
  (h) **Refusals.** `cursor` on a media clip whose media has no `cursor` is refused, "clip {id}'s
  media has no cursor file, so there is no cursor to follow; frame it with subject, center, fit
  or keep" (`no_cursor_file`), after the nest and still refusals, which name the following kinds
  and now name `cursor` too; with `subjects` absent, or no point in the played window, it is
  refused "no subjects" (VR-26 (10)), last, as today, so the tool's trial meets every other
  refusal with no file read.
  (i) **The app fills it** (`FramingCursor.swift`, new): the cursor file opened through
  `AutoZoom.cursorFiles` and `readTracks`, then per played window (`FramingAnalysis.windows`)
  CU-25's `path` at smoothing 0.5 and step `max(60_000, ⌈Σ window lengths ÷ 90_000⌉)` ticks, and
  `events {clicks, typing}`; each down click (`down == 1`) is inserted as a `click: true` point at
  its own `t` (a path point at the same `t` dropped); a point inside a typing stretch `[from, to]`
  gets `typing: true`; `x ÷ media.width`, `y ÷ media.height`, clamped to 0…1. `reframe_clip`'s
  tool reads the file instead of waiting for an analysis (no `waitForAnalysis`, `cached: true`),
  after the trial's "no subjects"; a missing or unreadable file is its refusal, in Auto Zoom's
  sentences.
- **VR-51 — A clip with a cursor file is never followed by faces.** `subject`, `face`, `person`
  or `salient` on a media clip whose media has `cursor` is refused, "clip {id}'s media has a
  cursor file, so it follows the cursor, not faces; frame it with cursor, center, fit or keep"
  (`cursor_not_faces`), after the nest and still refusals and before the matte refusal; a cursor
  in `subjects` is never read by a face follow. **Make Vertical** (VR-34 (3)), with a following
  Follow: a media picture whose media has `cursor` and whose media file is present is in
  `analysisTargets`' new `cursor` list and never analysed. With its cursor read it is framed
  `follow: cursor`, `replace: true` (VR-52); unread (the file missing or unreadable) it is framed
  `fit` with the backdrop, entry `not_followed`, reason "its cursor file could not be read, so it
  is shown whole". Center centres it as before, and a missing MEDIA file is still kept first.
  **Follow Subject** (VR-29) never analyses such a clip: `FollowSubject.analysed` (the targets
  whose media has no cursor) feeds the sheet's requests and `FollowSubject.subjects` skips it.
  The clip stays in the targets and the plan, so the core's VR-51 sentence is listed as its
  refusal. `FollowSubject.follows` and `make_vertical_version`'s `follow` gain no `cursor`.
- **VR-52 — A cursor-followed clip's own zooms are replaced in a vertical version.** Its
  `reframe_clip` carries `replace: true`, so its 16:9 auto zooms' and pans' `x`, `y` and `scale`
  leave every end and its base is fitted (VR-27 (g)); its counts are `FollowSubject.counts(…,
  replace: true)`. The summary adds, after the followed count, " Follows the cursor in N clip(s),
  their own zooms and pans replaced." when N > 0; `make_vertical_version`'s answer always has
  `cursor`, the clips followed by the cursor in id order (amends VR-35, VR-36).
- **VR-55 — VR5's proof** (`vr5_proof.py`; core tests `core/tests/reframe_cursor.rs`). The
  fixture: ffmpeg `testsrc` 1920 × 1080, 30 fps, 20 s, on a 1920 × 1080 canvas, and a v1 cursor
  file beside it, its path in media pixels at y = 540: x 400 → 1100 linearly over 0–8 s, held
  to 9.9 s, 1700 from 10.0 s (a down click at 10.0 s), held to 13.9 s, 300 from 14.0 s (a down
  click at 14.0 s), held to 16 s, 300 → 600 over 16–18 s with typed marks making one stretch
  16–18 s, held to 20 s; the Debug launch has `-RCDevAnalysisCanned YES`. **V1** in the 9:16
  copy every 10 Hz sample of the smoothed cursor in 0.5–8 s, placed through the copy's
  placements, is on the canvas and in the window's central 60 % of width. **V2** `reframe_clip
  {follow: cursor, zoom: 2}` and the copy each have a key ending on each click's frame, the
  window centred on the click's clamped point (±1e-6). **V3** with canned panning faces on the
  media the copy's clip `video` and `actions` equal the face-free run's, and `reframe_clip
  {follow: face}` is refused in VR-51's sentence. **V4** after `auto_zoom` on the clip the copy's
  clip has no end naming the auto zoom's scale, the answer's `cursor` lists it and the summary
  has VR-52's sentence. **V5** with the `.fjcursor` deleted the entry is `not_followed` with
  VR-51's reason and one "Blurred Background" sits on Backgrounds. **V6** no move starts inside
  16–18 s, and one starts after 18 s. **V7** Clip ▸ Follow Subject… on a fresh copy of the
  fixture with no analysis: within 10 s the sheet's summary carries VR-51's sentence, no
  Analyzing view is seen, `cache/analysis/` holds no file for the media and no undo step is
  added. **Z1** the parity grep. Six mutants, each caught: faces allowed on cursor clips (V3),
  the dead zone at 0.15 (core test 0.17 W), clicks ignored (V2), `replace` off for cursor clips
  (V4), typing ignored (V6 and its core test), `analysed` returning every target (V7).
  **JOB-36**: a screen recording's vertical version is readable on a phone (S-ST2's, skipped by
  name while it does not exist).

**Amendments recorded by VR5.**
- **VR-26**: `follow` gains `cursor` (after `salient`); (8) gains the cursor refusals; the
  following kinds' nest and still refusals name `cursor`; VR-51's refusal sits before (5).
- **VR-29**: a clip whose media has a cursor file is a target but is never analysed (VR-51).
- **VR-34** (3): a cursor picture is framed `cursor` with `replace: true`, or `fit` unread
  (VR-51, VR-52).
- **VR-35**, **VR-36**: VR-52's sentence and the answer's `cursor`.

**Deviations from the road map's draft, recorded before the code.** (1) The planner is a new
`reframe_cursor.rs`, not `reframe.rs`, which is past the cap; `Subjects` moves whole to
`reframe_subjects.rs` first. (2) `typing` is a point flag beside `click`, and a typing stretch
holds the window (the draft's "when keys were recorded"). (3) An unreadable cursor file shows the
clip whole (`fit`) rather than following faces, which VR-51 forbids. (4) Follow Subject's
analysis skip and proof rows V4–V7 are added; six mutants, not three.
