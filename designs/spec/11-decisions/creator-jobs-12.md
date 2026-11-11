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
  scale and opacity within `RECOGNISE_RATIO` (0.001). On a nest role the radius is not compared
  (amended by #536): a switch made before #536 holds the panel radius there and one made after
  holds 0, and both are recognised; the replay writes 0 (CO-60). Then every group clip and piece takes
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

## VR6a — a two-shot follows the speaker (2026-11-04)

Recorded before the code. VR6 is split (the road map's VR6, "Split (recorded before code)"):
**VR6a** gives agents `reframe_clip`'s `follow: speaker` — a wide two-person clip framed on the
face whose microphone is speaking, turns read exactly as Switch by Speaker reads them, faces
matched to microphones automatically and refused, naming each face, when the match is weak —
and VR-S3's runnable arm; **VR6b** (VR-64 onward) puts it in Make Vertical's sheet and
`make_vertical_version`. No FFI, header, op, tool or `Kind` change and no format change (43
stands; `OP_COUNT` 70; 124 product tools); `Kind::Follow` gains a member. Nothing is sent
anywhere, so nothing is keyed (CJ-3). The owner's answer of 2026-11-01: faces are matched to
microphones automatically, the sheet confirming (the sheet is VR6b's).

- **VR-60 — `follow: speaker`.**
  (a) **Arguments.** `mics`, 2–4 clip ids, each a media clip whose media has audio, on its own
  track, not the framed clip; `mic_faces`, optional, each microphone's face number in `mics`'
  order. Both are read only by `speaker`; another follow ignores them.
  (b) **What the app fills.** `subjects.turns` (`[{from, to, mic}]`, container timeline ticks,
  `mic` a clip id of `mics`) and a face box's `mouth` (its mouth gap ÷ its mouth width, SW-81's
  opening, absent when either is unread, the width ≤ 0 or the gap < 0) are the tool's;
  `subjects` stays `filledByTheApp`. Nothing is written to `media.speech` or to any cache.
  (c) **The tool's turns** (`FramingSpeaker.turns`, `SpeakerSwitch+Turns.swift`). The tool reads
  `SpeakerSwitch.read(clips: mics, pairing: each mic's track as a speaker with no angle, no
  wide, range: the framed clip's span, settings: Settings())`, then `turns` — SW-21's labels and
  SW-22 (a)–(e) as `shots` applies them, on labels, not angles: the crosstalk bridge, then the
  nobody bridge; the first turn from the range's start; a person run of at least `minTurn`
  starts that microphone's turn at `snap(onset − lead)`; a crosstalk run of at least
  `crosstalkMin` starts one turn per microphone active at any of its crosstalk steps; nobody and
  shorter runs hold; each turn ends at the next start, so the turns tile the range (crosstalk
  turns share one span). `read`'s `problems` and `silentMicrophones` (SW-24's no-speech sentence,
  moved out of `refusals`) refuse as `"reframe_clip was refused: " + joined`, SW-24's own
  sentences. A call whose scope differs from the document's open scope is refused: "follow
  speaker reads its microphones on the open timeline; open that nest first with set_scope". The
  turns are added to `subjects` on the last main hop. A microphone `read` drops (its sound off)
  gets no turn and no refusal of the tool's own: the core names it, (d).
  (d) **The core's refusals**, after VR-26's (1)–(2), the nest and still refusals and VR-51's
  (`speaker` reads subjects), and (5)–(6), in this order: `mics` absent or not 2–4 ("follow
  speaker needs two to four microphone clips in mics, not N"); a clip named twice ("clip C is
  named twice in mics"); a microphone with no sound from a media file, or the framed clip ("clip
  C has no sound from a media file, so it cannot be a microphone" / "clip C is the clip being
  framed, so it cannot be one of its microphones"); a microphone whose sound is off ("clip C's
  sound is off, so it never says who is talking; turn its sound on or leave it out of mics" —
  `SpeakerSwitch.read` drops such a track silently, so the core names it; a detached camera
  sound with its sound on stays a valid microphone, SW-20); two microphones on one track ("clips
  A and B are both on track T; each microphone needs its own track"); `mic_faces` not one per
  microphone, a 0, or a face named twice; bad `subjects` (a turn `from ≥ to`, turns' `from`
  decreasing, over 100,000 turns, a `mouth` not finite or below 0, a `mouth` on a people or
  salient box); no subjects (LAST of the subject-free refusals, VR-28's trial); then a turn
  naming a clip not in `mics`, a shot change inside the played window ("clip C changes shot at
  TC; follow speaker frames one wide shot — split the clip at its shot changes first", TC by
  `layout_timecode`), fewer faces than microphones, a `mic_faces` number past the faces found, no
  turn inside the clip, and — with no `mic_faces` — a match that is not `sure`: "clip C's faces
  do not show which microphone is whose: the best match agrees only A (under 0.2); name each
  microphone's face with mic_faces, in mics' order — face 1 at X % across the picture, face 2 at
  …". An unknown microphone id is an `Err` (`require_clip`).

- **VR-61 — Speaker changes are cuts, held 2 s; the match.**
  (a) **Faces.** `reframe_tracks.rs`'s `link` over the in-clip samples' faces (its `Track`'s
  `pub(crate)` fields and `at`, reused, not copied); tracks chained when a later one starts after
  a chain's last box and its first box has `iou` ≥ `LINK_IOU` with that box (the best IoU wins);
  a chain present in at least `FACE_SHARE` (0.25) of the samples is a face; at most
  `MAX_SPEAKERS` (4) by sample count; numbered 1… left to right by median centre x (ties: the
  earlier first sample).
  (b) **Activity.** The population standard deviation of a face's `mouth` over its samples
  within ±`ACTIVITY_SPAN` (0.25 s, SW-81's 0.5 s window), at least two values.
  (c) **Agreement**(mic, face): Pearson's r between the activity and 1/0 "a turn of the
  microphone covers the sample" over the face's samples with an activity; 0 when undefined.
  (d) **Assignment.** The injective microphones → faces map with the greatest summed agreement,
  ties to the lexicographically smallest face list; `sure` when every assigned agreement is at
  least `SPEAKER_AGREEMENT` (0.2, PROVISIONAL, VR-62). `mic_faces` replaces it, unchecked.
  (e) **Segments** over clip ticks [0, duration), cut at the turns' bounds: one microphone → its
  face; none → the previous segment's label (the first labelled one's at the start); two or more
  → Both(current, other) — current the previous segment's face when among them, else the first
  in `mics` order; other the first other in `mics` order — kept only when both faces' median
  boxes over the segment, each widened by `PAIR_WIDEN`, fit the window, else current's face.
  Equal neighbours coalesce, then SW-22 (h)'s merge at `SPEAKER_HOLD` (2 s): the earliest segment
  shorter than the hold joins the one before it (the first, the one after) until none is short.
  (f) **The path.** Every segment start after 0 is a cut through `reframe_path.rs`'s
  `write_keys`, passed as its `shots` (a cut's key on `snap_up` of its start, on its face's
  first-second median); one `Chosen` per sample: kind Face, `subject` the segment's face's box
  (none when the face is absent there: VR-24's loss to `where_empty`), `second` Both's other
  box, else none, `identity` the face number, `lost` false. Within a segment VR-23's moves at
  `FRAMING_TUNING`; `zoom`, `where_empty`, `backdrop` and `replace` read as for `face`.

- **VR-62 — VR-S3** (`tools/proof/creator_spike/speaker_spike.py`). `rule.check_rule("VR-S3")`
  first. S-PC3 absent: "SKIPPED the S-PC3 arm: S-PC3 is not in tools/proof/media/creator/
  (owed)"; present, it is not run by this head and is owed, as `mouth_spike.py` does. The still
  arm: `face_fixtures.py`'s `subjects_moving.mov` through `faces_spike.swift run` at the `faces`
  kind's settings (rate, read size and devices as `AnalysisFaces` pins them), boxes with
  `mouth`, synthetic turns A [0, 4 s), B [4, 8 s) … alternating over the clip, "true" = face 1 ↔
  A and face 2 ↔ B; `core/tests/speaker_spike.rs` (`#[ignore]`, reading
  `FRAMEJOB_SPEAKER_SPIKE`'s folder) writes the four agreements; `rule.write_results`. A still's
  mouths never move, so this arm is the no-speech control and cannot supply true pairs; the
  rule's midpoint needs S-PC3. The road map drafts no figure, so `SPEAKER_AGREEMENT` is 0.2,
  provisional, re-measured on S-PC3 (owed); the control's figures are recorded, and a control
  |r| ≥ 0.2 is recorded as such, not acted on.

- **VR-63 — VR6a's proof.** `core/tests/reframe_speaker.rs`: the segments (nobody holds, the
  first label back to 0, Both kept when it fits and current's face when not, three
  microphones), the hold (a 1.9 s segment merges into the one before, the first into the one
  after, 2.0 s stands), the cuts on `snap_up` of each start, faces chained across a 3 s gap and
  numbered left to right, `FACE_SHARE` at its edge, the activity window, Pearson against hand
  values, the assignment and its tie, `sure` at 0.19 and 0.2, `mic_faces` overriding, every
  VR-60 (d) refusal's sentence and order (the sound-off microphone before "no subjects"), a ×2
  and a reversed clip's turns and samples. `tools/proof/vr6_proof.py` over F-TURNS (`f_turns.py`,
  exit 2 skips by name) on a 1080 × 1920 30 fps canvas, `cam_wide.mov` the two-shot with canned
  shots, subjects and faces with landmarks (face 1 at x 0.42, face 2 at 0.58, y 0.4; each mouth
  alternating 0.05/0.20 of width 0.5 inside its speaker's utterances, 0.05 outside), Mic A
  `mic_a_b12_f55.wav` and Mic B `mic_b_b12_f55.wav` at 0: **P0** every log's `Frame Job: ` grep
  empty; **P1** `{follow: speaker, mics: [A, B]}` applied, one undo "Reframe Clip", its cut keys
  equal, each within one frame (20,000 ticks), to the shot starts of `switch_by_speaker {apply:
  false, min_shot: 2}` over the same microphones with F-TURNS' Wide, Cam B and Cam A angles (a
  second document) from its first person shot on (cam_a → face 1, cam_b → face 2, wide → both);
  **P2** at each segment's middle the evaluated placement puts the speaker's face (or the pair's
  union) inside the window's central 60 % across; **P3** mouths swapped between the faces → B's
  segments frame face 1; **P4** mouths constant → refused naming face 1 at 42 % and face 2 at
  58 %, nothing changed, then `mic_faces: [2, 1]` applies and A's segments frame face 2; **P5**
  `get_project`'s `media` byte-identical before and after P1; **P6** the refusals in their
  sentences: `mics: [A]`, `[A, A]`, the two-shot as a microphone, `mic_faces: [1]`, a canned cut
  inside the clip, Mic A's loudness cache removed (SW-24's "still being analyzed" (amended by #526)), Mic B's sound
  switched off with `mic_faces: [1, 2]` given (the sound-off sentence naming Mic B, nothing
  changed). Canned analyses (CJ-26, `-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`); the
  expected numbers from F-TURNS' manifest or from `switch_by_speaker`'s answer, never from the
  code under test. Six mutants, each once on the final instrument: the hold removed (a core test
  and P1); the assignment transposed (P3); Both never kept (P1); `sure` ignored (P4); `mouth` not
  filled by `FramingSubjects` (P1); `lead` dropped in `SpeakerSwitch.turns` (P1).

### Amendments recorded by VR6a

- **VR-20**: `reframe_clip`'s arguments gain `mics` and `mic_faces` after `replace`, before
  `subjects`; `subjects` gains `turns` and a face box's `mouth` (VR-60 (b)).
- **VR-26**: `follow` gains `speaker` (after `layout`), which reads `subjects` like a following
  kind and adds VR-60 (d)'s refusals in their place in the order; "no subjects" stays last of the
  subject-free refusals.

### Recorded after the code

- **VR-62's figures** (2026-11-04, macOS 25F80, Apple M2 Max, on AC; the rule's hash matched
  the table): S-PC3's arm skipped by name (owed). The still arm read `subjects_moving.mov` at
  720, 10 a second, both requests on the Neural Engine: 600 samples, 1,200 boxes with a
  `mouth`, two faces (each in all 600 samples, median centres 0.4425 and 0.5061), fifteen 4 s
  turns. Agreements `[mic][face]`: A–1 −0.0145, A–2 −0.1181, B–1 0.0145, B–2 0.1181 — the
  "true" pairs −0.0145 and 0.1181, the swapped −0.1181 and 0.0145; none at or over 0.2, so the
  control would be refused as not sure, as it should. `SPEAKER_AGREEMENT` stays 0.2,
  provisional, re-measured on S-PC3 (owed).
- **The match is its own module.** `reframe_speaker.rs` and its match passed the 400-line cap
  for a new file together, so VR-61 (a)–(d) — the faces, activity, agreement, assignment,
  `speaker_match`, the four constants and the median box — are `reframe_speaker_match.rs`,
  re-exported by `reframe_speaker.rs`, which keeps the hold, the segments, `mics_refusal` (VR-60
  (d)'s subject-free sentences, out of `edit_reframe.rs`) and `plan_speaker_framing`.

## VR6b — Make Vertical follows the speaker (2026-11-04)

Recorded before the code. VR6a gave agents `reframe_clip {follow: speaker}`; VR6b puts it in File ▸
Make Vertical Version… and `make_vertical_version`: a wide shot of two to four people beside their
microphones cuts to whoever is talking, the faces matched to the microphones automatically and
the sheet confirming (the owner's answer of 2026-11-01). One FFI export (`rc_project_speaker_match`,
a query); no op, op-table, tool count (124), `Kind` or format change (43 stands). Nothing is sent
anywhere, so nothing is keyed (CJ-3).

- **VR-64 — `make_vertical_version`'s `follow: speaker`.**
  (a) **Arguments.** `mics`, 2–4 clip ids, each standing for its TRACK as a microphone;
  `mic_faces`, optional, one face number per microphone in `mics`' order. Both are read only with
  `speaker` and ignored otherwise (VR-60 (a)'s rule).
  (b) **Speaker clips.** A class-3 media picture (VR-33) whose file is present and whose media has
  no cursor file, not on a microphone's track, whose span overlaps a clip with audio on at least
  two microphone tracks. Its own `mics`: per microphone in order, the media clip with audio on
  that track, one with its sound on before one with it off, then the greatest overlap with it
  (ties: the earlier start, then the lower id); a track with none is left out, with its
  `mic_faces` entry. A track whose only clip under the shot has its sound off still counts toward
  the two and stays in `mics`, so the core's sentence reaches the entry's reason.
  (c) **Step (3) with `speaker`.** Every `settings.follow.follows` test in the plan and the tool
  (`VerticalVersion+Plan.swift`'s missing and cursor branches, `AgentServer+VerticalVersion.swift`'s
  targets and `cursor`) becomes `VerticalVersion.analyses` (`follows || speaker`), so a missing
  picture is kept with its note and a picture whose media has a cursor file follows its cursor (or
  is shown whole) exactly as under the other analysing follows. A speaker clip gets `reframe_clip
  {follow: speaker, mics, mic_faces, zoom, where_empty, from_*, backdrop}` with its subjects; every
  remaining present, analysed (non-cursor) media picture gets `face`. A refused speaker framing is
  retried as `face`, its entry `followed` with the reason "it follows its faces, not who is
  talking, because " + the core's sentence, joined with `followedEntry`'s reasons by " and "; a
  refused `face` is retried as `keep` (VR-34), its entry `not_followed` with the face's sentence.
  (d) **Turns.** `withTurns` fills each speaker clip's `subjects.turns` through
  `FramingSpeaker.turns` with `silence: .notTalking` on the last main hop (the sheet's refresh,
  the tool's last hop): a microphone with no speech under the shot gets no turn, that person not
  talking there, and a shot with no turn at all is the core's to refuse and (c)'s to retry as
  `face`; a `FramingSpeaker.Refusal` (a microphone still being analysed, no speech detection, an
  unreadable plan) refuses the tool "make_vertical_version was refused: " + its sentence, nothing
  made (amended by #527).
  (e) **Refusals**, after VR-36's, in order: the `follow` sentence names speaker ("follow must be
  subject, face, person, salient, speaker or center, not X."); `follow: speaker` without `mics`:
  "make_vertical_version's follow speaker needs mics: two to four clips, one on each microphone's
  track."; an unknown id: `clipArg`'s error; no speaker clip: "make_vertical_version found no
  full-frame movie clip playing beside two of the microphones in mics, so nobody is framed by who
  is talking." The count, a repeat, a microphone that is not one and `mic_faces`' shape are the
  core's (VR-60 (d)) and reach the entry's reason; Swift restates none.
  (f) **The answer** gains `speaker [{clip, mics, mic_faces}]`, one per speaker-framed clip in id
  order, `mic_faces` the given ones or `clip_speaker_match`'s assignment; the summary adds
  " Follows whoever is talking in N clip(s)." after the cursor sentence.

- **VR-65 — The match crosses the FFI.** `rc_project_speaker_match(p, clip, args_json)`
  (`ffi_query.rs`, no `err_out`, no handle): `args_json` is `{"mics": [id, …], "subjects": {…}}`,
  `subjects` read by `reframe_clip`'s strict reader and `check_subjects`; the answer, compact, is
  `{"faces": [{"face", "x", "samples"}, …], "agreement": [[r, …], …]` (`[mic][face]`),
  `"assignment": [face per mic], "sure": bool}`, and with fewer faces than microphones the empty
  answer (`faces`, `agreement`, `assignment` [] and `sure` false); NULL for a NULL project or
  args, an unknown clip, a clip that is not a media clip, malformed or failing args, or `mics`
  empty or over 4. `reframe_speaker_match.rs` gains `clip_turns` (`plan_speaker_framing`'s turn
  clamp, a pure move: timeline → clip ticks, clamped to `[0, duration]`, empty dropped) and
  `clip_speaker_match` (`in_clip_time`'s samples, `clip_turns`, `faces_of`, `matched`), so the
  sheet shows the core's own assignment and face places; Swift computes none.
  `ReelCore+Framing.swift`'s `ReelProject.speakerMatch` is its one caller.

- **VR-66 — The sheet.**
  (a) **Follow**: Subject, Faces, People, Salient Region, Speaker, Center
  (`VerticalVersion.follows`). Speaker is remembered in VR-29 (c)'s key; Follow Subject's sheet
  reads a stored `speaker` as Subject (its rule for a value outside its list) and gains no Speaker.
  The sheet's `opened`, fresh and restoring alike, is `VerticalVersion.remembered(.standard)`
  (`FollowSubjectSettings` with `follow` the key's value when in `follows`, else `subject`; Where
  Empty as `FollowSubjectSettings.remembered`; zoom 1), so `remember(changedFrom:)` compares
  against what Follow showed and Subject chosen after a stored `speaker` is written.
  (b) **With Speaker**: "Microphones:" one checkbox per `VerticalVersion.microphones` track (a
  track holding a clip `SpeakerSwitch.playsSound` takes whose media has no video, front to back,
  titled by the track's name, its `clip` the earliest such clip), the first four ticked; "Faces:"
  one row per ticked microphone, the track's name and a pop-up of "Choose a face" and "Face N
  (X % across)" per face found; then a muted note.
  (c) **The reading.** The reference clip is the longest speaker clip (ties: the lower id).
  `speakerReading` (main) fills the turns (`withTurns`) and asks the match on the reference clip
  with its own microphones; only a `.ready` reading is cached, per ticked set, and a `.refused`
  one is read again at each `refresh()`, so a loudness cache landing while the sheet is open
  clears it. `.refused` shows its sentence (SW-24's still-being-analysed sentence (#527), or
  with no speaker clip "No full-frame movie
  clip plays beside two of the ticked microphones, so nobody can be framed by who is talking."),
  Make off.
  (d) **The confirmation.** A `sure` match presets the pop-ups to its assignment, the note "Each
  microphone is matched to the face that talks with it; change one if it is wrong."; not sure, or
  no match, leaves them on "Choose a face", the note "The faces do not show clearly who is on each
  microphone: choose each microphone's face." The preset is made once per ticked set. Make is off
  until 2–4 microphones are ticked, a speaker clip exists and every ticked microphone has a face,
  each its own. Make passes `mics`, `micFaces` (always the confirmed faces) and the subjects with
  their turns.
  (e) **Analysis missing.** The pending summary reads "Finds the faces, people and shot changes in
  N files on this Mac first, then asks you to confirm who is on each microphone, then makes a W × H
  version."; after the Analyzing sheet lands, the editor presents the sheet again from the
  hand-off (`restoring`): its shape, follow, zoom, where empty, copy and ticked microphones.
  Nothing is made until Make there. `-RCDevVerticalAccept` presses each sheet's Make once it is
  first enabled.

- **VR-67 — The documents.** `docs/guide/vertical-and-framing.md`'s Make Vertical section gains
  Follow Speaker for people and the `speaker` bullet loses "There is no menu for it yet."; the
  README's Vertical and framing highlight names whoever is talking; `menus-and-shortcuts.md`'s Make
  Vertical row lists Speaker; `15j-make-vertical-sheet`'s prose lists Speaker and the Microphones
  and Faces rows (no new screen: the catalog pins Follow to Subject, and the proof's Q6 dump stands
  for the Speaker block); JOB-37 between JOB-36 and JOB-39; spec §7.1, §7.4, §7.9i and §7.10.

- **VR-68 — VR6b's proof.** `core/tests/speaker_match_ffi.rs` (the two-face answer equals
  `speaker_match` on the in-clip samples; a clip at a timeline offset and a ×2 clip map turns as
  `plan_speaker_framing` does, not sure exactly when it refuses the weak match; fewer faces → the
  empty answer; NULL for a NULL project, an unknown clip, a text clip, malformed args, `mics` []
  and five mics). `tools/proof/vr6b_proof.py` over F-TURNS (`f_turns.py`, exit 2 skips by name) on
  a 1920 × 1080 30 fps canvas — `cam_wide.mov` W with VR6a's two canned faces and landmarks, Mic A
  and Mic B at 0, a second movie S after the microphones' span with one canned face — rows Z0 and
  Q1–Q8 (launch 1 `-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`: Q1 the tool with `mics`,
  W equal to a reference document's `set_canvas`, `add_track` and `reframe_clip {speaker}`; Q2
  `mic_faces: [2, 1]`; Q3 constant mouths retried as `face`; Q4 the four refusals; launch 2
  `-RCDevAnalysisCanned YES -FrameJobFollowKind speaker -RCDevVerticalAccept in-place`: Q5 the menu
  in place, W equal to Q1's; Q6 the not-sure sheet's dump; Q7 an uncanned analysis, the sheet
  presented again with both microphones ticked; Q8 `vr6b_probe.swift`, the remembered key read
  back), expected values from a reference `reframe_clip` or the manifest, never the code under
  test, under a scratch `CFFIXED_USER_HOME`. Eight mutants, each once on the final instrument:
  every present picture a speaker clip (Q1); a refused speaker retried as `keep` (Q3); `micFaces`
  not passed (Q2); the picker presetting when not sure (Q6); the picker's preset transposed (Q5); a
  Speaker hand-off committed after the analysis instead of presented again (Q7); `withTurns`
  filling nothing (Q1); `remembered` ignoring `.speaker` (Q8).

### Amendments recorded by VR6b

- **VR-29 (c)**: the Follow key may hold `speaker`, written only by Make Vertical's sheet; Follow
  Subject's sheet reads it as `subject`.
- **VR-34** (3): the speaker branch, the speaker → face → keep chain and `Plan.speaker` (VR-64 (c),
  (f)); `where_empty` is sent to `speaker` as to the following kinds.
- **VR-35**: VR-64 (f)'s sentence.
- **VR-36**: `follow` gains `speaker`; the arguments `mics` and `mic_faces`; VR-64 (e)'s refusals;
  the answer's `speaker`.
- **VR-39**: Follow gains Speaker with its Microphones and Faces rows (VR-66); `opened` is
  `VerticalVersion.remembered`; a Speaker hand-off that analysed presents the sheet again.

## Fixes batch c1 (2026-11-09)

- **#456 — An empty range gets no no-face refusal, and a marker range past the grid is
  skipped.** With `from == to` the range has no step, so every read face angle's `activity` has
  `count == 0` values and none of them is a value: SW-84's loop added "shows no face whose mouth
  can be read" beside the microphones' own no-speech refusal, which is the range's real reason.
  The loop now runs only when `count > 0`; `silentMicrophones` is unchanged, so an empty range's
  refusal is the no-speech sentence alone, and no new empty-range refusal is added. A `faces`
  marker range clamped to the grid (`max(0, lower)...min(grid.lastIndex, upper)`) crosses when
  the range begins past the grid's last index — a marker written over a longer media, or a grid
  read at another rate — and forming that `ClosedRange` traps. `SpeakerSwitch.storedActivity`
  and `AnalysisMasks.run` skip a range whose clamped bounds cross: it covers no index of this
  grid, so nothing is read and nothing is published for it. Amends SW-84.
- **#458 — The landing's follow-ups read the landing's own container.** The voice clips, their
  presence and readiness (AU-68 (a), (b), (d)), the screen clips, their cursor files and media
  (CU-101 (b), (c), (j)) are read in `RecordingEnhance.container(of:scope:)`, the landing's
  container (the nest it landed in, or the top level), never `editedProject`. Before, a nest
  opened while a follow-up waited made the open container the nest: the landed clips were not in
  it, `decide`'s first arm answered `.drop`, and the follow-up was lost ("No screen clip with a
  cursor file landed…") although the scope test was there to wait. Now the clips are still found,
  the moved scope is busy (AU-68 (c), CU-101 (d)), `decide` answers `.wait`, and the follow-up
  runs once the person returns, or gives up at 300 s as before. At the tool door,
  `landAndEnhance` reads `document.scope` and, when the choice asks for Enhance, the voice clips
  in the main hop that runs `land`, and hands both on; no later hop reads them, so a nest opened
  between hops cannot empty them. The panel door already reads both in the landing's own hop
  (`follow`). `isReady` (which reads the open container) is evaluated only when not busy, at both
  doors; busy reads not ready. `decide`'s arms and order, the sentences, the clocks and the 300 s
  limit are unchanged. Amends AU-68 (a), (d) and CU-101 (b), (d), (j).
- **#459 — A cache file that vanishes during the carry is skipped.** The thumbnail pass's
  `clearThumbnails` (`MediaCacheFiles`) is the one remover of the source's cache not held off by
  the ledger's save bracket, so a `thumbs/<id>/` tile listed for the carry could be gone when it
  was cloned, and New Project from Range or Make Vertical then failed ("cache/thumbs/3/40.jpg
  could not be carried: No such file or directory"). The carry is now two steps,
  `DerivedCarry.listing` (each listed path that exists: a file as itself, a folder as itself and
  its regular files; a folder that vanishes while it is enumerated contributes nothing) then
  `copy(_ listing:from:to:)` (every folder created, then every file cloned). A file whose clone
  fails while the source no longer exists is skipped and not counted in the report; the
  derived document's own thumbnail pass makes its tiles again. Every other failure still throws
  "cache/<path> could not be carried: <reason>". Skipping was chosen over bringing the tiles into
  the bracket: a vanished tile is a cache the copy rebuilds, and the bracket would hold the
  thumbnail pass for the whole carry. Amends CJ-51 (c).
- **#460 — A vertical copy whose save fails is closed and its package removed.** With `path`,
  `make_vertical_version` saves the copy on the server thread after `verticalCopy` opened it at
  `path`. When that save threw, the copy stayed open and dirty, its package held the project
  before the step, and the error had no `project` to name it. Now any throw from the save closes
  the copy (on main), removes the package at `path`, and answers the save's error unchanged —
  `ProjectDocument.verticalCopy`'s own shape for a copy the step did not change. A dev-tools build
  reads `-RCDevVerticalSaveFault <name>`: a save to a `path` whose last component is `<name>`
  throws before it is attempted, so a proof can see the cleanup; Distribution never reads it.
  Amends VR-36.

## Fixes batch c2 (2026-11-09)

- **#444 — A voice cache replaced under shown cloud words is read again at once.** TX-34 said a
  voice cache REPLACED under a shown cloud-transcribed media kept the old one in the tab's table
  until the tab showed again (filed). That clause is replaced. A `speech` landing now calls
  `TranscriptTabSource.reloadSpeech(media:)` after TX-18's `reloadDeviceWords` (which moves the
  media's epoch) and before `update()`. It always drops the media's kept voice cache and the
  table, so the next `cutTable()` reads the landed file, as it already did for a media with none
  kept: the word cuts (TX-30) and the pause tokens follow the new cache. When the tab is shown,
  the media's words are there and no TX-18 re-read covers it (its words are not this Mac's), its
  pause set and voice cache are read again on the load queue at the media's epoch. They are
  merged and rebuilt only while the tab still shows words of the same engine; when a landing came
  during the read (the epoch moved), the media is read again instead. So the paragraph breaks
  (TX-22) follow the new cache too. A cloud load that read the media before a landing and merges
  after it (its epoch moved) merges its words and then calls `reloadSpeech(media:)`, so it never
  keeps the voice cache or pause set it read before the landing. An `.apple` media is unchanged:
  TX-18's re-read reads its words, pause set and voice cache. A peaks landing also moves the
  epoch; a cloud load that crosses one is read once more, which is harmless. Amends TX-34.
- **#438 — Remove Background's status: the shut header follows, no nil stamp is memoised, and
  `analyze_cutout` re-reads only what is still analysing.**
  - (1) A tick of `CutoutStatus.Memo` that does not change the state's kind (a recompute of the
    same kind, or a progress-only tick) refreshes the read-out's enclosing `InspectorSection` —
    its rows and its header summary — not the read-out alone. The Background section is shut by
    default and its summary repeats the Status words for one clip, so before it kept showing the
    first "Analyzing N %". The section's `summary` reads the memo's held status, so this refresh
    reads nothing again and starts no second ticker. Amends CO-30 (d).
  - (2) `CutoutStatus.stamp` memoises only a non-nil stamp; a nil one is answered and its key's
    entry removed, so it is read again on the next call. Before, a transient "Failed: the media
    file cannot be read" (the file briefly absent) stayed for that media, URL and LUT for the
    rest of the process, Analyze Now included. `analyzeMasksNow()` is unchanged. Amends
    CO-31 (a).
  - (3) `analyze_cutout`'s poll keeps the details it read with the document's `project` and
    `editedProject` handles (`AgentServer.cutoutDetails`, `CutoutPoll`). While both handles are
    the same (`===`), a clip whose kept detail is settled (anything but analysing) keeps it and
    only the others are read again; any change of either handle, an edit during `wait`, reads
    every clip again, as the pane's memo does. The quality and the project summary are still read
    in each hop. The answer's shape and the refusals are unchanged. Amends CO-31 (b).

## Fix #546 (2026-11-09)

- **#546 — The polish waits for Enhance's measurement, not only its timer.** AU-68 (e) ends
  Enhance's follow before anything is shown, so `RecordingEnhance.isPending` was false for the
  whole measurement, and the polish's follow (CU-101 (a), (f)) was then held only by the
  Measuring Sound sheet being attached. The sheet hands its answer back a main-queue turn after
  it has gone; in that gap the polish's 0.5 s timer could fire and commit Auto Zoom (measured on
  Debug: 21 ms before the hand-back), and `AudioMeasureDoor.measure`'s stale test then refused
  Enhance ("…Choose Enhance Voice again."), so its step was lost. No build was exempt: the timer
  either landed in the gap or did not.
  - (a) **The measuring state.** `RecordingEnhance.tick`'s `.enhance` step makes a
    `RecordingEnhance.Measurement`, counted per document, and `AudioMeasureDoor.enhanceLanded`
    takes a `done` it calls exactly once, after whatever the call ends in has landed: each
    refusal before the run, the no-render answer, the sheet's hand-back (the commit, a refusal or
    the stale refusal; the document gone), the sheet's Cancel and a run with no outcome.
    `AudioMeasureSheetController` gains `stopped`, called in `finished`'s place on the same turn
    after `viewDidDisappear`, so one of the two always runs for a sheet that was shown. A
    `Measurement` released without `end()` uncounts itself, so a hand-back dropped uncalled
    cannot hold the polish. `isMeasuring(document)` reads the count; `isUnderWay` is `isPending`
    or `isMeasuring`. `isPending` keeps AU-68 (e)'s meaning, the timer, and never depends on the
    sheet.
  - (b) **Who reads it.** The polish's panel follow (`enhancing`, and so CU-101 (a)'s clock
    restart) and the tool door's `polishLanded` read `isUnderWay`. The tool door's own Enhance was
    never exposed — `enhanceVoice` returns before `polishLanded` starts — but its `decide` read
    `isPending` for a panel landing's Enhance in the same document, and its busy test has no sheet
    arm, so it had the same gap, wider; it now waits for that measurement too.
  - (c) **`land_recording`.** `follow_wait` waits while `isUnderWay` or the polish is pending, and
    `enhance_pending` answers `isUnderWay`. Before, `follow_wait` returned when the timer ended,
    about 2.7 s before the step, and an `undo` read then was itself the edit that made the
    measurement stale.
  - (d) **The dev hold.** `-RCDevMeasureHandBackHold <s>` (dev tools only) holds the Measuring
    Sound sheet's hand-back, `finished` or `stopped`, s seconds after `viewDidDisappear`, so a
    proof makes the gap wider than the polish's check interval instead of relying on where a
    timer lands.
  - (e) **The proof.** `cu10_proof.py` P5 requires "Auto Zoom", "Enhance Voice", "Add Recording"
    exactly, on every build. P6 and P7 run on an instance held 2 s: Enhance alone with
    `follow_wait` (undo read straight after the answer: "Enhance Voice", "Add Recording";
    `enhance_pending` false), and Enhance with Auto Zoom (all three names, both pendings false).
    Mutants: `polish-ignores-measuring` (P7) and `wait-ignores-measuring` (P6).
    `audio_ap6c_probe.swift`'s P5 also reads `isMeasuring` false after a no-render refusal.
  Amends AU-68 (e), AU-69 (e) and CU-101 (a), (j).

## Find in the Transcript tab (#434, 2026-11-10)

Recorded before the code. The owner asked for it on 2026-11-01 as "⌘F later, unless it comes
free" (TX-20), and on 2026-11-10 to begin it. No owner question was asked.

- **TX-37 — Edit ▸ Find… (⌘F) finds in the Transcript tab, in Frame Job's own bar.** The item is
  the Edit menu's last, after a separator, enabled while the window's Transcript tab shows and no
  sheet is attached, whatever has the keys. ⌘F was free; ⌘G and ⇧⌘G are Nest and Un-nest, so the
  usual Find Next keys are not offered. **Not `NSTextFinder`**, which #434 named, for four
  reasons: its bar is a system search field in the editor window, whose Return K-4 (3) spends
  before the field sees it; it shows the current match by setting its client's selection, and a
  selection here is the in/out range (TX-31), so every Return and every keystroke of an
  incremental search would move the range; its only search string from code is the shared find
  pasteboard, so a proof would write a system-wide pasteboard; and the panel's fields are
  `DSField` chrome (the Media search's own reasoning). What that gives up: the find pasteboard
  (⌘E) and the system bar's options. **No MCP mirror:** Find edits nothing and is view state,
  never saved, as the Media tab's search is; an agent reads `get_timeline_transcript`.
  - (a) **What is searched.** The words, not the view's string: each paragraph's token texts
    joined by one space, paragraphs separated by a line break, and a line break rather than a
    space before a token with `collapsedBefore > 0`. So a timecode, "⋯" and a pause label are
    never matched, a phrase is found across a pause label, and no match spans a paragraph break
    or a collapse.
  - (b) **How.** The query as typed, not trimmed (as `MediaListFilter.search`), compared ignoring
    case, diacritics and width (what `localizedStandardContains`, the Media search's test,
    ignores), left to right, never overlapping. A match is its token range and, per token, the
    part of that token's text it covers. A match covering no token character (a query of spaces)
    is dropped; an empty query, or one holding a line break, has no matches.
  - (c) **The current match.** An anchor token is set as the bar opens: the selection's first
    token, else the highlighted word, else the top visible token, else 0. While typing, the
    current match is the first one starting at or after the anchor, else the first. Return or
    Next (›) moves to the next match and ⇧Return or Previous (‹) to the one before, wrapping,
    and the anchor moves there. With no match they beep. The count reads "3 of 12", "No matches",
    or nothing for an empty field.
  - (d) **What Find moves.** Only the scroll position and its own marks. Every match is marked
    behind its text in `NSColor.findHighlightColor` at 0.3, the current one at 0.65 with a 1.5 pt
    outline of the same colour (a strength that keeps the words readable in both looks), under
    the selection and the highlight; a phrase is one mark, and a pause label between two of its
    words is not marked. The current match is scrolled into sight by `setHighlight`'s rule (a
    third from the top when it is outside the margins), **after the text from the top through
    the match is laid out**, the match's own paragraph invalidated first. One scroll onto a
    measured rect is not enough: a far word's rect and the view's own height are estimates
    until the text above is laid out (measured on 27,000 words in 900 paragraphs: the last word
    estimated at 88,601 pt and laid out at 130,078 pt, in a view 979 pt tall, so the scroll was
    clamped short; a paragraph measured early keeps its estimated place). Laying out all 27,000
    words took 0.06 s, once; drawing still lays out only what shows. The selection, the range, the playhead and the undo stack are
    untouched, bar open or closed. To act on a match the person clicks its word, which works
    with the bar open and leaves it open. Only the matches whose tokens meet the dirty rect are
    measured, so TX-21's viewport layout stands with a match in every word.
    **Amended 2026-11-11 (#558):** the layout step is `TranscriptView+Layout`'s
    `layOut(through:)`, and the click-to-clip scroll (TX-20, `scrollToToken`) and the follow's
    scroll (TX-22, `setHighlight`, only on a tick that scrolls) take it too. Measured before, on
    the same 27,000 words: `scrollToToken`'s two scrolls left word 18,000 some 1,850 pt below
    the visible rect, and six ticks of the follow never showed it. The step also lays out a
    viewport's height below its target and invalidates those paragraphs first: the view is only
    as tall as what is laid out from the top, so laid out through the word and no further the
    word came to rest at the visible bottom, and a paragraph laid out on its own keeps its
    estimated place (the one after a paragraph at 86,015 pt placed at 58,837 pt). The follow's
    step costs 1.4 ms once the text above is laid out. The scroller's knob is left as it is: it
    reads the scroll against the height laid out so far (0.995 at word 18,000 of 27,000), since
    the text below the viewport is not laid out (TX-21). A rebuild's anchor restore is not
    changed either: it keeps the top word (measured: the same top word, 9 pt lower), and the
    step there would lay out everything above the anchor on every rebuild.
  - (e) **Keys and focus.** ⌘F opens the bar and gives its field the keys, its text selected;
    with the bar open it only does that again. In the field Return is (c)'s next and ⇧Return its
    previous, and the field keeps the keys: K-4 (3)'s one exception, decided in the window with
    the event in hand (`TextFocus.keptReturn`, asked before `leavesOnKey`; the field is a
    `TextFocusKeepsReturn`), so ⇧ is read from the key itself. The bar is the field's host for
    K-4 (1) (`TextFocusHosting`): a press on Previous, Next or the count leaves the keys in the
    field. Tab and a click outside the bar still hand the keys back by K-4, and the bar stays
    open. Esc in the field, Done, or Esc in the transcript's text with nothing selected (a
    selection is cleared first, TX-21) closes the bar. Closing while the field holds the keys
    hands them to the transcript's text when it had them as the bar opened, else to the window's
    content view (K-4's target); keys anything else holds stay where they are.
  - (f) **The follow waits** while the bar is open (TX-22): playback does not scroll a match away.
  - (g) **A rebuild** (an edit, words landing, Words from, Language) recomputes the matches over
    the new words. The current match stays on its first word by identity, else the first match
    at or after that word's start; nothing scrolls.
  - (h) **Hiding the tab** (another tab, Hide Inspector, the window closing) closes the bar; keys
    its field holds go to the content view, never to a view not shown. The typed text is kept
    for the window and searched again when the bar next opens. **Found here and fixed with it:**
    AppKit leaves the WINDOW first responder when the view that was is removed, and there a bare
    key beeps, so after leaving the tab with the transcript's text focused J, K and L were dead
    (measured before the fix: first responder `EditorWindow`, L did not play). Out of sight, the
    pane now hands the keys to the content view whenever the window itself or the transcript's
    text holds them (`handBackKeys`), bar or no bar.
  Amends TX-20 ("⌘F later" is built), TX-21 (Esc), TX-22 (the follow) and K-4 (1), (3).
- **TX-38 — `transcript_view` drives Find.** `find: string | null` — a string opens the bar as
  Edit ▸ Find… does and sets the field's text through the field's own change path; null closes
  it by Esc's path. `find_step: "next" | "previous"` presses Return's or ⇧Return's path once,
  after `find`; refused while the bar would be closed (no `find` and the bar closed, or
  `find: null`). Applied after `click` or `select_pause`. The answer gains `find`: null while
  the bar is closed, else `{query, count, current, matches: [{first, last}] (the first 200),
  label, field_first_responder, current_visible}`. Amends TX-23.
- **TX-39 — The proof.** `tools/proof/transcript_find_proof.py` with
  `transcript_find_probe.swift`. Probe rows F0–F13 over the app's own editor window, keys and
  clicks through `NSWindow.sendEvent` (a press is then handed to the view it hit, because a
  window that is not key dispatches none; F12 holds that to one delivery): the search alone (F1), the validator and the open (F2),
  typing and the anchor (F3), Return, ⇧Return and keypad Enter (F4), Esc and the keys after it
  (F5), a click on a word and the two Escs (F6), a rebuild (F7), the follow (F8), hiding the tab
  (F9), a bare view of 27,000 words with a match in every one — the fragments its draw lays out,
  and the last match in sight once revealed (F10) — the marks' pixels (F11), a press on Next
  with the field typing (F12), and leaving the tab with the text focused (F13). App rows Z0 and A1–A5 over MCP: the argument set, the menu item's validation,
  the matches against the same rule computed in Python, phrases and paragraph breaks, a ripple
  under an open bar, and screen 11d (the `fillers` fixture, "er" found three times;
  `transcript_view` joins `screens.py`'s step tools for it, since Edit ▸ Find… is a `none` menu
  item that is no view toggle). **Fourteen mutants**, one per decision, over the root rule's ten
  because the plan's review named two decisions as unguarded and the build added two (the
  reveal's layout and the keys handed back):
  `return-leaves` (F4), `across-paragraphs` (F1), `case-sensitive` (F1), `anchor-ignored` (F3),
  `find-selects` (F4), `close-keeps-keys` (F5), `follow-while-finding` (F8),
  `stale-after-rebuild` (F7), `find-measures-all` (F10), `always-enabled` (F2),
  `hide-keeps-bar` (F9), `view-esc-passes` (F6), `reveal-on-estimate` (F10) and
  `keys-left-behind` (F13). Each is a probe mutant; the app rows are the same decisions read
  through MCP and name none. How the bar and the marks look, and a real ⌘F, are
  `docs/manual-checks.md`'s JOB-67.
  **Amended 2026-11-11 (#558):** probe row **F14** — `scrollToToken` on a fresh bare view of
  F10's 27,000 words, each target measured first where an estimate puts it: word 18,000 at the
  visible top and the top visible token; the last word in sight with the view's bottom at the
  visible bottom, at the height every paragraph laid out gives; a paragraph's first word less
  than a viewport from the end at the top or as the last word; and the follow to word 18,000 a
  third from the top, the next word's tick scrolling nothing. **Nineteen mutants**: #558 moved
  the reveal's layout into a step three callers share and gave that step two decisions of its
  own, each of which is one mutant, and two road-map items now share the instrument.
  `reveal-on-estimate` moves to the shared step (F10, F14); new are `reveal-skips-layout`
  (F10), `scroll-on-estimate` (F14), `follow-on-estimate` (F14), `no-viewport-below` (F14) and
  `below-keeps-estimate` (F14).
