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
