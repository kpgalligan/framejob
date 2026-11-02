# Spec §11 — decisions: Creator jobs, the cutout's edges onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md) and
[`creator-jobs-4.md`](creator-jobs-4.md) (CJ-, VR-, TX-, SW-, CU- and CO-), so a citation never has
to say which file; `creator-jobs.md` says what the road map builds and how its IDs are made (CJ-7).
This file is new because `creator-jobs-4.md` passed the road map's ~500-line split rule with CO3's
entries (620 lines, 2026-11-02); each phase's decisions are appended here from now on, before its
code.

CO-40…CO-42 are CO4's (the cutout's edges), recorded before its code. S-KEY1 (`samples/README.md`:
the owner before an evenly lit plain cloth) does not exist, so CO-S3 — whether the edge needs
refinement, and which — cannot run; the road map's head rule for that case is that r0 ships and
the row is owed. The owner's answer of 2026-11-01 for CO4: Best is **not** the default on a short
clip — Standard always, Best chosen per clip. No format bump, no `rc_*`, no core change, no new
tool, no shader change: two doc comments, the documents and the proof. Vision runs on the Mac, so
nothing here is keyed (CJ-3).

- **CO-40 — r0 is the edge; CO-S3 is owed.**
  - **What ships.** The edge is CO-27's r0 and nothing else: the mask's `.r` sampled bilinearly
    and remapped by `cutoutCover` (`Compositor.metal`), `c = 0.5 − 0.5·edge`, `w = 0.5 +
    0.5·feather`, `lo = clamp(c − w/2, 0, 1)`, `hi = clamp(c + w/2, 0, 1)`, `cover =
    smoothstep(lo, hi, m)`. No r1 (joint bilateral) or r2 (guided filter), no pre-pass, no
    `KeyReading` passed to a refinement (CO-7's clause on a refinement's guide has nothing to
    read yet), no new uniform, no core constant; `LayerUniforms` stays at 160 floats.
  - **The documented amount (the contour rule).** At Feather 0 the outline — where coverage is
    one half, the midpoint of `smoothstep(lo, hi, ·)` — lies at the mask value **m½(e)**: `0.5 −
    0.5·e` for |e| ≤ 0.5, `0.375 − 0.25·e` for e > 0.5 (`lo` clamped at 0), `0.625 − 0.25·e` for
    e < −0.5 (`hi` clamped at 1). At e = −1, −0.5, 0, 0.5, 1 it is 0.875, 0.75, 0.5, 0.25,
    0.125. On a mask edge that rises linearly over R display pixels, Edge +1 moves the outline
    3R/8 outward from Edge 0 and −1 moves it 3R/8 inward; coverage is non-decreasing in `edge`
    at every mask value, so a larger Edge never draws less. This is what Edge means until a
    refinement replaces it; the guide states it in words, and `co4_proof.py` E4 measures it.
  - **CO-S3 runs when S-KEY1 exists**, unchanged: its rule as CJ0a pinned it (`rule_sha256`
    `84ae691664c9d8293b50f70e1f332e68a032984da4f2ae65500561f152e9319f`), after CO-S1's owed
    S-KEY1 rows. A refinement it picks is a new phase, with its own decisions, its own proof
    (CO4's E1–E3: B on S-KEY1's composites against CO-S3's, the same in an HLG project, the
    preview's cost bound) and its own mutants; until then E1–E3 are skipped by name and owed.
- **CO-41 — No Best yet; Best is never a default.** CO-S1 kept no Best (its rule (d) needs
  S-KEY1), so there is no `masks_best` kind, no Quality row (CO-30 stands) and `best` stays
  refused in CO-20's sentence ("video.cutout.quality must be standard: Best masks are not made
  yet") until CO-S1 (d) keeps Best on S-KEY1. When Best exists (the owner, 2026-11-01): Standard
  on every clip, Best only when chosen per clip, with no rule that picks it by duration.
- **CO-42 — CO4's proof.** `co4_proof.py`: B0 its probe (`co2a_probe.swift`, whose `pack` mode
  gains the `ramp` kind: every mask 512 × 288, column i `round(255·clamp((i − 240)/32, 0, 1))`)
  builds; E1, E2 and E3 skipped by name while `tools/proof/media/creator/S-KEY1/` is absent, and
  each a scored failure once it exists; E4 the documented amount on a 1920 × 1080 transparent
  canvas — the bar code at scale 1 over a canned `ramp` pack (a ramp of 32 texels, 120 display
  pixels), at Edge −1, −0.5, 0, 0.5 and 1, Feather 0: on rows 100, 540 and 980 the contour where
  alpha crosses 127.5 within 1 px of `3.75·(240.5 + 32·m½(e))`, and Edge 0 → +1 and −1 → 0 each
  45 ± 1 px; E4r the order on real masks — `push_1080.mov`'s, made by `get_media_analysis` — at
  Edge −1, 0 and +1: alpha non-decreasing in `edge` at every pixel within one level, and the
  count of pixels with alpha ≥ 128 strictly increasing; Z1 each launch's log free of `Frame
  Job: `. Two mutants on Release: Edge's sign reversed (E4, E4r) and `lo`/`hi` unclamped (E4).
  JOB-60 (`docs/manual-checks.md`) is the person's look at real edges.

CO-50…CO-56 are CO5's (Text Behind Subject), recorded before its code. The owner's answer of
2026-11-01 for CO5: Behind Subject is **a clip flag**, not a track flag — a title is placed per
moment, and a track flag would catch every later clip on the track. Nothing here sends anything:
Vision's masks are on-device, so no `ModelKeys` row (CJ-3). No `rc_*` export and no new op: the
tool is an app-state composite of ordinary ops (CJ-8 (f) not needed, no rule must hold inside the
core).

- **CO-50 — Behind Subject is a per-instant relation, drawn by the matte machinery.**
  `video.behind_subject: true` on any drawing clip but an adjustment or nest clip (CO-52). At each
  instant the recipe (`recipe_subject.rs`, called once from `recipe.rs` after the mattes and the
  routed dissolves and before Show Selection) reads it over the covering instances:
  - **A subject** is an instance whose layer's `cutout` is non-null and which is not drawn into a
    matte, `background` `remove` or `keep` alike. **A behind layer** is an instance not drawn into
    a matte and not an adjustment clip whose `evaluate_clip(clip, clip_t).video.behind_subject` is
    true. Nothing is evaluated unless some layer's `cutout` is non-null.
  - **Subject L is behind B** when, with d = B's nest depth, L is at least as deep, L's first d
    enclosing nest clips are B's (by id), and L's level-d track — its own track when L's depth is
    d, else the track of L's d-th enclosing nest clip — has a lower index than B's track in that
    container's tracks (the timeline's at d = 0, else B's innermost nest's). So a subject inside a
    nest on a track behind a top-level title cuts it, and a top-level camera never cuts a title
    inside a nest. No clip names another, so split, move, paste, nest and undo cannot break it.
  - **Ids.** A subject is listed only when at least one behind layer is cut by it. Listed subjects
    take group ids n, n + 1, … in instance order, n one past the largest id any layer's `matte`
    names (0 when none), so the track groups keep their ids and order. Each behind layer's
    `matte` becomes `{into: null, cut: [the ids]}` or gains them, ascending; each subject's entry
    `{group, mode: "alpha_inverted"}` is appended after every track group in `mattes`. The cuts
    multiply (MT-2 as amended). The behind clip's own shadow and reflection are cut with it, as a
    matte cuts them (MT-3).
  - A frame with no behind layer cut by a subject is byte-identical to the frame without the
    relation: `frame_mattes` is untouched, and the inputs come back as they went in.
- **CO-51 — The subject copy, MT-4's third override.** A listed subject is drawn into its group by
  a COPY of its layer inserted directly after it: the original layer object with exactly `blend:
  "normal"`, `shadow: null`, `reflection: null`, `cutout.background: "remove"`,
  `cutout.subject_copy: true` (appended to the cutout object) and `matte: {into: s, cut: <the
  original's track-matte cut>}`; every other key kept, the layer's 28 keys unchanged. It is the
  recipe's THIRD deliberate override of model values, after a transition's `normal` and a matte
  layer's (MT-4). Its Show Selection fact is drawn-into, so `behind` keeps it.
  - **A copy whose mask is not drawn draws nothing** (`CompositorEffects.prepare`): pending, no
    person found, a coverage miss or a slate leave the behind clip whole, never cut by the
    whole camera picture.
  - **Its transition is weighed with no partner correction.** A copy keeps its original's
    `transition` and `dissolve` (dropping them would lose a zoom's scale and a push's offset), but
    `prepare` looks up no partner for it, as `partnerBox` already does for a cut-out partner on
    the canvas (CO-27): an unrouted `cross_dissolve` or `zoom` half's copy weighs `(1 − p)` going
    out and `p` coming in, so a cut-out camera dissolving into an uncut clip fades its subject
    out of group s. A routed half (MT-8) is a run in s whose missing half `encodeDissolve` draws
    as a cleared target, so it mixes to `(1 − p)·out` or `p·in` with no change. Push, slide, wipe
    and fade are per-layer weights and offsets, the same on the canvas and in s. Each copy
    directly follows its original, so `layers.first { $0.clip == partner }` still finds an
    original's partner, and an original's lookup is unchanged.
  - The copy's canvas box duplicates its original's and the hit test answers the same clip; no
    cursor, hit-test or selection-overlay change. `MattePlan.swift`, `Compositor+Matte.swift`,
    `MetalRenderer.swift` and `CutoutWants.swift` are unchanged: a subject group is an ordinary
    group listed after the track groups, and a copy's masks are wanted because it has
    `background: remove`.
- **CO-52 — `video.behind_subject` (format 40).** A boolean after `cutout`, written only when true,
  so every file without it is the text it was; no migration. The bump is so an older build
  refuses a file with the flag instead of dropping it on save. `set_video` and `paste_attributes`
  refuse it on an adjustment clip ("clip N is an adjustment clip and cannot be put behind a
  subject") and on a nest clip ("clip N shows a nest and cannot be put behind a subject")
  (`cutout_check.rs`'s `check_behind_subject_clip`, in `settle_video` after the cutout's clip
  check); a file's flag on an adjustment clip is ignored by the recipe. A boolean, it switches at
  an action's end (§5.4), never refused there. `add_blurred_background`'s copy drops it.
  `background: keep` draws the camera whole on the canvas and still makes it a subject, so the
  title is hidden behind the person while the room stays.
- **CO-53 — The planner, and Insert ▸ Text Behind Subject.** `BehindSubjectPlan.swift`, pure over
  a snapshot, a playhead, the selection and an optional clip, top-level only.
  - **Candidates at `at`:** top-level clips with start ≤ at < end that `CutoutStatus.canCutOut`,
    with `enabled.video`, on a track neither hidden nor a matte track. **The pick:** the named
    clip (refused "Clip N cannot have a title put behind its subject: it must be a clip of a
    video file on the timeline, on a shown track that is not a matte track." when it is not a
    candidate kind, "Clip N does not play at T: pass an at inside it." when it does not play at
    `at`); else the front-most selected candidate; else the front-most candidate with a base
    cutout; else the front-most; none refused "No clip of a video file plays at T on a shown
    track that is not a matte track, so there is no one to put the title behind.".
  - **The track:** a new track named "Behind Subject" at 1 + the index of the front-most track of
    the unbroken run of matte tracks directly in front of the clip's track, or of the clip's own
    track when that run is empty — so it sits behind an ordinary track or at the front and no
    matte targets it (MT-2): with `[V, M1→V, M2]` it goes to index 3, not 2.
  - **The ops, one undo step "Text Behind Subject":** `add_track`, `add_text_clip` (the Title
    preset; `content` when given) at `at` for min(4 s, the clip's end − at), `set_video
    {behind_subject: true}` on the title, and, only when the clip has no base cutout, `set_video
    {cutout: {background: keep}}` on it — the camera stays whole and still hides the title.
  - **The menu item** is Insert ▸ Text Behind Subject, last in the menu, no key equivalent; off
    with a nest open or with no plan. It applies through `applyEdit` and selects the new clips.
- **CO-54 — `text_behind_subject {clip?, at?, content?}`.** An app-state tool (no `scope`), on the
  main thread, mirroring Insert ▸ Text Behind Subject: refused with a nest open
  ("text_behind_subject works on the top-level timeline: set_scope with no nest first."); `at` in
  ticks, else the playhead; `clip` an id; `content` a non-empty string ("content must not be
  empty"); a planner refusal answers its sentence; one undo step through `performGroupedEdit`, the
  selection untouched. It answers `{ok, clip, track, text, duration, cutout_added, project}`. No
  key gate (CJ-3). `set_video`'s description names `behind_subject` and the clip kinds of `cutout`.
- **CO-55 — The Behind Subject section.** In the Clip tab right after Transform, shown when no nest
  is open and no adjustment or nest clip is selected: a checkbox "Behind subject" writing `video
  {behind_subject}` (an end inside an action), one undo step "Behind Subject", mixed over a
  selection that disagrees; Reset writes false; its summary "on" or "off". With one clip selected,
  its flag on, and no cut-out clip behind it at the playhead (the document's recipe there names no
  subject group in its `matte.cut`), a note: "No cut-out clip is behind it at the playhead."
- **CO-56 — The proof, its mutants and JOB-63.** `co5_proof.py` with `co5_probe.swift`: P1 (the
  planner: pick order, min(4 s, rest), the index above a matte pair and above `[V, M1→V, M2]`, the
  three sentences, 3 or 4 ops, `isCutBySubject`); B1 (a full-canvas opaque shape with the flag in
  front of a cut-out `barcode.mov`: all-255 3×3 mask neighbourhoods equal the frame with the shape
  hidden, all-0 the frame with the camera hidden); B2 (a cut-out camera in front does not cut);
  B3 (split, move and undo keep B1's answer); B4 (`background: keep`); B5 (the shape's blur-0
  shadow cut with it); B7 (`play_preview` composes ≥ 95 % of the flag-off frames, median of
  three); B8 (menu and tool give equal projects, one undo each); B9 (a coverage miss leaves the
  shape byte-identical to flag-off); B10 (a cut-out camera cross-dissolving into an uncut clip:
  at p = 0.5 over all-255 the mean of flag-off and shape-hidden within ±3); Z1 (parity logs
  empty). Seven mutants: front-subjects (B2), copy-shadow (B5), three-steps (B8), miss-whole (B9),
  copy-partner (B10), one-matte-skip (P1) and listed-uncut (`behind_subject.rs`'s b6). **JOB-63**:
  a person's look, on S-TH1, at the halo where the soft edge meets the letters.
