# Spec §11 — decisions: Deepening, a folder at an import door onward (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The entries continue [`deepening.md`](deepening.md), so a citation never has to say which file. This
file holds #497, #524, #534, #523, #521, #526, #532, #527, #531, #525, #535, #536 and #395, and a
new decision of this kind is appended here. It is new because `deepening.md` had passed the spec's
~500-line split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below"
in one may now point into a sibling file.

- **#497 — a folder at an import door imports the media files directly
  inside it.** A folder dropped on the Media tab, alone or among files, and
  a folder given to `import_media` are replaced by the media files directly
  inside them, one level down, sorted by `localizedStandardCompare` on the
  name, as the Finder sorts (`Clip 2.mov` before `Clip 10.mov`). A link to a
  folder counts as the folder; a package (a `.framejob`, an `.rtfd`) is not a
  folder, and a package dropped on its own is probed as it always was. Media
  is what an import door can read: a `.cube` by its extension
  (`MediaImporter.isLUT`), a type conforming to `public.audiovisual-content`,
  a still of `MediaImporter.imageTypes`, or a file beginning with an EBML
  header (`ContainerRewrap.isMatroska`, so a Matroska file with no extension
  counts); a `.psd`, an `.svg` and a `.txt` do not. Hidden files are left out
  and never named. Subfolders, packages and files that are not media are
  skipped with no alert, and `import_media` names each in its `skipped`
  (`a folder`, `a package`, `not a media file`). The drop's files are probed
  in place, in the drop's order, and commit as the drop's one undo step
  ("Add 2 Media Files"). A media file that will not read still shows its
  alert on the drop, and on the tool it is a `skipped` reason in the probe's
  own sentence. A file already in the media list is skipped by the tool as
  `already in the media list`; on the drop the core's `add_media` keeps the
  one entry, as for a dropped file, and the undo step's name still counts
  it. A folder that yields nothing adds nothing and says nothing on
  the drop; the tool refuses, `Nothing in Shoot was added: it has no files
  directly inside it.` or `Nothing in Shoot was added. Skipped: readme.txt
  (not a media file).` A folder whose items cannot be listed is not one
  that yields nothing: the tool refuses `Nothing in Shoot was added: it
  could not be read.`, and the drop shows the same sentence as an alert,
  before probing, and still adds the rest of what was dropped; this
  replaces "says nothing" for that case only. `import_media` on a folder
  answers `{folder, imported, skipped, note, project}`, `imported` in
  Finder order with each file's probe as a file's answer gives it; a file
  keeps its answer. **Out:**
  recursion past one level, and any folder handling at Add Media… (whose
  panel chooses no folder), File ▸ Open, the window or Dock drop, Add
  Background, `relink_media` and `open_project`. **Risks accepted:** for a
  drop, the listing and its header sniff run on the main thread; a tool call
  on a large folder waits `probeCeiling` per file.
- **#524 — `set_video` refuses crop, corner radius and chroma key on a
  text, shape or graphic clip, and Paste Attributes leaves such a clip's
  own** (the owner, 2026-11-06, "Refuse and skip"). These kinds have no Crop,
  Corner Radius or Chroma Key section, so a value written there had no field
  to show it and no Reset. The rule reads the PATCH, as AU-111 reads
  `duck.mode`: a key fires only when the patch names it and the merged value
  is not neutral (a crop other than all zero, a radius other than 0, a
  chroma key other than `null`). So clearing is always allowed, and a value a
  clip already holds (a full `paste` keeps what its payload holds) is kept by
  every other edit and cleared by a neutral one. `crop` is taken on a matte
  track, because there crop shapes the matte (K-7, MT-4). The answer is an
  `Err`, the tier of `check_blend` and CO-20's kind refusals, in one of three
  sentences: `clip {id} is a text clip and cannot take a crop off a matte
  track`, `… cannot take a corner radius`, `… cannot take a chroma key`
  (`a shape clip`, `a graphic clip` likewise). Paste Attributes copies the
  video group onto such a target and keeps the target's own crop, corner
  radius and chroma key, beside the qualifier rule (GR-13); onto any other
  clip the three travel as before. `switch_layout`, and every replay through
  its composition (`reframe_clip {follow: layout}`, Make Vertical Version),
  refuses up front, before any write and as a refusal, when a shape or
  graphic clip under `at` or in the reach would be given a non-zero radius or
  a crop off a matte track: `clip {id} is a shape clip and cannot take a
  camera layout's crop or corner radius`. One rule covers the base
  `set_video` and the layout action's end, so the answer does not depend on
  where `at` falls in the clip. This amends CO-64's refusal order: after the
  movers, before `add_action`'s own. A text clip has no source size, so it is
  never a layout role (CO-64). `paste` is unchanged; `set_action_end`
  refuses the same keys (amended by #535), and an adjustment clip joins
  these kinds (amended by #536).
- **#534 — A media path is stored and compared as given, never trimmed.**
  `add_media`'s `path`, every `original.path` (#228-O), `relink_media`'s
  `path` and a pasted media row's `path` are kept byte for byte, and the
  check for a file already in the media list compares them that way. A blank
  path, or one of only spaces, is still `media path must not be empty`.
  Trimming stored a file whose name ends in a space (`A.mov `, or a WebM
  `talk.webm ` that the built-in copy takes with no question) under its
  sibling's path: the import of the converted copy recorded the sibling as
  its original, and a raw `add_media` of the spaced name answered for the
  sibling's row. A bookmark's blank check is unchanged.
- **#523 — a timeline whose last stretch holds only generated clips gets a
  composition as long as its plan.** Text, shape, graphic and image clips
  need no decoding, so §7.2 gives them no composition track; with a movie to
  10 s and titles to 20 s the composition ended at 10 s, and `AVPlayer`
  clamped every seek past it — the asked seek, `play_preview`'s `seek_to`,
  the restore after an edit — and the item ended there: the playhead went
  back to 10 s and the titles never played. `addPlaceholderIfNeeded` now
  runs after the audio tracks are filled, and gives the composition its
  one-frame `Blank.mp4` track, scaled across `plan.duration`, when the plan
  has a duration and either has no video track (as before) or its
  composition, audio and #336's silence included, ends a tick or more short
  of the plan (compared as `CMTime` against the plan's duration less one
  tick, never subtracted). A composition within a tick of its plan builds as
  before and is left to `+InstructionRanges`' sub-tick correction. The
  placeholder's id is one past every plan id, video and audio
  (`placeholderTrackID`), so it can sit beside media tracks; a plan with no
  video track keeps its old id, one past the audio ids. The placeholder is
  never one of `videoTracks`, so `convertsSources` and every recipe see the
  plan's tracks only. It applies to the builder's every caller alike — the
  preview's item, both export passes and the offline frame — so an export
  of such a timeline runs to its end too. A missing `Blank.mp4` still
  leaves the composition as it was, never a crash.
- **#521 — The Transcript tab's overlap sentence names an overlap, not a
  transition** (the owner, 2026-11-06, "Reword"). A word TX-11 holds back
  for meeting a `SilenceDetector.overlapWalls(snapshot)` wall reads "Near an
  overlap between two clips: a cut here would leave one clip's tail under
  the other." The rule is unchanged: `overlapWalls` is any overlap on an
  unlocked track, with or without a transition, widened by its own length
  each side, so a word up to one overlap length outside it is held back too.
  The old sentence ("Under a transition: …") showed by an overlap with no
  transition and on words outside the overlap. Amends TX-11's quoted
  sentence.
- **#526 — The app's own strings spell color and center the American way**
  (the owner, 2026-11-06, "American", matching the Color tab, Key Color,
  Normalize and macOS). Every string a person reads (a label, tooltip,
  note, readout, hint or plan note) or a caller reads (a tool's, argument's
  or declaration's text, an app or core refusal or error sentence) spells
  color, colors, colored, center, centers and centered. Identifiers, JSON
  keys and values (`ScopeTraces`' `"centre"`), FFI names
  (`rc_normalise_color`), cache keys, Matroska element names and code
  comments keep theirs. The documentation's prose stays British; a quoted
  label, and an alt text quoting one, follows the app. Amends GR-13's
  caption ("Center"), GR-38's tip and its "Centre stays", HD-13 (k)'s
  "Color row", VR-34's two notes, and G-12's and CU-30's quoted sentences.
  **Extended by #538** (the owner, 2026-11-07, "#538 follows #526's
  American"): the same strings spell analyze, analyzed, analyzing and
  analyzes (the verb; the noun 'analyses' is already right),
  normalize(d/s), recognize(d), recognizer, neighbor(s), gray(s), labeled,
  summarize and standardized, the graphics library's `interpolateColors`
  error included. 'cancelled', 'Cancelled.' and 'Cancelling…' stay in
  prose. American English accepts that spelling, and it is the status value
  a caller reads beside the sentence (`export_status`'s and
  `analysis_job`'s `cancelled`, with the reason 'Cancelled.'), so the word
  reads one way. 'judgement', also accepted, stays. JSON keys (`leveller`),
  identifiers and comments keep their spelling. Amends the quoted strings
  of AU-14, SY-11, SY-17, SY-31, SY-34, SY-38, SW-24, SW-84, VR-63, TX-18
  and G-12.
  **Extended by #541** (the owner, 2026-11-10): the same strings spell
  Leveler, leveler and leveling: the Sound tab's section and its rows'
  names, its Status "Not leveling: <reason>", Enhance Voice's "Leveler: …"
  reasons, the export's `loudnessUnmeasured` sentence and the tools' prose.
  The key `leveller` and its paths (`audio.leveller.target_db`), the
  section id `audio.leveller` and its launch default
  `-FrameJobInspectorSection.audio.leveller`, `LevellerProps` and every
  other identifier, file name and comment keep theirs. On the documentation
  site the Leveler's own words (leveler, leveling, leveled) follow the app
  in prose too, so that no page spells the feature two ways, and its page
  is `audio/leveler`; the rest of the site's prose stays British. Amends
  the quoted strings of AU-66 and AU-67, and §4.3's and §7.8's quotations
  of them.
- **#532 — A frames timecode counts real seconds at a fractional rate that
  is not NTSC.** At an NTSC rate (`Fps::counts_nominal_seconds`: the rate's
  denominator over the gcd of its numerator and denominator is 1001, so
  `[60000, 2002]` is `[30000, 1001]`) `HH:MM:SS:FF` stays non-drop, a second
  of `ceil(num/den)` frames, and drifts from the clock as §7.3b says. At
  every other rate SS is the whole second the frame starts in,
  `floor(index·den/num)`, and FF counts frames since that second's first
  frame, `index − ceil(SS·num/den)`. So at 12.5 fps a second holds 13 frames
  then 12, 500 frames read `00:00:40:00`, and a whole rate reads as before.
  `parse_timecode` inverts it. It moves every reading at such a rate: the
  toolbar, the export sheet's readout, a burn-in, a layout name and an image
  sequence's or Save Frame's name. The milliseconds form is unchanged.
- **#527 — Make Vertical's Follow Speaker reads a microphone with no
  speech under a shot as that person not talking there** (the owner,
  2026-11-06, "Silent mic, Face if none"). `withTurns` reads each speaker
  clip's turns through `FramingSpeaker.turns(…, silence: .notTalking)`:
  SW-24's no-speech sentence (`SpeakerSwitch.silentMicrophones`) no longer
  refuses, the silent microphone gets no turn and stays in the clip's `mics`
  with its `mic_faces` entry, so VR-61 (e)'s segments frame whoever else
  talks. `read`'s problems (a microphone still being analysed, speech
  detection unavailable) and an unreadable plan still refuse the tool,
  "make_vertical_version was refused: …", and still show on the sheet. A
  shot none of whose microphones has a turn is handed `turns: []`; the core
  refuses it "clip C has no turn of its microphones inside it, so there is
  no speaker to follow" (VR-60 (d)) and VR-64 (c)'s retry frames it `face`,
  its entry `followed` with "it follows its faces, not who is talking,
  because " + that sentence. With no `mic_faces`, a silent microphone's
  agreement is 0, so the match is not `sure`: the tool's shot follows its
  faces with the weak match's sentence, and the sheet leaves its pop-ups on
  "Choose a face" with its not-sure note. `reframe_clip {follow: speaker}`
  is unchanged (`silence: .refuses`, VR-60 (c)). Amends VR-64 (d) and
  VR-66 (c).
- **#531 — An export is written beside its destination and renamed over it
  only when it succeeds** (the owner, 2026-11-06, "Write aside, swap").
  Amends #470 and AU-108 (f) as #470 amended it. Every export, through the
  Export… sheet, the Export Queue or `export`, is written to a hidden sibling
  `.framejob-export-<UUID>.<ext>` in the destination's folder
  (`ExportAside.temporary`), whether or not a file is at the path.
  `Exporter.startWriting` makes the name and hands it to `Exporter.pipeline`
  as `writing`. The writer, the WebM writer and the image writer write it, and
  `encoderOutcome` cleans it. Only `finish` touches the path. When
  `graphicOutcome` leaves a success, it renames the sibling over the path with
  `rename(2)` (`ExportAside.swap`) and answers the path, never the sibling. Any
  other end — a refusal, a failure, a cancel at any stage, a failed graphic
  (G-13) or #378's dev fault — removes the sibling and leaves the path as it
  was. An existing file stays byte for byte, and a partly written file is never
  at the path. A rename that fails is a failure,
  `“<name>” could not be replaced with the new export: <strerror>. The file
  there is as it was.`, and the sibling is removed. **Stems** are written the
  same way: the mix at its sibling, each stem at its own. When every write has
  succeeded, each stem is renamed over its path in order, before the mix. A
  stem rename that fails removes the siblings not yet renamed and fails with
  its sentence; stems already renamed stay renamed. A mix rename that
  fails after every stem is renamed (`Exporter.finish`) leaves the new stems
  in place beside the old mix. The stem collision
  (AU-108 (d)) still refuses before anything is written. **The queue**: a
  completed row naming the same path is marked `superseded` when a later job
  SUCCEEDS, not when it launches, because until then the earlier file is
  still there. The cancel's removal of the path in both `finished` methods is
  gone, because nothing an export writes is ever at the path before it
  succeeds. **Accepted:** the folder needs room for both files until the
  export finishes. A crash or a forced quit during the write leaves a hidden
  `.framejob-export-*` partial beside the path; nothing removes it at launch.
  Leftover `.framejob-replaced-*` files from #470 are not touched.
- **#525 — An Objective-C exception inside a tool call fails that call, not
  the app.** An `NSException` raised by a tool's handler crossed Rust's
  `catch_unwind` in `agent::serve` (off main, where Rust aborts on a foreign
  exception) or AppKit's uncaught-exception handler (inside
  `onMainWhenIdle`'s `DispatchQueue.main.sync`), and both ended the process.
  The catch is Objective-C: `app/Bridging/FrameJobObjCCatch.h`'s
  `static inline` `framejob_catch_objc` runs a block inside `@try`, and
  `ObjCException.catching` is Swift's door to it. It sits in four places in
  `AgentLane.swift`: around `execute` on the server thread and in the main
  fallback (`executeCatching`), around `onMainWhenIdle`'s body on main (an
  exception caught there is raised again on the calling thread, where
  `executeCatching` answers it), around `submit`'s `answer`, and around
  `answer`'s question hop. The call answers `isError` with `<tool> failed on
  an internal exception (<name>: <reason>). Frame Job is still running, but
  part of the call may have happened.`, and the log has `framejob agent:
  <tool> raised <name>: <reason>`. Every catch sits inside the lane lock's
  `defer`, so the lock is always released. **Accepted:** a raise skips the
  `defer`s and releases of the Swift frames between it and the catch, so a
  handler's own lock or half-made state is not restored. A raise on a queue a
  handler starts itself still ends the app.
- **#535 — `set_action_end` refuses crop, corner radius and chroma key on a
  clip `set_video` refuses them on** (the owner, 2026-11-06, #524's "Refuse
  and skip", which 2026-11-07's answer to #536 extends to an action's end).
  The kinds, the sentences, the matte rule and the patch-read rule are #524's
  as #536 amends them, judged on the end the op would store: a key fires
  when the op's `patch.video` names it (any value, `null` included) and the
  merged, pruned end's value is not neutral (a crop with a side other than
  0, a radius other than 0, a chroma key present and not `null`). So
  removing a key (`null`), animating it to neutral, `off`, and `video: null`
  stay allowed. The answer is an `Err`, as #524's. A crop at the end of an
  action on a matte track's text, shape or graphic clip stays allowed: K-7's
  crop handles write the end there with an action selected. An end already
  in a file, or brought by a full `paste`, is kept by every other end edit.
  `switch_layout` never reaches it: #524 refuses a shape or graphic role up
  front, a text clip is never a role, and an adjustment clip has no source
  size and is never a role (CO-64), and it writes a nest role's radius as 0
  (#536).
- **#536 — An adjustment clip takes no crop, corner radius or chroma key**
  (the owner, 2026-11-07, "Refuse and skip, as #524"). It has no Crop,
  Corner Radius or Chroma Key section, and on the base app none of the three
  drew on it. `set_video` and `set_action_end` (#535) refuse them in #524's
  sentences with `an adjustment clip` as the kind, and clearing stays
  allowed; Paste Attributes leaves the target's own. There is no matte
  exception: on a matte track an adjustment clip is inert (GR-6), so a crop
  there is refused too, `clip {id} is an adjustment clip and cannot take a
  crop`. Amends GR-6's "kept and do nothing" for these three; one already
  stored in a file is kept and does nothing. **A nest clip takes a crop but
  no corner radius or chroma key** (the owner, 2026-11-07, round 3: "Refuse
  corner radius and chroma key; keep the crop", as K-7 keeps a matte
  track's crop). Before #536 a crop drew on a nest and neither of the
  other two did, and a nest has no Corner Radius or Chroma Key section.
  `set_video` and `set_action_end` refuse the two in #524's sentences with
  `a nest clip` as the kind, `clip {id} is a nest clip and cannot take a
  corner radius` and `clip {id} is a nest clip and cannot take a chroma
  key`, on any track, matte or not; clearing stays allowed and the crop is
  taken. Paste Attributes leaves a nest target's own radius and chroma key
  and gives it the crop. A camera layout writes a nest role's radius as 0
  (amends CO-60, CO-62 and VR-53 (b)), so a switch never trips the
  refusal. A radius or chroma key already stored on a nest in a file, or
  brought by a full `paste`, is kept and does nothing.
- **#395 — `export_status`'s `done` answer carries `message`, the Export
  Queue row's sentence.** (Amends #326.) Every other state already answered
  the row's sentence (`waiting` while held, `reason` when failed or
  cancelled); `done` answered only what the file holds, so nothing over MCP
  could read the success line ("Exported “Mix.wav” and 2 stems. …", AU-108
  (f)) and `audio_ap10b_proof.py`'s S1 could not hold its stem count against
  the result's `stems`. `AgentExports.status` now adds `message` on `done`:
  the string the row holds, copied at the finish inside the queue's own
  change notification as the rest of the record is (`AgentExportRecord.message`),
  so it is the sentence a person reads, with its warning suffixes and its
  loudness figures. It is present on every finished export, since the queue
  writes the sentence in the step that completes the job.
  `AgentServer.exportResult` is untouched: its keys stay the ones `export`
  answered before #326. `snapshot_ui` of the Export Queue window was the
  other way to read the row and is not built: it needs the window shown,
  which an agent export never does. Proofs: `audio_ap10b_proof.py` S1 (two
  stems) and S6 (one, the singular), `export_status_proof.py` A2 (no stems).
