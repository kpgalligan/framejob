# Spec §11 — decisions: Creator jobs, Follow Subject onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) …
[`creator-jobs-9.md`](creator-jobs-9.md) (CJ-, VR-, TX-, SW-, CU-, CO- and FC-), so a citation
never has to say which file; `creator-jobs.md` says what the road map builds and how its IDs are
made (CJ-7). This file is new because `creator-jobs-9.md` held VR2b1's entries past the road
map's ~500-line split rule; each phase's decisions are appended here from now on, before its code.

## VR2b2 — Clip ▸ Follow Subject… (2026-11-03)

Recorded before the code. VR2b2 is the second half of VR2b's split (the road map's "Split"
paragraph under VR2b): VR2b1 settled VR-27 and `reframe_clip`'s `replace`; this phase is the
menu command over it. No core, FFI, header, op, tool or `Kind` change, and no format change (43
stands; `OP_COUNT` 70; 122 product tools); nothing is sent anywhere, so nothing is keyed (VR-2,
CJ-3). The owner's answers of 2026-11-01 for VR2b stand: the default zoom is fill (100 %), two
people who do not fit are framed by following one, and the headroom is 38 % (VR2a's settings,
VR-22, VR-24 (g)).

- **VR-29 — Clip ▸ Follow Subject…** (`FollowSubject.swift`, `FollowSubjectSheetController.swift`,
  `EditorViewController+FollowSubject.swift`, all new; `FramingAnalysis.swift`'s `qualifies`).
  The command is `reframe_clip` with `replace: true` on each selected clip and a "Backgrounds"
  track as `backdrop`, as one undo step "Follow Subject".
  (a) **Offered** on the selected clips of the edited container (the timeline or the open nest)
  for which `FramingAnalysis.qualifies` holds — a media clip of a video media with a picture,
  `windows`' own test, lifted out of it — in id order (`FollowSubject.targets`). Enabled with at
  least one and no sheet on the window; the others in the selection are left alone and not
  listed. Stills, pictures, nests, text, shapes, graphics and adjustment clips are never offered.
  (b) **The sheet.** Title "Follow Subject"; hint "Frames each selected clip on its subject with
  eased moves on its action lane, and a blurred copy behind it where it shows the whole picture.
  Replaces the clips' own position and scale. One undo step." Rows: Follow, a pop-up (Subject,
  Faces, People, Salient Region, Center → `subject`, `face`, `person`, `salient`, `center`); Zoom,
  a whole-number field 100–400 and "%"; Where Empty, a pop-up (Show Whole → `fit`, Center →
  `center`), disabled while Follow is Center; the summary; Cancel and Follow. The Zoom field
  opens at 100 % (fill, the owner's answer) unless the first target's media `width / height` is
  within 1 % of the canvas's aspect, when it opens at 125 % (VR-29's draft: a picture already the
  canvas's shape gains nothing at fill). Zoom is never remembered.
  (c) **Remembered**: Follow and Where Empty, as their raw values under `FrameJobFollowKind` and
  `FrameJobFollowWhereEmpty`. An absent or unknown value reads as `subject` / `fit`; a launch
  argument counts (the argument domain). Each key is written at Follow only when its value
  changed from what the sheet opened with. `reframe_clip`'s tool reads no `UserDefaults`
  (AU-68 (f)): its `where_empty` stays the core's default, `fit`.
  (d) **Analysis** (CJ-28). The requests are `FramingAnalysis.requests(clips: targets, in:
  document)` (VR-12's three kinds), the same for every Follow.
  - The sheet opens at once and computes them. When none are missing it reads the subjects off
    main ("Reading the analysis…", Follow disabled), then plans on main at every control change.
  - When some are missing and Follow is a following kind, the summary is the pending one ((g));
    Center plans without subjects. A thrown request error is the summary for a following kind.
  - **Follow with Center never analyzes**: whatever is missing, it writes the remembered keys and
    commits at once on the current handle (VR-26: only the following kinds read `subjects`).
  - Follow with a following kind and requests missing writes the remembered keys and dismisses.
    On the main queue's next turn after `viewDidDisappear`, the editor presents the Analyzing
    sheet, one row per request, named "<file> — Shot changes", "<file> — Faces" or "<file> —
    People and salient regions".
  - Once it lands: if the project or scope changed, the command is refused with "the project
    changed while Follow Subject was analyzing, so nothing was framed. Choose Follow Subject
    again.". Otherwise the subjects are read off main, the plan is made on the current handle,
    and it is committed with `performGroupedEdit`.
  - A failure is refused as "The <kind> analysis of “<file>” failed: <why>." Stop changes nothing.
  - Every refusal is a beep plus `projectDocumentDidRefuse` with `ReelRefusal(op: "reframe_clip",
    …)`, Split at Shot Changes' shape.
  (e) **The plan, in VR-29's order**, on the edited container's handle through
  `SwitchAngle.Trial`:
  - `add_track {index: 0, name: "Backgrounds"}` first, required: a refusal answers "Follow
    Subject was refused at add_track: <reason>" and nothing is planned. The track's id is read
    from the trial's snapshot.
  - Then each target's `reframe_clip {clip, follow, zoom, replace: true, backdrop}`, with
    `where_empty` and `subjects` for the following kinds only, applied on the trial's project
    directly: applied → kept and counted; identity → listed as already framed; refused → left
    out and listed with the core's sentence.
  - `moreTracks` is the sum, over the applied ops, of the trial snapshot's track count after the
    op minus before it: VR-25's new back-most track when the copy's span meets a copy already on
    Backgrounds (two selected clips overlapping in time). Swift restates none of VR-25's test; it
    counts what the core made.
  - Then `remove_track` of Backgrounds when no clip is on it.
  - With nothing framed there are no ops: Follow is disabled and the summary lists the refusals.
  - Follow (or the Analyzing sheet's hand-back) plans again on the document's current handle and
    applies the plan's ops with one `performGroupedEdit("Follow Subject", …)`.
  (f) **Counts** (VR-27 (f) under `replace`), per clip, from the container's handles before and
  after its op: re-eased = an action id in both whose duration shrank and whose after curve is
  not `linear`; carried = an action with the same id, start and duration in both, across which
  the AFTER handle's `clip_state` `video` `scale`, `x` or `y` differs by more than 1e-6, read at
  project time `clip.start + action.start` and `clip.start + action.start + action.duration`.
  (g) **The summary**: "Frames N clip[s]." then " Adds a Backgrounds track for the blurred copy."
  when Backgrounds is kept; " Adds T more track[s] behind it where clips overlap." when T > 0;
  " K action[s] re-eased at a cut." when K > 0; " M action[s] carry a framing move." when M > 0;
  then one line each, "Clip C is already framed this way." and "Clip C: <sentence>". Pending:
  "Finds the faces, people and shot changes in F file[s] on this Mac first, then frames N
  clip[s]."
  (h) **`-RCDevFollowAccept YES`** (`FRAMEJOB_DEV_TOOLS` only) presses Follow once, the first
  time Follow is enabled after the first summary (AU-128's precedent).
  (i) **The menu**: Clip ▸ Follow Subject… right after Auto Zoom… (both write moves on the action
  lane), no key equivalent; `UIMenuTable`'s verdict `.sheet`; the screen
  `15i-follow-subject-sheet`.
  (j) **VR-13's suffix lands**: Show Subjects' label is "Not analyzed — Clip ▸ Follow Subject…
  analyzes it".
  (k) **Manual checks**: JOB-31 (the framing's feel on T1 / S-TH1: no fidget, no lag, moves
  where a camera operator would make them) and JOB-32 (S-PC3's two-shot: framed together when
  both fit, else one followed — the owner's answer — with no ping-pong).
  **Choices left to the code:** the Zoom field's `%` is a whole number and its op value is the
  field over 100; the subjects the sheet read are kept for its life and every re-plan reads the
  document's current handle.
