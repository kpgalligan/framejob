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
    microphones' problems: "The camera on track T is still being analysed — its faces have not
    been found yet. Try again in a moment." (a needed window the store does not answer). Pure, in
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
    `RecordingEnhance.isPending(document)`, and its clock restarts when that ends. The tool door
    polishes after `enhanceVoice` returns. Then Auto Zoom (zooms are planned on unsplit clips),
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

## VR3a — Make Vertical's step, its copy and make_vertical_version (2026-11-03)

Recorded before the code. VR3a is the first half of VR3's split (the road map's "Split"
paragraph under VR3): the step as a function of a document, the copy through CJ5b's derived
document, and the tool. VR3b, next in lane C and before VR4, adds File ▸ Make Vertical
Version… and its sheet, the Analyzing sheet and its Stop, `-RCDevVerticalAccept YES`, the
screen, the guide, spec §9 and JOB-33. No core, FFI, header, op or `Kind` change, and no format
change (43 stands; `OP_COUNT` 70); one product tool (123 → 124); nothing is sent anywhere, so
nothing is keyed (VR-2, CJ-3). The owner's answers of 2026-11-01 for VR3: 4:5 is offered beside
9:16 and 1:1 (VR-32), and the copy opens with the step as its one undo step (VR-31). VR-38 is
left to JOB-35.

- **VR-30 — Make Vertical is one grouped edit applied to a document; the copy is the default**
  (`VerticalVersion.swift`, `VerticalVersion+Plan.swift`, `ProjectDocument+VerticalCopy.swift`,
  all new). The step is `VerticalVersion.plan` on a handle — its ops tried in one
  `SwitchAngle.Trial` — and FC9 calls the same step on its own short (FC-90). The copy is
  CJ5b's derived document handed the source's handle unchanged (`range: nil`: every media
  stays, every cache and analysis is carried); the step is applied there with one
  `performGroupedEdit`. The source never changes and gains no undo step. With `copy: false` the
  step is applied to the addressed project in place. **Owed to VR3b:** File ▸ Make Vertical
  Version…, its "Make a copy" checkbox (ticked by default, never remembered) and the sheet.
- **VR-31 — The copy opens with the step as its one undo step, "Make Vertical"** (FC-90's
  name; the owner's answer), named "<source name> (9:16)", "(4:5)" or "(1:1)" until saved
  (`derived(…, name: "<displayStem> (<shape>)")`). When the copy's handle is still the one it
  opened with after the grouped edit, the door closes the copy, removes the package at `path`
  when one was given, and throws "Make Vertical did not apply to the copy, so nothing was
  made."
- **VR-32 — Shapes and sizes** (`VerticalShape`): `9:16`, `4:5` and `1:1` (the owner's answer
  adds 4:5). w = min(W, H) rounded down to even; h = 2 × round(w × r / 2) with r = 16/9, 5/4
  or 1 — from 1920 × 1080: 1080 × 1920, 1080 × 1350 and 1080 × 1080. A size equal to the
  current canvas is refused ("the canvas is already W × H, so there is no <shape> version to
  make."). 4:5 is a size and nothing more: every rule here and in VR4 that reads "taller than
  wide" applies to it.
- **VR-33 — How each top-level clip is classed** (`VerticalVersion.classify`: the first match
  per top-level clip with a picture — not audio-only, not an adjustment clip — in id order, on
  the OLD snapshot; a nest's contents are never touched). Fill is `max(W/sw, H/sh)` over
  `snapshot.sourceSize(of:)`, clamped to `CanvasScaleSession.minScale…maxScale`
  (`edit_fit.rs`'s `fill_scale`).
  (1) **Backdrop**: named exactly "Blurred Background", with a partner on a track in front of
  it with an equal `source`, `start` and `duration`.
  (2) **Plate**: a `shape` rectangle whose width and height are within 0.5 px of the old
  canvas, x and y within 1e-6 of 0 and scale within 1e-6 of 1 (a shape plate); or an `image`
  or `still` named "Background" with x and y within 1e-6 of 0 and scale within 1e-6 × fill of
  the old fill (an image plate).
  (3) **Picture**: a `media` clip with a picture, a `still` or an `image` whose `canvasRect` at
  its first frame (base `VideoProps` with scale, x and y from `clip_state` at its start)
  covers one axis of the old canvas — both edges at or beyond the canvas's, at most 1 px
  inside — and on the other axis is centred within 2 % of that side or covers it too. A
  punch-in, or a clip Follow Subject framed at its 1.25 default, is a picture; a
  picture-in-picture, covering neither axis, is not.
  (4) **Nest**: a nest clip passing the same test.
  (5) VR4's full-frame graphics are class 6 until VR4 (VR-42).
  (6) **Other**: everything else.
- **VR-34 — The order of the step, and where it stops** (`VerticalVersion.opening`, `plan`).
  The draft's (3) and (4) are swapped, because a backdrop's fate reads its partner's result.
  Every op is tried on one `SwitchAngle.Trial`; the trial's ops and handle are the plan.
  (1) `set_canvas {width, height}` with no rescale and (2) `add_track {index: 0, name:
  "Backgrounds"}` (`opening`); a refusal answers "Make Vertical was refused at
  set_canvas|add_track: <reason>" and nothing is made.
  (3) In clip-id order, each picture, nest and other clip gets `reframe_clip {clip, follow,
  zoom, where_empty, from_width: W, from_height: H, backdrop: Backgrounds}` (W × H the old
  canvas): a media picture takes the settings' follow, with `where_empty` and `subjects` only
  for a following kind; a media picture whose media file is missing (no URL in `mediaURLs()`)
  under a following kind takes `keep` and is not followed, "its media file is missing, so it
  is kept as placed" (under `center` it is centred as any media picture); a still or image
  picture takes `center` and is not followed, "it is a still picture, so it is centred"; a
  nest takes `center`, "it is a nest, so it is centred"; an other clip takes `keep` and is
  kept. Only the op's answer decides an entry. **Applied:** a following kind or `center` on a
  media picture is **whole** only when the op added a "Blurred Background" clip to the trial
  (any track) AND `FollowSubject.framing` (k = s′/s, dx = x′ − k·x, dy = y′ − k·y from both
  handles' `clip_state`) agrees within 1e-6 at every sample time — the clip's start, its last
  tick, and each action's start and end in the new clip; otherwise **followed**, its reason "it
  is shown whole on a blurred copy where no subject is found" when a backdrop was added, then
  the clip's own motion ("moves by its own motion: <name>", the first active slot that is
  neither a fade nor a spin, during then in then out), joined by " and "; a clip centred by
  `where_empty: center` with no subject stays followed with no reason. **Identity:** treated
  as applied with no op. **Refused:** retried as `keep` and not followed, its reason the core's
  sentence; a refused `keep` stops the step: "Make Vertical was refused at reframe_clip for
  clip C: <reason>". Swift restates none of VR-26's refusals: a matte, rotated or spinning clip
  reaches `keep` through the core's sentence. The counts sum `FollowSubject.counts(…, replace:
  false)` over the entries whose applied op was not `keep`; a kept or not-followed entry counts
  0 (`keep`'s per-axis rescale is no framing). `more_tracks` is VR-29's sum.
  (4) Classes 1 and 2 in clip-id order: a backdrop whose partner was applied with a non-`keep`
  follow is deleted (`delete`, **removed**); any other backdrop, and every image plate, gets
  `set_video {x: 0, y: 0, scale: new fill}` (**refilled**); a shape plate gets `set_shape
  {width: W′, height: H′}` (**refilled**). A refusal answers "Make Vertical was refused at <op>
  for clip C: <reason>".
  (5) `remove_track` of Backgrounds when no clip is on it.
  (6) VR4's captions and graphics, owed to VR4.
  **Counts under compose** (VR-27 (f), `counts`' compose branch): an action in both handles
  with the same span is carried when F differs by more than 1e-6 between its two ends;
  re-eased is unchanged, and the replace branch Follow Subject reads is unchanged.
- **VR-35 — The summary** (`VerticalVersion.summary`): "Makes a W × H version." then, each only
  when non-zero, " Follows N clip[s]." " Shows N clip[s] whole on a blurred copy." " Keeps N
  clip[s] as placed." " Re-fills N background[s]." " Removes N blurred cop[y|ies] the framing
  replaces." then VR-29's sentences for Backgrounds, more tracks, re-eased and carried; then
  one line per entry with a reason: "Clip C is not followed: <reason>." or "Clip C is
  followed, but <reason>."
- **VR-36 — `make_vertical_version {shape, follow?, zoom?, where_empty?, copy?, path?}`**
  (`AgentServer+VerticalVersion.swift`, its row in `AgentCatalog+Framing.swift`; off main,
  never asking the person, reading no `UserDefaults`). `shape` is required (`9:16`, `4:5`,
  `1:1`); `follow` subject, face, person, salient or center (default subject; anything else
  "follow must be subject, face, person, salient or center, not <v>."); `zoom` default 1;
  `where_empty` fit or center (default fit); `copy` default true; `path` read only with
  `copy`. `captions` is VR4's. The first main hop refuses in this order: the target and each
  argument; an open nest ("make_vertical_version works on the top-level timeline: set_scope
  with no nest first."); `path` with `copy: false` ("make_vertical_version writes path only for
  a copy: drop path, or copy."); the path as `new_project_from_range` refuses it; a size equal
  to the canvas; `opening`'s refusal. It then runs a **dry plan** with no subjects, so a core
  error for a bad argument (`zoom` outside 1…4) is thrown at once, before any analysis is
  asked for. The answer: `ok`, `canvas {width, height}`, `cached`, `clips [{clip, treatment,
  reason?}]` in clip-id order (`followed`, `whole`, `kept`, `refilled`, `removed`,
  `not_followed`), `backgrounds`, `more_tracks`, `re_eased`, `moves_carried`, `summary`,
  `project`, and for a copy `carried {files, bytes, seconds}`, with `path` `saved` (the copy
  saved through `save_project`'s `save(_:to:operation:)`). It is ask-first for the assistant
  only when it names `path` (amends **AI-7** by one row, `askOnlyWith: "path"`, CJ-52's
  shape).
- **VR-37 — Analysis comes before the copy, in the source's cache.** For a following kind the
  requests are `FramingAnalysis.requests` over the media pictures whose media is present, on
  the SOURCE (so an offline media never throws `missingFile`); the wait is `reframe_clip`'s,
  lifted into `waitForAnalysis` with CJ-25's bound, and past it the answer is `analyzing`
  ("Still analyzing the media of N clip[s] (P %); call make_vertical_version again to make the
  version.") with nothing made. The subjects are read off main from the source's cache, so the
  copy carries copies of the analysis files and a later run on the source reuses them. The
  last hop refuses a changed project or scope ("the project changed while
  make_vertical_version read the analysis, so nothing was made. Call make_vertical_version
  again."). **Owed to VR3b:** the Analyzing sheet's Stop, which makes nothing.
  **Choices left to the code:** a picture's first-frame test reads `clip_state` at its start
  for scale, x and y; the dry plan's answer is discarded.

## CO8 — layout and cutout at record time (2026-11-03)

Recorded before the code. With "Record the camera too" ticked, the recorder panel chooses the
camera's layout (Corner, Rounded Corner, Circle, Side by Side, Camera Full) and whether the
camera's background is removed when it lands; `record_screen` takes `camera_layout` and
`camera_cutout`, and the dev tool `land_recording` lands a fixture camera with both. The owner's
answer (2026-11-01): the panel's default layout is Corner, today's landing. No core, FFI, header,
op, format or tool-count change (43 stands; 124 product tools); the cutout runs on-device, so
nothing is keyed (CJ-3).

- **CO-80 — The recorder offers a layout** (amends CAM-10 (3)).
  - (a) **One `switch_layout` per camera clip.** Right after segment k's camera clip is placed,
    the landing applies ONE `switch_layout {camera: the clip, screen: segment k's screen clip,
    layout, shape, corner: bottom_right, at: the clip's start, duration: one frame of the
    container's canvas, through}`. `through` is max(segment k's screen clip's end, the camera
    clip's end), per segment and never the whole recording's end, so the reach re-bases only a
    later screen clip this camera overruns into: never a later segment's own screen, nor a clip
    placed before the recording. The op is built by `ReelOp.switchLayout` unscoped, applied to
    the trial scoped as the commit is, and read back; a refusal throws "Clip N could not be laid
    out: <the core's sentence>". It sends no `curve`, `focus` or `nest`: no masks exist at
    landing, so the crop centres on the source (CO-70 needs them).
  - (b) **The one-frame switch.** The one-frame `duration` makes both roles cut at `at`. The
    camera is always cut at its clip time 0: its base and a one-frame layout action there. A
    screen whose clip time at `at` is 0 gets the same; a screen whose clip time is t > 0 (a
    positive `camera_offset`, or the floor after an overrunning camera) keeps its base and gets
    one one-frame layout action at t, so it stays full until the camera arrives. `corner_square`
    reproduces CAM-10 (3)'s geometry to the pixel (`layout.rs`'s corner is the same arithmetic).
  - (c) **The fallback.** When segment k's screen minted no clip, or its screen clip does not
    play at the camera clip's start (`screen.start ≤ at < screen end` fails), the camera takes
    CAM-10 (3)'s `cornerPatch` `set_video {x, y, scale}` whatever the layout, and the landing
    never throws for that reason: without it the core would pick another clip as the screen,
    or refuse.
  - (d) **A recorded limit.** An Auto Zoom visit that starts in a screen clip's first frame, or
    at a screen's mid-clip layout action, meets that one-frame action and is dropped and counted
    (CU-75).
- **CO-81 — The cutout follows the landing as its own undo step "Remove Background"**
  (AU-68's pattern, with no wait). `RecordingCutout.cameraClips` is every clip of the open
  container whose media path is one of the segments' camera paths, that `CutoutStatus.canCutOut`
  and has `video.cutout == nil`, in id order; `ops` is one base `set_video {cutout:
  CutoutProps()}` per clip; `apply` commits them through `performGroupedEdit` right after the
  landing — both branches of the panel and the tool door — before Enhance Voice and the polish
  (CU-101 (a)), so the order is the landing, Remove Background, Enhance Voice, then the polish.
  It is never inside the landing's step. With no camera clip the panel is quiet and the tool
  answers `camera_cutout_error` = "No camera clip landed on the timeline, so Remove Background
  did not run."; otherwise the answer gains `camera_cutout: {clips: [id…]}`. Not key-gated: it
  runs on-device (CJ-3).
- **CO-82 — The panel's rows and keys** (amends CAM-11). Two rows after the camera's preview
  and before Microphone: "Layout:" with a pop-up of the five (`RecordingCameraLayout`, each
  item's `representedObject` its raw value, read from `selectedItem`), and under it, unlabelled,
  "Remove the camera's background when it lands". Both are live only while idle with
  `cameraBesideSelected`; otherwise greyed with their values kept. `applyCameraLanding`: the
  layout is the pop-up's with `cameraBesideSelected`, else `.cornerSquare`; the cutout is the
  box's value and `cameraBesideSelected`. The keys `FrameJobRecordingCameraLayout` (a String;
  absent or stale reads `corner_square`, the owner's Corner) and `FrameJobRecordingCameraCutout`
  (a Bool, absence tested by `object(forKey:) == nil`, reads off) are the panel's seventeenth and
  eighteenth, written on every change and restored on show, and pinned at those values in the
  harness and `screens.py`.
- **CO-83 — The tools' arguments** (amends CAM-4 (2), (3) and CAM-10 (5)).
  - (a) **`recordingCameraStrangers`.** With source voice_over, the given ones of `camera,
    camera_format, camera_layout, camera_cutout` in its one sentence; with source screen and no
    `camera`, the first given one of `camera_format, camera_layout, camera_cutout`, as "With
    source screen, <arg> needs camera — name the camera to record beside the screen."; with
    source camera, both new arguments join `cameraRefusedArguments`, before `rate`.
  - (b) **`recordingCameraLanding`** runs after `recordingPolish` and before any grant: the enum
    first (`enumArg` refuses an unknown value with the vocabulary), then with `place: false`
    "camera_layout lays out the landed camera clips, so it needs place: true." when the layout
    is given and "camera_cutout: true removes the landed camera clips' background, so it needs
    place: true." when the cutout is true. The tool's defaults are `corner_square` and false,
    because a tool reads no `UserDefaults`.
  - (c) **`land_recording`** takes `camera` (a path, only with `movie`: "camera cannot be given
    without movie — a camera lands beside the screen segment's movie."), and `camera_offset`
    (integer ticks, default 0), `camera_layout` and `camera_cutout`, each only with `camera`:
    "<arg> cannot be given without camera — it applies to the camera's clips.". The fixture
    camera is probed as the others are, the segment built with `cameraDescriptor` and
    `cameraOffset`, `choice.camera` the fixed id "land_recording", and the place checks are
    `recordingCameraLanding`'s. Its panel door builds its own choice, so the two panel keys
    never reach it (CU-102 (c)'s rule).
- **CO-84 — CO8's proof.** `co8_proof.py` (MCP, both doors of `land_recording`, ffmpeg fixtures
  under `tools/proof/work/co8/`): R1 the default landing (the camera at CAM-10 (3)'s arithmetic,
  the screen an `add_clip` twin's, one one-frame layout action at clip time 0 each); R1b a +2
  frame `camera_offset`; R2 the five layouts against a twin given `switch_layout` by hand; R3
  the cutout as a second step "Remove Background" on the camera clips only; R4 every CO-83
  sentence through `record_screen` and `land_recording`, the project unchanged; R6 a clip placed
  before the recording left byte-identical; R7 `fit_new_clips` off; Z0 the parity log clean;
  app mutants `cutout-in-landing` (R3), `default-rounded` (R1), `no-frame-duration` (R1b).
  `co8_probe.py` (built through `swift_build.build()`): Q1 the rows, Q2 the keys, Q3 the gates
  and `currentChoice`, Q4 the refusals, Q5 a write run then a read run, Q6 two segments with the
  second camera absent, Q7 a +3 frame offset and an overrun screen's fallback; probe mutants
  `gate-ignored` (Q3), `cutout-without-camera` (Q4), `through-whole-recording` (Q6),
  `throw-on-unplayed-screen` (Q7) and `no-through` (Q6). No JOB row: the landing is measured.
