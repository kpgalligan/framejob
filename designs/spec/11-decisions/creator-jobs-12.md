# Spec §11 — decisions: Creator jobs, camera layouts in a vertical version onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) …
[`creator-jobs-11.md`](creator-jobs-11.md) (CJ-, VR-, TX-, SW-, CU-, CO- and FC-), so a citation
never has to say which file; `creator-jobs.md` says what the road map builds and how its IDs are
made (CJ-7). This file is new because `creator-jobs-11.md` reached 504 lines with VR5's entries,
past the road map's ~500-line split rule; each phase's decisions are appended here from now on,
before its code.

## VR5b — a screen and its camera re-laid in a vertical version (2026-11-03)

Recorded before the code. In Make Vertical Version, a camera and the screen behind it arranged
with Clip ▸ Camera Layout ▸ keep their switches: each switch is recognised on the old canvas and
solved again on the new one, never reframed, followed or given a backdrop. No FFI, header, op,
tool or `Kind` change, and no format change (43 stands; `OP_COUNT` 70; 124 product tools);
`Kind::Follow` gains a member. Nothing is sent anywhere, so nothing is keyed (CJ-3). The owner's
answer of 2026-11-01: Side by Side becomes Stacked on a tall canvas (*yes*); VR5's answer stands
(a screen with its camera is re-laid here instead of following the cursor).

- **VR-53 — A layout role is re-laid, not reframed.**
  (a) **Class 2b.** VR-33 gains class 2b, checked after class 2 and before class 3: a top-level
  clip holding an action `action_class::is_layout` recognises (all six placement keys, CO-63).
  **Pairing** is CO-64's front/behind: a camera action at absolute time T pairs with the layout
  action starting at T on the front-most track behind it that holds one. A 2b clip is a SCREEN
  when a 2b clip on a track in front of it holds a layout action at the same absolute start as
  one of its own, else a CAMERA. A **piece** is a picture clip whose source is the same source
  as a 2b clip R's (`same_source`: the same kind and the same `media` for a media, still or
  image source, or the same nest id; `in`, `at` and `reversed` ignored — Swift twins it, never
  through `ClipSnapshot.source ==`, which compares `in`) on R's track, starting after R's layout
  action at T and before the track's next layout action, whose base six keys are `alike` (b)
  that action's end: a cut piece of a laid-out recording, CO-61's reach (`split_clip` bakes the
  evaluated state into the second half's base and advances its `in`). A piece that is not itself
  2b is role `layoutPiece`. A 2b clip can also be a piece of an EARLIER switch (a recording split
  before a later switch): its base is re-based by that switch's replay and its own actions by its
  own switch. A clip of other media laid out only by a reach is NOT a piece and takes VR-33's
  other classes — a recorded limit.
  (b) **`reframe_clip {follow: "layout"}`** on a camera clip. The GROUP is the closure over
  pairing from it (cameras ⇄ their screens), plus the pieces of every switch. Each camera
  action's switch (its camera end, the paired screen end or none) is recognised by
  `layout_recognise.rs`'s `recognise` on the AUTHORED canvas, `from_width` × `from_height` (the
  canvas when absent): the candidates in order — `corner` × the shapes (square, rounded, circle)
  × the corners (bottom right, bottom left, top right, top left), `side_by_side`, `stacked` (both
  skipped with no screen), `camera_full`, `screen_only` — each solved by `layout.rs`'s
  `camera_placement` with `focus` = `focus_of` the camera end (`((l − r)/2, (t − b)/2)` of its
  crop) and `kept` = the camera end, and `screen_placement`; the first candidate `alike` on both
  ends wins. `alike` is x, y, the four crop edges and the radius within `RECOGNISE_PX` (1 px) and
  scale and opacity within `RECOGNISE_RATIO` (0.001). Then every group clip and piece takes
  `keep`'s per-axis rescale (`rescale_video`, from `from_*`) of its BASE only, the group's layout
  actions are removed, and the switches are replayed in time order through `edit_layout.rs`'s
  composition (`compose_switch`, the body after `switch_layout`'s refusals, extracted unchanged)
  at the camera action's absolute start, with the duration and curve `switch_timing` answers —
  those of the switch's longest role action whose `start` is not 0 in its clip, else the camera
  action's (so a camera starting after its screen keeps a one-frame cut while the screen glides,
  and the replay's clip-end and next-action clamps re-apply). `focus` is `focus_of` the old
  camera end — the old layout's CLAMPED crop centre, not CO-70's focus: a replay into a layout
  with more crop room (Side by Side → Stacked for a portrait camera, Side by Side on 1:1 for a
  landscape one) crops nearer the centre than a direct switch with the original focus would — a
  recorded limit. `side_by_side` is replayed as `stacked` when the canvas is taller than wide (a
  square keeps it; 4:5 is taller). Each role's later clips are that switch's pieces (looked up in
  the current project) and no clip ends its reach. After the replay, every other moving end of a
  group clip or piece (a zoom: `moves && !is_layout`) is `conjugate`d from the old placement in
  effect at its start (the latest old layout end starting at or before it, else the old base) to
  the new one (the replayed end, else the new base): with `r = new.scale / old.scale`, each key
  the end names is written `x' = new.x + r·(x − old.x)`, `y' = new.y + r·(y − old.y)`,
  `scale' = scale·r` (clamped to `SCALE_MIN…SCALE_MAX`), so the zoomed picture point keeps its
  place in the picture (`keep`'s per-axis rule would move a {2, −400, −200} zoom on a Corner
  screen about 243 px on 9:16). CO-62's refusals are not run again: each switch passed them when
  it was made.
  (c) **Refused**, in order, after VR-26's (1)–(2): no layout action on the clip, "clip {id}
  holds no camera layout to re-lay; frame it with subject, center, fit or keep"; a group clip
  that is both a camera and a screen, "clip {id} is laid out both as a camera and as a screen, so
  its layouts cannot be re-laid; keep its clips as placed"; an unpaired screen action (the
  earliest), "clip {id}'s layout action {a} at {tc} has no camera switch in front of it, so it
  cannot be re-laid; keep its clips as placed"; the first unrecognised switch in time order (the
  camera's action on a camera end no candidate matches, the screen's when some match the camera
  end but none the screen end), "clip {id}'s layout action {a} at {tc} is not a camera layout
  Frame Job made on the {W} × {H} canvas, so it cannot be re-laid; keep its clips as placed"
  (`tc` the absolute start as `layout_timecode`, W × H the authored canvas); then a composed op's
  own refusal. `layout` reads no `zoom`, `where_empty`, `backdrop`, `replace` or `subjects` (a
  value that cannot be read is still an `Err`), and skips refusals (5) and (6) as `keep` does.
  (d) **Make Vertical's step 3b**, run first after `opening`: one `reframe_clip {follow:
  "layout", from_width, from_height}` (the old canvas) per `layoutCamera` in id order, skipped
  when an earlier 3b op already changed it. Every clip a 3b op changed (its `ClipSnapshot`
  differs before and after) is DONE: entry `relaid`, skipped by steps (3) and (4), never followed
  (classes 3 and 6, VR-51) and given no backdrop. A refused op is not a stop: after the loop
  every 2b role and piece not done takes `keep` (a refused `keep` stops the step, VR-34) with
  entry `not_followed` and reason "its camera layout was edited by hand, so it is kept as
  placed".
- **VR-54 — The summary and the answer.** The summary's first line gains, after the cursor
  sentence, " Re-lays N camera layout(s) for the new canvas." (`counted(n, "camera layout")`),
  then one line per re-laid switch straight after the first line: "Re-laid: Side by Side →
  Stacked at <tc>.", or "Re-laid: <name> at <tc>." when the layout is unchanged (`<name>` a
  corner's `CameraLayoutShape.menuTitle`, else `CameraLayoutKind.title`; `<tc>`
  `ReelTime.format(at, fps:, frames: canvas.timecodeFrames)`). `make_vertical_version`'s answer
  always has `relaid: [{camera, at, from, to, shape?}]` in time order then camera id — `at` in
  ticks, `from` and `to` `switch_layout`'s `layout` words, `shape` only when `from` is `corner`
  — and `clips[].treatment` gains `relaid`. `from` is `VerticalVersion.layoutName` of the
  camera's OLD action end on the old canvas: a naming twin for ends the core has already
  recognised, never a decision (no FFI answers recognition) — opacity < 0.5 is `screen_only`;
  |x|, |y|, every crop edge and the radius < 0.5 is `camera_full`; a `canvasRect` within 0.25 W
  + 1 × H/3 + 1 is a corner (circle when a crop edge > 0.5, rounded when the radius > 0.5, else
  square; the corner by the signs of x and y); else `stacked` when the rect's midY > H/2 + 1,
  `side_by_side` otherwise. `to` is `stacked` for a `side_by_side` on a taller canvas, else
  `from`'s layout.
- **VR-56 — VR5b's proof** (`vr5b_proof.py`, `vr5b_probe.swift`; core tests
  `core/tests/reframe_layout.rs` and `core/tests/layout.rs`). The fixture: two ffmpeg `testsrc`
  1920 × 1080 30 fps 30 s movies, the screen on "Screen", the camera on "Camera" in front, canvas
  1920 × 1080, `switch_layout` Corner at 0, Side by Side at 10 s for 1 s `linear`, Camera Full at
  20 s. **R1** the 9:16 copy holds per role three layout actions at the old starts, durations
  and curves, each end equal to a reference project made at 1080 × 1920 with Corner, Stacked and
  Camera Full; **R2** the 1:1 copy equals its 1080 × 1080 reference with Side by Side kept;
  **R3** no role clip has an action whose end is exactly {scale, x, y} or a "Blurred
  Background", Backgrounds is removed and both entries are `relaid`; **R4** the screen split at
  25 s by `split_clips`, then the Side by Side camera end's x moved 40 px by `set_action_end`:
  `reframe_clip {follow: "layout", from_width: 1920, from_height: 1080}` is refused in VR-53's
  sentence naming that action, and Make Vertical lists the camera, the screen and the split half
  (classed `layoutPiece` by Swift's `sameSource`) `not_followed` with the hand-edit reason, none
  with a framing action; **R5** `render_frame` at 5 s, 15 s and 25 s of the 9:16 copy equals the
  reference's byte for byte; **R6** the summary has " Re-lays 3 camera layouts" and the three
  lines (Corner; Side by Side → Stacked; Camera Full), and `relaid` their four fields; **R7**
  (the probe) `layoutName` of every `menuRows` end the core makes on 1920 × 1080 and 1080 × 1080
  (1920 × 1080 and 1280 × 720 cameras) is that row, and `isLayoutAction` is true for each and
  false for a zoom end; **Z1** the parity grep. Seven mutants, each once on the final
  instrument: class 2b checked after class 3 (R3); Side by Side kept on a tall canvas (R1 and a
  core test); the tolerance widened to 50 px (R4 and a core test); the old `duration` dropped for
  the 0.5 s default (R1 and a core test); the replay's later clips left as `role()`'s unfiltered
  reach (the core piece test); zoom ends rescaled by `keep`'s per-axis rule instead of
  `conjugate` (the core zoom test); the switch's duration and curve taken from the camera's
  action (the core late-camera test). **JOB-39**: a screen recording with its camera in Side by
  Side, made vertical — the stacked version reads well on a phone (S-ST1's, skipped by name
  while it does not exist).

**Amendments recorded by VR5b.**
- **VR-26**: `follow` gains `layout` (after `cursor`), VR-53 (b)'s replay and (c)'s refusals;
  `from_*` is read by `keep` and `layout`.
- **VR-33**: class 2b and its pieces (VR-53 (a)), between classes 2 and 3.
- **VR-34**: step 3b, first after `opening` (VR-53 (d)); steps (3) and (4) skip what it did.
- **VR-35**: VR-54's sentence and lines.
- **VR-36**: the answer's `relaid` and the treatment `relaid` (VR-54).

**Deviations from the road map's draft, recorded before the code.** (1) `recognise` lives in a
new `layout_recognise.rs`, not `layout.rs`, which is at its 400-line cap. (2) No `through`:
explicit pieces instead — a `through` at the next switch would leave a screen piece unreached
when the next switch had no screen, and none at all would re-base a later B-roll CO8's `through`
had kept out. (3) Members' bases take `keep`'s per-axis rule and their zoom ends `conjugate`.
(4) Each switch's timing is `switch_timing`'s, not the camera's action alone. (5) The
camera/screen pairing and the pieces (`same_source`, which ignores `in`). (6) The Swift naming
twin `layoutName` (no FFI exists to answer recognition). (7) Seven mutants, not four.

**Recorded after the code.** (8) VR-56's one-key test moves each crop edge on an axis the
camera's crop has no room on — left and right in Stacked, top and bottom in Side by Side, for a
1280 × 720 camera on 1920 × 1080. On an axis with room, recognition reads the crop's own centre
as the focus (VR-53 (b)), so a 2 px move of one edge re-centres the solve by 1 px and leaves
each edge 1 px off, inside `RECOGNISE_PX`: such an end is re-laid as a CO-70 focus — a recorded
limit of the tolerance, not a refusal.

## CO10b — Remove Background and Behind Subject on pictures (2026-11-04)

Recorded before the code. CO10b is the second half of CO10's split (CO-102): CO10a settled the
model, the recipe's image arm and the mirror (CO-100…CO-104, `creator-jobs-5.md`); this phase makes
an image clip's masks, waits for them, draws them, and lets the UI and the tools treat pictures as
cut-out clips. The owner's answer of 2026-11-01 for CO10 stands: pictures are in this road map,
built last in CO. No core, FFI, header, op, tool-count or format change: format 43 stands, there
are 124 product tools, and nothing is sent anywhere, so nothing is keyed (CJ-3).

- **CO-105 — A picture's masks.** One mask per image media and subject kind, in CJ-22's store: the
  `masks` kind for `person` (`AnalysisMasks.vision` and `parameters` unchanged — a media id is
  either a movie or an image, so the two never share a marker) and a new kind `foreground`
  (`cache/analysis/foreground/<media>.json` and `/masks.pack`, version 1, the picture queue, margin
  0, files `[masks.pack]`, grid `AnalysisGrid(media:)`) for `foreground`. Its stamp's `vision` is
  `{request: "foreground_instance_mask", quality: "none", revision: 1, rate: "one", read_size:
  "image"}`, its device the one a fresh request pinned to the GPU reads back
  (`AnalysisMasks.foregroundDevice`), and its parameters `request`, `revision`, `output`
  `scaled_one_component_8`, `rate` `one`, `read_size` `image_8192`, `found` (as `masks`),
  `compression` `lzfse` and `pack_version`. The job (`AnalysisMasks.runImage`,
  `AnalysisMasks+Image.swift`) decodes the file through `MediaImporter.decodeImage(url,
  maxPixelSize: LayerRenderers.maxTextureSide)`, the decode every `LayerRenderers.image` arm
  draws from, upright; a nil decode throws "the picture could not be decoded". Progress is 0, then
  1 after Vision; a cancel before Vision answers false. Each request is fresh and pinned, performed
  on `VNImageRequestHandler(cgImage:options: [:])`, and refused when its device is not the
  stamp's: `MaskError.device` for person, `ForegroundMaskError.device` ("the foreground mask
  request ran on <named>, not <foregroundDevice>") for foreground.
  - Person: `VNGeneratePersonSegmentationRequest` `.balanced`, revision 1, 8-bit, at Vision's own
    size.
  - Foreground: `VNGenerateForegroundInstanceMaskRequest` revision 1, its observation's
    `generateScaledMaskForImage(forInstances: allInstances, from:)` at the read size (the decoded
    picture's), each float stored as `UInt8(clamp((v·255).rounded(), 0, 255))`.
  - No observation, or no instance: an all-zero mask at the read size (for person, with no
    observation, the decoded picture's size).
  - The mask is LZFSE'd, `found` is `MaskPack.found`, and the pack holds one frame `(pts 0,
    index 0, slot 0)`, published through `AnalysisStore.publishFile(kind: request.kind, covered:
    [0...0], files: [masks.pack])`.
  - `analysisInput` answers `(nil, false)` for a media that is not a video, with no asset made:
    a picture is read direct.
  - `get_media_analysis` lists and accepts the kinds of `AnalysisKind.mediaAnalysisKinds` only
    (every kind but `foreground`), in its `kind` enum and its check; an image is still refused
    there ("no moving picture"). A picture's masks are `analyze_cutout`'s.
- **CO-106 — The wants.** A cut image clip, top-level or nested, whose BASE cutout is set gets one
  window `[0, 1)` of its image (`CutoutWants.imageWindows`), its kind `CutoutWants.kind(of:)` —
  `foreground` exactly when the clip's source is an image and its base cutout's subject is
  `foreground`, else `masks`. Its need is `0...0`.
  - Top-level clips are taken when `[start, start + duration)` meets the range (none: always);
    nested ones are always taken.
  - `frameWindows` adds the recipe layers with `background` remove, `mask.kind` image and source
    `.image(mask.media)`, as `(layer.clip, media, 0, 1, kind)`, the kind from the mask's subject.
  - `CutoutWants.wants` runs the keep rule and `requests` once per kind present (`masks` first),
    each over `AnalysisLane.openRequests(kind:)`. Its three callers — the document's one owner
    (`ensureMasks()`, which adds the image windows), the export (`waitForMasks`) and the frame
    (`waitForFrameMasks`) — want both kinds in one `want`, since `want` replaces an owner's set.
  - The export's and the frame's waits go kind by kind: stamps and the uncovered set are keyed by
    (kind, media), and every `cutoutFailed` names the failing window's clip and, from its kind,
    `foreground:` — "Clip N's foreground masks could not be made: <why>." for a foreground
    window, the person sentence byte for byte otherwise.
  - `render_frame`'s uncut sentence for a foreground picture is "Clip N is drawn uncut: its
    foreground masks were not ready within 30 s."; every other clip keeps its sentence. Save
    Frame's sheet reads "<names> drawn whole: the <noun> were not ready within 30 seconds.", the
    noun "person masks" when no uncut clip is a foreground picture, "foreground masks" when every
    one is, and "masks" otherwise.
  - `analysis_job`'s `mask_wants` rows carry `kind`.
- **CO-107 — The draw.** `cutoutMask`'s `.image` branch requires `background` remove, `mask.kind`
  image, a layer source `.image(m)` with `m == mask.media`, a project, a cache folder and a URL.
  It looks up `CutoutMasks.pack(kind: subject == foreground ? .foreground : .masks, …)` — the
  packs and the stamp memo keyed by kind too — then `found(pack, clip: layer.clip, window:
  0...1)` and `CutoutLookup.slot(… sourceTick: 0, pivot: nil)`, and binds the mask at
  `texture(4)` with the media branch's uniforms. The shader is unchanged: the mask is in display
  orientation, as the decode is. A publish of either kind refreshes the paused frame
  (`EditorViewController+Cutout`) and the Background section's Memo. The media branch and
  `CutoutLookup` are unchanged.
- **CO-108 — The UI and the tools.**
  - `CutoutStatus.canCutOut` takes an `.image` clip of a media whose kind is `image`, so Clip ▸
    Remove Background, the Background section and Behind Subject's candidates take pictures.
  - Status: an image's frames are 1, its windows `imageWindows`'. A found-false pack answers
    `no_person` for person and the new `CutoutState.noSubject` ("No subject found";
    `analyze_cutout`'s `no_subject`) for foreground; a failure's sentence names "foreground
    masks" for a foreground picture. `Detail` carries its kind; `ownerRequests` and `stamp` take
    it.
  - The Background section gets **Subject** (Person, Foreground) right after its checkbox, shown
    only when every selected clip is a picture (`allPictures`) and enabled while `allCutOut`. It
    writes per clip `VideoPatch(cutout: .some(the base cutout with that subject))` through
    `binding.ops(video:for:)`, so the write lands on the base and the row is ⊘ inside an action,
    as the checkbox is; it reads mixed when the base subjects differ; undo name "Cutout Subject".
    `ClipPane.structureSignature`'s cutout cell is `cutout-image` when `allPictures`. Analyze
    Now's tooltip reads "Make this clip's masks now, again after a failure".
  - `analyze_cutout` drops CO-103: a named image clip is answered, and the default set is every
    cut clip of the open scope in timeline order.
  - Descriptions: `set_video`'s `cutout` drops "kept but not drawn yet" and says an image's masks
    are made from its picture (person segmentation, or for `foreground` the foreground instance
    mask) as soon as it is set, with `analyze_cutout` answering where they stand;
    `analyze_cutout` adds pictures, `no_subject` and a picture's one frame; `text_behind_subject`
    says "a clip of a video file or a picture"; `render_frame` says "A clip with set_video cutout
    waits up to 30 s for its masks (a picture with subject foreground, its foreground masks; any
    other, its person masks); past that …".
  - Behind Subject's two sentences: "No clip of a video file or picture plays at T on a shown
    track that is not a matte track, so there is no one to put the title behind." and "Clip N
    cannot have a title put behind its subject: it must be a clip of a video file or a picture on
    the timeline, on a shown track that is not a matte track." A planned cutout stays
    `{background: keep}` (person) on a picture too.
- **CO-109 — CO10b's proof, its mutants and JOB-66.** `co10_proof.py` over two launches. Launch
  H (`-RCDevAnalysisHold 3600`): S2 and S3 as CO-104; S4 one `render_frame` with a `foreground`
  image cutout answers in 25–45 s with that clip's foreground uncut sentence, its PNG byte-equal
  to the cutout-off PNG; S5 `analyze_cutout {clips: [image], wait: 0}` answers a row `analyzing`,
  frames 1, covered 0, and `{wait: 0}` the media and image rows in timeline order; S6
  `text_behind_subject {clip: image, at}` answers `cutout_added: true` and the image's cutout reads
  `background: keep`. Launch U (no hold): S1 a copy of `cutout_spike.FLEX` as `person.jpg` (missing:
  a scored failure naming the path) on a canvas of its own size with background `[0, 1, 0, 1]`;
  uncut, under 1 % green (r ≤ 2, g ≥ 253, b ≤ 2); S1a `{cutout: {}}` — `analyze_cutout {wait: 60}`
  `ready`, frames 1, covered 1, `subject_found` true, the render ≥ 20 % green and ≥ 1 % of its
  pixels not green and within ±2 of the uncut render; S1b `{subject: "foreground"}` the same, and
  `cache/analysis/foreground/<m>.json`'s stamp `vision.request` `foreground_instance_mask` and
  its pack's `FJMP` footer the media's width × height. Z1: both logs free of `Frame Job: `. Seven
  mutants, each once on the final instrument, files restored by SHA-256: `foreground-in-masks`
  (S1b), `image-draw-off` (S1a), `frame-wait-no-images` (S4), `noun-person` (S4),
  `analyze-image-refused` (S5), `picture-not-cuttable` (S6) and `subject-ignored` (the foreground
  job runs the person request; S1b's footer). **JOB-66** — a portrait photo's cutout on hair:
  Remove Background with Person, then Foreground, at Edge −0.5, 0 and 0.5; the outline stays on
  the hair and the person.

### Amendments recorded by CO10b

- **CO-22** (a) the windows add a cut picture's one window `[0, 1)` (CO-106); (e) the export's
  wait covers both kinds and names a foreground window's failure in its own sentence; (f) the
  frame's wait and its sentences take a picture's foreground masks, and Save Frame's noun follows
  the uncut clips' kinds.
- **CO-24** — an image layer's mask is the pack's one frame at source tick 0, with no pivot.
- **CO-30** (a) a picture can be cut out; (c) the Status's words add "No subject found", and the
  section adds the Subject row for pictures.
- **CO-31** (a) a picture's frames are 1 and its found-false foreground state is `no_subject`;
  (b) the named-image refusal and the default set's exclusion are gone.
- **CO-53** — the two refusal sentences name "a video file or picture" / "a clip of a video file
  or a picture".
- **CO-102** — an image clip's cutout is drawn now; the "drawn uncut" half is CO10a's history.
- **CO-103** — lifted, both refusals.
- **CO-104** — S4 and S5 are rewritten by CO-109 (an image's cutout now waits and is analysed).

### Deviations

- The road map's S1 used "a pencils still" for `foreground`; no pencils still exists in the tree,
  so S1 uses the one person photo (`cutout_spike.FLEX`) for both subjects.
- The road map named the manual check JOB-65; JOB-65 is CO9's since, so this one is **JOB-66**.
- S4 is rewritten: CO10a's "equal to off, each call under 10 s" no longer holds for a cut picture,
  which now waits for its masks.
