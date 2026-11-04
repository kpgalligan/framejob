# Spec §11 — decisions: Creator jobs, Make Vertical's menu onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) …
[`creator-jobs-10.md`](creator-jobs-10.md) (CJ-, VR-, TX-, SW-, CU-, CO- and FC-), so a citation
never has to say which file; `creator-jobs.md` says what the road map builds and how its IDs are
made (CJ-7). This file is new because `creator-jobs-10.md` reached 483 lines with VR3a's entries,
near the road map's ~500-line split rule; each phase's decisions are appended here from now on,
before its code.

## VR3b — File ▸ Make Vertical Version… (2026-11-03)

Recorded before the code. VR3b is the second half of VR3's split (the road map's "Split"
paragraph under VR3): VR3a settled the step, the copy and `make_vertical_version` (VR-30…VR-37);
this phase is the menu command over them, and it builds what VR-30 and VR-37 left owed. No core,
FFI, header, op, tool or `Kind` change, and no format change (43 stands; `OP_COUNT` 70; 124
product tools); nothing is sent anywhere, so nothing is keyed (VR-2, CJ-3). The owner's answers
of 2026-11-01 for VR3 stand: 4:5 is offered beside 9:16 and 1:1 (VR-32), and the copy opens with
the step as its one undo step (VR-31). VR-38 is left to JOB-35.

- **VR-39 — File ▸ Make Vertical Version…** (`VerticalVersionSheetController.swift`,
  `EditorViewController+VerticalVersion.swift`, both new; `VerticalVersion.analysisTargets`,
  `offered` and `pendingSummary`). The command is VR3a's step over the top-level timeline,
  opened as a copy (the default) or applied in place as one undo step "Make Vertical".
  (a) **The item.** File ▸ Make Vertical Version…, directly under New Project from Range…, with
  no key equivalent. It is enabled with a document, no nest open (`scope == nil`), no sheet on
  the window, no recording running (`!ScreenRecorder.shared.isRecording`) and at least one clip
  in the project; otherwise disabled.
  (b) **The sheet.** Title "Make Vertical Version"; hint "Makes a version of the timeline for a
  tall or square canvas. Each full-frame movie clip follows its subject with eased moves, stills
  and nests are centred, and everything else is kept as placed, with a blurred copy behind a
  clip where it shows the whole picture. With Make a copy it opens as a new project and this one
  does not change. One undo step." The grid's rows:
  - Shape, a pop-up of `VerticalVersion.offered(canvas)` — `VerticalShape.allCases` whose
    VR-32 size differs from the canvas, in case order — each titled by its ratio then its size,
    "9:16 (1080 × 1920)", opening at the first offered shape;
  - Follow, Zoom and Where Empty exactly as VR-29 (b) has them (the same five follows, a
    whole-number field 100–400 and "%", Show Whole and Center, Where Empty disabled while Follow
    is Center), except that Zoom always opens at 100 %;
  - a "Make a copy" checkbox beside an empty cell, ticked when the sheet opens and never
    remembered (VR-30);
  - the summary; then Cancel and Make.
  The accessibility identifiers are `vertical.shape`, `vertical.follow`, `vertical.zoom`,
  `vertical.whereEmpty`, `vertical.copy` and `vertical.summary`.
  (c) **Remembered.** Follow and Where Empty are read and written through
  `FollowSubjectSettings.remembered` and `remember(changedFrom:in:)`, so they share VR-29 (c)'s
  two keys, `FrameJobFollowKind` and `FrameJobFollowWhereEmpty`: it is the same choice over the
  same op. Shape and Zoom are not remembered. Nothing is written at Cancel. No new key.
  (d) **Analysis (VR-37).** At `viewDidAppear` the sheet computes
  `VerticalVersion.analysisTargets(document.project, urls: document.mediaURLs())` — the media
  pictures (`mediaPictures(classify(project), …)`), split into those whose media has a URL
  (`present`) and those without (`missing`, kept, not followed) — and then
  `FramingAnalysis.requests(clips: present, in: document, project: document.project)`. It
  captures `document.project` and `document.scope` at that moment. Then, as VR-29 (d):
  - with nothing missing, it reads the subjects off main ("Reading the analysis…", Make
    disabled) and plans at every change;
  - with something missing, a following kind shows `pendingSummary(files: F, width: W, height:
    H)` — "Finds the faces, people and shot changes in F file[s] on this Mac first, then makes a
    W × H version." with F the distinct media of the requests — and Make is enabled;
  - Center plans with no subjects at once and never analyzes;
  - a thrown request error is the summary for a following kind, and Make is disabled.
  `make_vertical_version`'s first hop reads the same `analysisTargets`, so the two doors split
  the pictures one way; the tool's answers are unchanged.
  (e) **The plan** is `VerticalVersion.plan(document.project, settings:, subjects:, missing:)`
  on main; its summary is `summary(plan)` (VR-35). A `.refused` or thrown sentence is the
  summary, with Make disabled.
  (f) **Make** writes the remembered keys, dismisses the sheet and hands the editor one
  `VerticalHandOff` (the settings, `copy`, the targets — `present` for a following kind, none
  for Center — `missing`, the missing requests, the subjects read, and the project and scope of
  (d)) on the main queue's next turn after `viewDidDisappear`; never after Cancel. The sheet
  itself never edits and never opens a window.
  - The editor first checks `document.project === asked && document.scope == scope`, on both
    paths (the tool's last hop). With no requests and the check failing, it refuses with "the
    project changed while the Make Vertical Version sheet was open, so nothing was made. Choose
    Make Vertical Version again." and commits nothing. With requests and the check failing, it
    refuses with the analyzing sentence below and presents no Analyzing sheet.
  - With requests, the editor presents `AnalyzingSheetController(document:, command: "Make
    Vertical", rows:)`, each row named by `FollowSubject.rowName`.
  - When it has landed the editor checks the project and scope against the hand-off's again and
    refuses a change: "the project changed while Make Vertical was analyzing, so nothing was
    made. Choose Make Vertical Version again." Otherwise it reads
    `FollowSubject.subjects(targets, in: asked, cacheDir: document.cacheDirectory)` off main,
    checks again on main, and commits.
  - A failure is refused as "The <kind> analysis of “<file>” failed: <why>." **Stop makes
    nothing**: it is the Analyzing sheet's own behaviour, so no edit lands and no window opens
    (VR-37's owed Stop).
  (g) **The commit** plans again on `document.project`. With `copy` it calls
  `ProjectDocument.verticalCopy(from: document, plan:, shape:, path: nil, display: true)`: the
  copy's window opens in front, untitled, named "<name> (<shape>)" (VR-31). Without it, it calls
  `document.performGroupedEdit("Make Vertical", plan.ops)`. Every refusal or error is a beep
  plus `projectDocumentDidRefuse` on the source with `ReelRefusal(op: "set_canvas", reason:)`,
  Follow Subject's shape. The summary is the sheet's: the copy opens with no further sheet.
  (h) **`-RCDevVerticalAccept`** (`FRAMEJOB_DEV_TOOLS` only): with `YES` (`bool(forKey:)`) the
  sheet presses Make once, the first time Make is enabled after the first summary (AU-128's and
  VR-29 (h)'s precedent); with `in-place` (`string(forKey:)`) it unticks Make a copy first and
  then does the same.
  (i) **The menu table and the screen.** `UIMenuTable`'s verdict for `showVerticalVersionSheet:`
  is `.sheet`; the screen is `15j-make-vertical-sheet` (not `18b`: `screens.py` runs screens in
  name order and requires the recorder panel, `16-recorder-panel`, to run last).
  (j) **VR3's review nit 1 is closed.** The tool's description and §7.9i's sentences about File
  ▸ Make Vertical Version… are true once the menu lands and stay unchanged; only the guide's
  `mcp.md` row loses its ", coming next".
  (k) **Manual check JOB-33**: a 1080p edit and a 4K one, each made 9:16 with the defaults,
  exported and watched on a phone — faces stay framed, titles and pictures-in-picture stay
  legible and inside the frame, the blurred copies read as deliberate, and the 1080p source's
  ×1.78 enlargement is acceptable with the 4K source visibly sharper (VR-32; `vr3_proof.py`
  scores placements, never how it looks on a phone).
  **Choices left to the code:** the sheet's subjects are kept for its life and every re-plan
  reads the document's current handle; the Shape pop-up's titles use `size(from:)` of the
  canvas the sheet opened on.

## VR4a — captions re-paged, presets by the short side, Re-lay Captions (2026-11-03)

Recorded before the code. VR4 is more than one pipeline, so it is split as VR3 was (the road
map's "Split" paragraph under VR4): **VR4a** is the captions half — the toll (`CaptionLayout.swift`'s
`// MARK: - Words into cues` moved whole into `CaptionCues.swift`, line-identical, gated alone),
VR-40, VR-41 and VR-45, with VR-46 its proof; **VR4b** is the graphics half (VR-42…VR-44, the
graphic counts in `make_vertical_version`'s answer, JOB-34's graphics half and JOB-35). No core,
FFI, header, op, `Kind` or format change (43 stands; `OP_COUNT` 70); one new product tool,
`relay_captions` (124 → 125). Nothing is sent anywhere, so nothing is keyed (CJ-3): no `ModelKeys`
row and no `AssistantToolTable` row. **The owner's answers of 2026-11-01 for VR4:** (1) Re-lay
Captions for This Canvas is offered on its own — yes, VR-45; (2) the pages are re-paged from the
pages, not regenerated from the cached transcript, so every correction is kept — VR-40. (3), the
old template copies, is VR4b's (VR-44).

- **VR-40 — Word caption pages are re-paged from their own words** (`CaptionRelayout.swift`, new;
  `CaptionPages.repage`). W-7 and W-10 stand: the measuring pager and `CaptionLayout.place` are
  the one builder and the one writer.
  (a) **The survey** (`CaptionRelayout.survey`, over one container's snapshot): the candidates are
  the tracks `CaptionLayout.isCaptionTrackName` accepts that hold at least one clip and only text
  clips. A candidate is **kept**, with the first reason that applies, in this order: "it is a
  matte track"; "it holds a page with no word timings" (`words(of:)` nil — Subtitles pages and
  untimed pages alike); "it holds a page none of whose words starts inside it" (`words(of:)`
  empty — a split's or a trim's half whose words all lie outside it); "it holds a page in a
  style Frame Job does not make"; "its pages are in more than one style". Otherwise it is
  **recognised** with its one style and looks. Both lists are in stack order, back first.
  (b) **Recognition** (`recognise`): a page is in a word style S with looks L when its `font` is
  S's and its `word_style` equals `S.wordStyle(L)`, tried for each word style in
  `CaptionStyle.allCases` order and, for each, the eight looks combinations that are their own
  `live(for: S)`. Subtitles is never a match.
  (c) **The words** (`words(of:)`): a page's whitespace tokens of `content` paired with
  `text.words` (nil when the clip has no text, no words, or a count that differs from the
  tokens), each in TIMELINE ticks (`clip.start + word.start`, `clip.start + word.end`), speaker
  nil, and only those whose timeline start lies in `[clip.start, clip.start + clip.duration)`. A
  split, `trim_start` or `roll` leaves a page holding words outside it (a negative start is
  legal); those belong to the other half or were cut away and are never clamped onto the clip's
  edge frames. A word starting inside and ending past the clip keeps its start; `normalize`
  clamps its end.
  (d) **The pager** (`CaptionPages.repage`): `build`'s pager over `normalize` with lead 0 (the
  engine's lead was applied once, when the pages were made), one clip at a time with `span` the
  clip's window, so a page is never merged with another and never leaves its clip. `build`'s
  output is unchanged (it is the same pager handed `lead(for: engine)`).
  (e) **The re-lay** (`relay`, on one `SwitchAngle.Trial`, the tracks back to front, each read on
  the trial's current snapshot): the clips' cues concatenated, then `CaptionLayout.place(cues,
  trackBase: <the old name>, style:, looks:, replacing: [old])` on the trial's handle, so the
  pages are measured on its canvas; `place`'s ops tried one at a time on a scratch copy of the
  trial and kept only when none is refused. A `LayoutError` (`tooMany`, `noCues`, `refused`) or
  a refusal keeps the track with its description as the reason, and nothing of it is applied.
  Then `move_track` of the new track (the id not in the snapshot before) to the old track's
  index, then `set_track {hidden: true}` and `{locked: true}` when the old track had them; the
  new track keeps the old name. The core's invalid input is thrown. `plan(project)` is `survey`
  then `relay` on a fresh trial, its outcome's kept list the survey's then the relay's.
  (f) **Make Vertical's step (6)** (`VerticalVersion+Plan.swift`): with `settings.captions` (the
  default) the step surveys the OLD snapshot first; step (3) skips the clips of the recognised
  tracks; after step (5) `relay` runs on the step's trial; `Plan.captions` is its outcome with the
  survey's kept tracks first. The clips of a kept (unrecognised) caption track stay class (6)
  `keep`, as before. A recognised track that `relay` keeps is given step (3)'s treatment after
  step (6): each of its clips `reframe_clip {follow: keep, from_width, from_height}` from the old
  canvas through `trial.require`, its `backdrop` the Backgrounds track when step (5) kept it
  (else none: the core throws for a track that is gone), a refusal stopping the step in step
  (3)'s sentence, and an entry `kept` with no reason; its reason is in `captions.kept`. So no clip
  of the old project is left without a reframe or an entry. With `captions: false` nothing is
  surveyed and the caption clips are VR3's `keep`.
  **Choices left to the code:** the relaid entry's `pages` is the plan's clip count; the summary's
  and the notice's spelling of a reason drops its final full stop.
- **VR-41 — Text presets are measured by the short side, and the Caption preset sits higher on
  a tall canvas; one function, three callers** (`TextPane.swift`'s `TextPreset`). `size(on:)` is
  `(sizeFraction × min(W, H)).rounded()`; `position(on:)` is `(xFraction × W, y × H)` with y the
  row's `tallYFraction` on a canvas taller than wide when it has one, else `yFraction`; the
  Caption row's `tallYFraction` is 0.25 (and `CaptionLayout.captionPreset`'s fallback's); the
  other three rows have none. `patches(on:)` is `TextPane.apply`'s two patches (the face, size,
  align, `valign: "middle"` and backdrop; x, y and opacity 1). The callers: `CaptionLayout.place`'s
  Subtitles path (its size by `size(on:)`, its wrap still `W × wrapFraction`, its `set_video` by
  `position(on:)`), `TextPane.apply` (through `patches(on:)`) and the Generate Captions sheet's
  Subtitles preview (`previewProps`, by `size(on:)`). On a canvas at least as wide as tall
  `min(W, H)` is H and `a × b == b × a` in IEEE 754, so landscape and square output is
  byte-identical; on a portrait canvas Subtitles from Generate Captions and Import Captions, Text
  ▸ Presets and the sheet's preview change (Caption on 1080 × 1920: size 38, wrap 864, y 480).
  **Counted:** `CaptionLayout.Plan.overTwoLines`, only for Subtitles on a canvas taller than wide,
  is the cues whose measured height (`LayerRenderers.measuredSize` of the props as placed) exceeds
  that of the same props with content "X\nX"; when it is above 0 `report` adds "N caption[s]
  wrap[s] to more than two lines on this canvas." The caption tools' answers gain no key.
  Amends **W-7** and spec §4.3d's Presets row ("Sizes are fractions of the canvas's short side,
  positions of its width and height (§11 VR-41).").
- **VR-45 — File ▸ Re-lay Captions for This Canvas, and `relay_captions`**
  (`EditorViewController+RelayCaptions.swift`, new; `AgentServer+VerticalVersion.swift`;
  `AgentCatalog+Framing.swift`). VR-40 on its own, for a project whose canvas changed by hand or
  whose captions were laid on another canvas, in the container being edited (the timeline, or
  the open nest, whose canvas is the nest's): `CaptionRelayout.plan(document.editedProject)`, and
  `performGroupedEdit` addresses the ops (`AgentServer+Scope.swift`'s rule: a producer reads the
  container it writes into).
  (a) **The item** sits after Export Captions… in `fileMenu()`, with no key equivalent (the
  caption items' reason there). It is enabled with a document, no sheet on the window, no
  recording running (`!ScreenRecorder.shared.isRecording`) and at least one recognised caption
  track in `editedProject`; otherwise disabled. The validator arm `validateRelayCaptionsAction` is
  one line in the frozen `EditorViewController.swift` after `validateFollowSubjectAction`.
  `UIMenuTable`'s verdict for `relayCaptions:` is `.plain`; the inventory's is `none`, with the
  notice's `beginSheetModal` site row.
  (b) **The command** refuses with a beep with no document, a sheet up or a recording running.
  With no ops it shows the notice; otherwise one undo step "Re-lay Captions"
  (`performGroupedEdit`), then the notice when a track was kept. The notice is an informational
  `NSAlert` sheet (`showShortcutOverlayNotice`'s shape): its message "Re-laid N caption track[s]
  for this canvas." (or "No caption track was re-laid.") and its informative text one line per
  kept track, `Caption track "<name>" is kept as placed: <reason>.`; none when every track was
  re-laid.
  (c) **The tool** `relay_captions {project?}` runs on main, declares no property of its own and
  acts in the container `set_scope` has open. **Deviation from the road map: no `scope`
  argument**, because dispatch reads `scope` only for op names (`AgentServer.swift`); it follows
  `set_scope`, as `add_shortcut_overlays` and `auto_zoom` do. With no ops it throws
  "relay_captions found no caption track it can re-lay: " and each kept track as `"<name>":
  <reason>`, joined by "; " (with none at all, "there is no track named Captions holding only text
  clips"). Otherwise `editResult(document, "Re-lay Captions", ops, …)`, answering `{ok, relaid
  [{track, replaced, name, style, pages}], kept [{track, name, reason}], project, …}` and
  `editResult`'s keys. It needs no key and is not ask-first.
  (d) **`make_vertical_version`** gains `captions` (boolean, default true, read with `boolArg`);
  its answer gains `captions {relaid, kept}` in the same spelling, absent when `captions` is
  false. The sheet (VR-39) has no Captions box and passes the default.
  (e) **The summary** (VR-35) adds "Re-lays N caption track[s] for the new canvas." after the
  counts, and one line per kept caption track after the entries' lines: `Caption track "<name>"
  is kept as placed: <reason>.`
- **VR-46 — VR4a's proof** (`vr4_proof.py`, `vr4_probe.swift`). Rows: **R1** (probe) every line of
  every re-paged page, measured as `CaptionPages` measures it, is ≤ 0.86 × 1080, a lone word
  carrying `width` excepted; **R2** every word's timeline start equals its source page's and no
  word appears twice, over a fixture holding a page cut by `split` mid-page and a page trimmed by
  `trim_start` past its first word, each word landing once in the half its start lies in, never
  on a half's first or last frame unless its start was there; **R3** a word corrected by
  `set_text` survives; **R4** each style keeps its font and `word_style`, looks included, over
  Highlight + Fill, Pill + Slide, Karaoke, Build and One Word laid by the probe's `pages` mode
  (`CaptionPages.build` + `place` on 1920 × 1080, sent as op tools); **R5** an untimed track and
  a Subtitles track keep their clip ids, are listed with their reasons and in Make Vertical are
  rescaled by `keep`; **R6** (probe) the three sites give VR-41's size, wrap and y on 1080 × 1920
  (38, 864, 480 for Caption) and on 1920 × 1080 and 1080 × 1080 patches byte-identical to the old
  formula, spelt out in the probe, and `overTwoLines` is counted; **R7** `make_vertical_version`
  answers `captions.relaid` and `captions.kept` as one undo step, and with `captions: false` the
  caption clips are VR3's `keep` with no `captions` key; **R8** `set_canvas 1080 × 1920`, then
  File ▸ Re-lay Captions for This Canvas by `perform_menu_item`: one undo step "Re-lay Captions",
  R1's measure, the untimed track kept and named in the notice (`snapshot_ui`), `relay_captions`
  on a second copy giving the same `get_project`, the item off with no caption track; **R9** a
  recognised track that was not front-most keeps its index, name and hidden and locked flags;
  **R10** (probe) Make Vertical with a recognised track whose re-page throws `tooMany` (a
  fixture filled near `RC_MAX_CLIPS` with one-frame text clips on another track): the track in
  `captions.kept` with `tooMany`'s description, every one of its clips with a `reframe_clip …
  keep` op and a `kept` entry, the plan applied, not refused; **Z0** the parity grep. Nine
  mutants, each caught by its row: `old-width` (R1), `clip-time` (R2), `lead-applied` (R2),
  `subtitles-fallback` (R4), `apply-height` (R6), `replace-unrecognised` (R5/R8), `front-track`
  (R9), `all-words` (R2), `failed-unkept` (R10) — the road map's three graphics mutants are
  VR4b's. **JOB-34**, its captions half: re-laid captions look intended on 9:16 and 1:1 (VR4b
  extends it to graphics).

**Amendments recorded by VR4a.**
- **VR-34** (step 6): its captions are built by VR-40 (f); its graphics are VR4b's (VR-42).
- **VR-35**: the summary's caption lines are VR-45 (e)'s.
- **VR-36**: `make_vertical_version` takes `captions?` (VR-45 (d)), with `captions {relaid, kept}`
  in its answer.
- **W-7**: on a canvas taller than wide, the Subtitles cue builder's size is 3.5 % of the short
  side and its line 25 % of H below centre, through `TextPreset`'s functions; landscape and square
  output is byte-identical (VR-41).

**Deviations from the road map's draft, recorded before the code.** (1) VR4 is split into VR4a and
VR4b. (2) `relay_captions` takes no `scope` argument (VR-45 (c)). (3) Its spec text is §7.9i,
where VR3a put `make_vertical_version`, not §7.9e. (4) The kept reasons gain "it holds a page none
of whose words starts inside it" and "it is a matte track", and a recognised track the re-lay
keeps is reframed by `keep` (VR-40 (a), (f)). (5) Nine mutants, the graphics three VR4b's.

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
