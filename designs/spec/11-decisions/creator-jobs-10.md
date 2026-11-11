# Spec §11 — decisions: Creator jobs, Follow Subject onward (road map "creator-jobs", from 2026-11-03)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) …
[`creator-jobs-9.md`](creator-jobs-9.md) (CJ-, VR-, TX-, SW-, CU-, CO- and FC-), so a citation
never has to say which file; `creator-jobs.md` says what the road map builds and how its IDs are
made (CJ-7). This file is new because `creator-jobs-9.md` held VR2b1's entries past the road
map's ~500-line split rule; each phase's decisions are appended here from now on, before its code.

VR-30…VR-37 (VR3a) and CO-80…CO-84 (CO8) are in [`creator-jobs-10b.md`](creator-jobs-10b.md), moved
there unchanged on 2026-11-11 because this file had passed the spec's ~500-line split rule (#548).

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

## SW8 — Switch by Speaker with one shared microphone, decided by faces (2026-11-03)

Recorded before the code. With one microphone between two or more people and a camera on each,
Clip ▸ Switch by Speaker… and `switch_by_speaker` decide who talks from each angle's cached
`faces` while the microphone hears speech, and feed SW-22's shot rules unchanged. The owner's
answer (2026-11-01) to the road map's SW8 question — "proceed at SW-S3's middle band?" — was
*yes, with SW-82's hedge*. SW-S3's agreement arm needs S-PC2, which the owner has not recorded:
it skips by name and is owed (SW-88), which is not a stop. No core, FFI, header, op, format or
tool-schema change.

- **SW-80 — Faces are CJ3's `faces` kind, read as CJ-30 stores it.** Per sample of the
  10-a-second grid, each face's box and its mouth's inner-lip gap and outer-lip width (each over
  the box's height), read through the analysis store in forward-media source ticks with no ids
  (CJ-31). SW8 makes no Vision request of its own, bundles no model, and adds no `mouths` kind:
  CJ-S2's rule 4 kept the landmarks in `faces`.
- **SW-81 — Mouth activity, and who is talking** (`FaceActivity.swift`, pure; `SpeakerSwitch+Faces`).
  - The opening of a sample is the largest face's `mouthGap / mouthWidth` — the largest by
    width × height, ties to the first in CJ-31's order. It is nil when the sample has no frame
    (pts −1), no face, a non-finite gap or width, or a width ≤ 0.
  - Activity at a sample is the population standard deviation of the non-nil openings among the
    samples within `window` (0.5 s) centred on it: `halfWidth(rate) = ⌊window/2 · rate⌋` each side
    (2 at 10 a second, 1 at 5), clipped at the media's ends; nil when fewer than two openings are
    there. A sample the marker does not cover has no opening.
  - A 10 ms step's activity on an angle is the activity at the sample nearest
    (`grid.index(of:)`) the forward source tick of the step's midpoint, taken through the angle
    clip covering the midpoint (the later-starting one where two cover;
    `AnalysisClipTimes.source(atClip:)`, the inverse of `clipTime(ofSource:)`); nil outside the
    media's 0…duration, off every clip, or uncovered. Only clips of moving-video media count.
  - A step is speech when the one microphone covers it and its v ≥ `voice_threshold` (SW-21's).
  - The label (`FaceActivity.label`), over the face speakers' angles front first: no speech →
    nobody; no non-nil activity → nobody; else the top angle (ties to the front-most) is the
    person when top ≥ `ratio` (1.5) × next — next the second-highest, 0 when the top is alone —
    and top > `floor`; otherwise crosstalk. The floor is 0.02 (the opening's standard deviation),
    provisional until SW-S3 sets it (SW-88).
  - SW-22 then runs unchanged over those labels with the face pairing (SW-83): `labels` and
    `shots` in `SpeakerSwitch+Shots.swift` are not edited.
- **SW-82 — How sure it says it is: the middle band.** In faces mode the sheet's summary and the
  tool's `note` begin "Faces guess who is talking; check the cuts.", and `min_shot` defaults to
  3 s (the sheet's one-microphone form opens at 3 s; the tool takes 3 s when `min_shot` is
  absent). The microphones mode keeps SW-26's 2 s.
- **SW-83 — The faces mode and its pairing** (amends SW-20 and SW-24).
  - SW-20's defaults: when the microphones number exactly one and the angles two or more, the
    pairing is every angle, front first, with that microphone, and no wide.
  - Where the tool names `wide` without `speakers`, or the one-microphone form picks a Wide, the
    pairing is `withoutWide(Pairing(the implied speakers, wide))`: each speaker whose angle is the
    wide AND whose microphone another speaker shares is dropped; any other pairing is unchanged.
    One microphone M with angles A and B and the wide B is `[(M, A)]`, wide B — microphones mode,
    planned exactly as before SW8.
  - The mode is `mode(pairing)`: faces when the face speakers — the speakers with an angle that is
    not the wide, the first per angle — number two or more and all name one non-nil microphone;
    else microphones. In faces mode a speaker whose angle is the wide takes no part, the face
    pairing is each face speaker as `(mic: its angle, angle: its angle)` with the same wide, and
    SW-24's "Track T is the microphone for N speakers" refusal applies only in microphones mode.
  - The microphones mode is unchanged byte for byte: `withoutWide` changes nothing where no two
    speakers share a microphone.
- **SW-84 — The faces are read, wanted and refused** (amends SW-24, SW-25, and CJ-28 as CO-6
  did). `SpeakerSwitch.readFaces` and `facesWanted` are the switch's second and third readers;
  `read` calls `readFaces` in faces mode and appends its problems after the microphones'.
  - Each needed window is the source span of each face speaker's angle clip's part inside the
    range, widened by `window/2` each side and clamped to 0…duration; only clips of moving-video
    media count. `facesWanted` (main thread) asks `analysisRequest(kind: .faces, …)` per window
    and merges each media's misses with `AnalysisStore.merged`, as `ShotSplit.wants` does.
  - SW-24 gains two refusals. From `read`, per face-speaker angle front first, after the
    microphones' problems: "The camera on track T is still being analyzed — its faces have not
    been found yet. Try again in a moment." (amended by #526) (a needed window the store does not answer). Pure, in
    `refusals`, right after the no-speech refusal: "The camera on track T shows no face whose
    mouth can be read between A and B, so it never says who is talking." (a read angle whose
    activity is nil on every step).
- **SW-85 — The sheet's one-microphone form, and the menu's Analyzing sheet.**
  - The form is chosen at open when `mode` of the implied pairing is faces: a Microphone popup
    (`microphoneChoices`), "Cameras:" naming every angle, then Wide ("None" to start), Minimum
    shot (opens at 3 s; never reads or writes `FrameJobSwitchSpeakerMinShot`), Cut, Crosstalk,
    "Cut to the wide after", Mute and Write to; no Ignore bleed row. Its pairing is `withoutWide`
    of every angle with the popup's microphone, plus the Wide; the hedge leads the summary while
    `mode` of that pairing is faces.
  - The menu runs `read` at default settings. In faces mode with `facesWanted` non-empty it shows
    CJ-28's Analyzing sheet (command "Switch by Speaker"), and on `.landed` the switch sheet. A
    project or scope changed since the press refuses "the project changed while Switch by Speaker
    was analyzing, so nothing was switched. Choose Switch by Speaker again."; `.failed` refuses
    "The faces analysis of “name” failed: why." Each refusal is a beep and
    `.projectDocumentDidRefuse` (op `switch_by_speaker`), `ShotSplit`'s shape.
- **SW-86 — The tool runs off main and waits** (amends SW-26 (c)): `switch_by_speaker` is in
  `creatorOffMainTools`, CJ-28's "a tool call shows no sheet and waits", `split_at_shots`' shape.
  - `AgentLane.shared.callCancel` is taken first; on the main thread the call throws
    "switch_by_speaker must run on the server thread — its name is missing from
    AgentServer.creatorOffMainTools."
  - One main hop: SW-26 (c)'s arguments and errors, the pairing, `min_shot` absent and
    `mode(pairing ?? implied pairing)` faces giving 3 s, `read`, `facesWanted` (its request
    errors thrown), and the document's project and scope kept. With no wants the same hop runs
    SW2b's sequence and answers.
  - With wants: their requests wanted under one owner of the call's own (`alive`: the document
    open and the call not stopped; `settled`: `packageContentsDidChangeOnDisk`), `lane.wait` to
    `AnalysisLane.callWaitLimit` (60 s), the owner released on every exit. `.failed` "The faces
    analysis of media N failed: why."; `.cancelled` "The faces analysis of media N was stopped
    before it finished, so nothing was switched."; `.timedOut` "The faces analysis of media N did
    not finish in the 60 s a call waits; what it covered is kept — call switch_by_speaker again
    to continue."
  - Then a second main hop: a changed project or scope refuses "the project changed while Switch
    by Speaker was analyzing, so nothing was switched. Call switch_by_speaker again."; else `read`
    again and SW2b's sequence unchanged.
  - The answer gains `mode` ("microphones" or "faces") always, and `note` (SW-82's hedge) in
    faces mode. The arguments and the schema are unchanged; the catalog's prose names the faces
    mode, the wait and its refusals.
- **SW-87 — The proof.** `switch_faces_probe.swift`, scored by `switch_faces_probe.py`: P1 the
  largest face and the opening's nils; P2 `activities` at half 2 and 1, clipped edges, under two
  values nil; P3 `label` at 1.5× and 1.49×, at the floor and just above, no speech, one angle,
  all nil; P4 SW-83's defaults, `withoutWide`'s three cases, the shared-microphone refusal and
  `plan` over synthetic series; P5 the pending and no-face refusals in order; P6
  `source(atClip:)`'s round trip (trimmed, speed 2, reversed) and `faceSeries`' later-starting
  clip and off-clip nil. Four mutants: ratio-removed (P3), voice-gate-removed (P3), first-face
  (P1), wide-in-contest (P4). `switch_faces_proof.py` drives the app over F-TURNS' cameras and
  ONE microphone (`mic_a_b12_f55.wav`) with canned `faces` (CJ-26; 36-byte records, the mouth
  gap alternating 0.05/0.20 of the box per sample at width 0.5 inside that speaker's utterances,
  0.05 outside, the wide two still faces): M0 the parity line; M1 faces mode with the wide named,
  the hedge, two speakers, the manifest's shots within τ_f and one undo step; M2 the defaults,
  three speakers and every shot ≥ 3 s; M3 cam_b's faces absent waits the bound and refuses, its
  mutant wait-removed; M4 the two-microphone selection answers microphones; M5 the menu's
  Analyzing sheet; M6 the menu's project equals the tool's. τ_f = 64 ms + 250 ms (half the face
  window) + 100 ms (one face sample) + one frame = 268,400 ticks (447.3 ms), fixed before the run.
  F-TURNS rows skip by name without `say`'s voices. JOB-55 is the person's check on S-PC2.
- **SW-88 — SW-S3's head.** `creator_spike/mouth_spike.py` checks the rule's hash
  (`rule.check_rule("SW-S3")`) and writes `results.json`. The rule's rate half is met by CJ-S2's
  recorded 10.30× (1080p30) and 8.88× (4K30) against 4× realtime per angle. The agreement half
  skips by name while S-PC2 is absent and is owed; the band is the middle one by the owner's
  answer. The floor 0.02 is provisional until S-PC2 measures it: then the high band drops SW-82's
  hedge, and the low band files the road map's candidate.

## CU10 — the recorder polishes on landing (2026-11-03)

Recorded before the code. CU10 runs CU7's Auto Zoom, CU8's Add Shortcut Overlays and CU9b's
Speed Up Typing over a finished screen recording's clips, after the landing, from three
remembered recorder-panel boxes under "When it lands:" and from `record_screen`'s (and the dev
tool `land_recording`'s) `auto_zoom`, `shortcut_overlays` and `speed_up_typing`. The owner's
answer (2026-11-01) sets the defaults: "the landing checkboxes default to zoom on, shortcuts on
when recorded, and speed-up off". No new tool, op, `rc_*` export, format or core change (43
stands); nothing is sent anywhere, so nothing is keyed (CJ-3). The product tool count (123) and
the dev tool count are unchanged.

- **CU-100 — Follow-ups, not part of the landing** (AU-68's shape). The landing, its step names,
  its notes and the answer's landing fields are unchanged. Each command is its own undo step,
  named by its title: "Auto Zoom", "Add Shortcut Overlays", "Speed Up Typing" (the speed-up's
  "and Re-time Captions" when captions ride, as its sheet's). The panel commits through
  `document.performGroupedEdit`, because a timer is not an AppKit event. The tool door calls
  each tool's own body, `autoZoom(document:clips:settings:)`,
  `addShortcutOverlays(document:clips:settings:)` and `speedUpTyping(document:clips:settings:)`
  (`from`/`to` nil; the `(_ a:)` handlers call the same bodies, their answers and refusals byte
  for byte as before). The panel door plans through `AutoZoom.plan`,
  `ShortcutOverlays.prepared` and `SpeedUpTyping.resolve`, the menu doors' planners.
- **CU-101 — Order, the clips, readiness and the two follows.**
  - (a) **Order.** Enhance Voice first, when asked: the polish waits while
    `RecordingEnhance.isUnderWay(document)` — the follow's timer or the measurement its
    `.enhance` step began, until that has landed its step, its refusal or its Cancel (amended
    2026-11-09, #546; before, `isPending`, the timer alone) — and its clock restarts when that
    ends. The tool door polishes after `enhanceVoice` returns, and its `decide` reads the same
    `isUnderWay`, for a panel landing's Enhance in the same document. Then Auto Zoom (zooms are planned on unsplit clips),
    then Add Shortcut Overlays, then Speed Up Typing (its stretches avoid the overlays, CU-91).
    `RecordingPolish.commands(of:)` answers the chosen commands in that order (`allCases`).
  - (b) **The clips.** `screenPaths(of:)` is each segment's movie path (none for a voice-over or
    a camera alone). `screenClips` is every clip of the open container whose media's path is one
    of them AND whose media has a cursor file, in id order. It is recomputed at every check, so
    the speed-up's splits and any clips added later are seen.
  - (c) **Readiness.** Auto Zoom and Add Shortcut Overlays need only the cursor files, read once,
    off main. The speed-up is ready when `SpeedUpTyping.resolve` does not answer `.waiting`; its
    first `.waiting` calls `document.generateCaches()`. A throw counts as ready, so the run
    reports the refusal.
  - (d) **Busy** is AU-68 (c)'s: `RecordingEnhance.isBusy` (a drag, or the open container is not
    the landing's), plus at the panel no editor window or a sheet already on it.
  - (e) **`decide`, in this order:** no clips → `.drop`; `enhancing` → `.wait`; ready and not
    busy → `.run(command, clips)`; `elapsed ≥ 300` s (`waitLimit`) → `.giveUp(command)`;
    otherwise `.wait`. Pure.
  - (f) **The panel's follow.** Each landing gets a follow of its own, never joined (unlike
    AU-68's). A repeating 0.5 s timer (`checkInterval`, the landing's) runs in the DEFAULT
    run-loop mode, so it waits out a drag. The follow ends FIRST — its timer invalidated and its
    entry removed — on `.drop`, on `.giveUp`, after the last run, or when the cursor files fail
    to read; then the step acts. A refusal from one run moves on to the next command, whose clock
    starts then. `isPending(document)` is true while any follow of that document runs.
  - (g) **The panel's settings.** `AutoZoomSettings.remembered(.standard)` with `typing =
    AutoZoom.hasTyping(tracks)` (CU-76's sheet rule), `ShortcutOverlaySettings()` (the menu
    item's), and `SpeedUpTypingSettings.remembered(.standard)` — what each menu door would use.
  - (h) **The panel's quiet and refused results.** A plan with no ops is quiet, and so is
    `.drop`. A refusal, `.giveUp` or a read failure posts `projectDocumentDidRefuse` with
    `ReelRefusal(op: command.rawValue, reason:)` at the inspector's foot, as
    `RecordingEnhance.refuse` does. No beep, no sheet.
  - (i) **The speed-up's question.** The panel cannot ask (no person pressed anything): a
    speed-up whose `SpeedAudioDrop.crossing` is non-empty is not applied, and its refusal is
    `SpeedAudioDrop.note(crossing)`. Otherwise it applies `CaptionRetime.withRetime(
    SpeedUpTyping.actionName, speechOps + plan.ops, on: document.editedProject)` grouped.
  - (j) **The tool door** (`AgentServer.polishLanded`, SERVER THREAD) polls `decide` through
    `onMain` every 0.5 s, with the tools' defaults (`AutoZoomSettings()`,
    `ShortcutOverlaySettings()`, `SpeedUpTypingSettings()`; a tool reads no `UserDefaults`). Its
    readiness is the same `isReady`, the cursor files read once on the server thread. On
    `.drop`, `.giveUp` or the call's cancel, every command not yet run gets its sentence in
    `…_error`. A body's `ToolError` becomes that command's `…_error`, and the door continues. The
    answer gains `auto_zoom` / `auto_zoom_error`, `shortcut_overlays` /
    `shortcut_overlays_error` and `speed_up_typing` / `speed_up_typing_error` — each the tool's
    answer object, or a sentence — and `project` is read last when enhance or the polish ran.
  - (k) **Sentences.** `noScreenSentence`: "No screen clip with a cursor file landed on the
    timeline, so <title> did not run." `notReadySentence`: "<title> did not run on the recording:
    " + (the speed-up: "its speech was not detected within 5 minutes." | otherwise: "the project
    was busy for 5 minutes.") + (panel: " Select its clips and choose <menuPath>." | tool: " Call
    <rawValue> with its clips."). `stoppedSentence`: "record_screen was stopped before <title>
    ran, so it did not run." The titles are each command's `actionName`; the menu paths are
    "Clip ▸ Auto Zoom…", "Clip ▸ Add Shortcut Overlays" and "Clip ▸ Speed Up Typing…".
- **CU-102 — The keys, the panel's rows and the tools' arguments.**
  - (a) **The panel rows**, under the Record shortcuts note and before Rate: "When it lands:"
    with **Zoom in on clicks**, then **Show shortcuts** and **Speed up typing** under it. Zoom in
    on clicks is live only while idle with a screen source (a display, window or picked one);
    Show shortcuts and Speed up typing only then AND with Record shortcuts ticked. Greyed, each
    keeps its value. `applyPolish`: `autoZoom` = its box && a screen source; the other two = their
    box && `choice.keys == .shortcuts`. The keys `FrameJobRecordingAutoZoom`,
    `FrameJobRecordingShortcutOverlays` and `FrameJobRecordingSpeedUpTyping` are the panel's
    fourteenth to sixteenth, written on change and restored on show; an absent key (tested by
    `object(forKey:) == nil`) reads on, on and off (the owner). The harness and `screens.py` pin
    them at those values. Each box's tooltip names its step.
  - (b) **`record_screen`'s refusals.** `auto_zoom`, `shortcut_overlays` and `speed_up_typing`
    are booleans, default false (a tool reads no `UserDefaults`). They are read right after
    `enhance` and refused before any grant, in the order auto_zoom, shortcut_overlays,
    speed_up_typing, each checking `place` and then `keys`:
    "auto_zoom: true plans on the landed screen clips, so it needs place: true." /
    "shortcut_overlays: true places overlays over the landed screen clips, so it needs place:
    true." / "shortcut_overlays: true needs keys: \"shortcuts\" — without it the cursor file
    records no shortcut to show." / "speed_up_typing: true speeds up the landed screen clips'
    typing, so it needs place: true." / "speed_up_typing: true needs keys: \"shortcuts\" —
    without it the cursor file records no typing to speed up." With `voice_over` or `camera`, each
    is a stranger refused by name in the existing lists (`voiceOverScreenOnlyArguments`,
    `cameraRefusedArguments`).
  - (c) **`land_recording`** (the dev tool) takes `keys` (`RecordingKeys`) and the same three
    booleans, each only with `movie`: without it, "<arg> cannot be given without movie — a
    voice-over has no screen clips." The shared `recordingPolish(a, place: place ?? true, keys:
    keys ?? .off)` runs after the `follow_wait` checks. Its panel door also waits on
    `RecordingPolish.isPending` and answers `polish_pending`. Its `RecordingChoice` is built by
    the tool itself, so the three `FrameJobRecording…` polish keys never reach it; the panel
    door's plan reads the Auto Zoom and Speed Up Typing sheet keys (CU-101 (g)).
- **CU-103 — The proof.** `tools/proof/cu10_proof.py` (MCP): Z0 (no "Frame Job: " in any
  instance's log); P1 the door tool with `keys: "shortcuts"` and all three into a fresh project —
  the answer holds the three objects, undo reads "Speed Up Typing", "Add Shortcut Overlays",
  "Auto Zoom", "Add Recording", and `get_project` equals a second fresh landing given the three
  tools by hand; P1b the panel door with `follow_wait`, on its own instance with the nine Auto
  Zoom and Speed Up Typing sheet keys pinned at their defaults by launch arguments — the same
  names in order and the same project; P2 the speed-up waited for speech (`speech_saved` names
  the voice); P3 `auto_zoom: true` refused by name with `source: voice_over` and without `movie`;
  P4 `place: false` and `speed_up_typing` without `keys` refused in CU-102 (b)'s sentences through
  both tools, the project unchanged. App mutants `wrong-order` and `one-step` on `tree_copy.py`
  copies, caught by P1. `tools/proof/cu10_probe.py` (built through `swift_build.build()`, the
  panel never shown): Q1 the grid rows, titles and action; Q2 absent keys on, on, off, persist and
  restore; Q3 the enabling and `applyPolish`'s gates; Q4 `commands(of:)`'s order; Q5 `decide`'s
  arms; Q6 `recordingPolish`'s and `recordingSourceKind`'s refusals, exact. Probe mutants
  `place-admitted`, `keys-admitted` (Q6), `enhance-ignored`, `ready-ignored` (Q5),
  `absent-zoom-off` (Q2) and `shortcuts-without-keys` (Q3). No JOB row: the feel is CU12's
  trial. `recording_proof.py` and `camera_recording_proof.py` gain the arguments in
  `RECORD_PROPERTIES` and are not run (they record only when granted).
