# Spec §11 — decisions: Deepening, an agent's export as a queued job onward (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The entries continue [`deepening.md`](deepening.md), so a citation never has to say which file. This
file holds #326, #336, #355, #337, #335, #367, #378, #465, #472, #470, #504 and #477. #497 on are in
[`deepening-5.md`](deepening-5.md). It is new because `deepening.md` had passed the spec's ~500-line
split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below" in one
may now point into a sibling file.

- **#326 — An agent's `export` is a job in the Export Queue and answers at
  once; `export_status` follows it and `cancel_export` stops it.** (Amends
  AI-16.) Every refusal `export` had stays synchronous — the arguments, the
  core's settings, the folder — and so does the graphics gate
  (`Exporter.graphicsRefusal`, its "The export was not started: …"), run in
  the handler before anything is queued, so a call that could only fail
  enqueues nothing. Then the handler pauses the editor's playback and
  enqueues in `ExportQueueController.shared` exactly as Add to Queue does
  (the queue captures the media URLs, the reverse resolution and the
  graphics itself), and answers `{export_id, path, status}`, nothing else.
  The status words are the queue's states in the agent's spelling:
  `queued` (waiting), `running`, `done` (completed), `failed`,
  `cancelled`. `export_status {export_id}` never waits: it answers
  `export_id`, `status`, `path` and `elapsed` (seconds, three decimals,
  from the `export` handler's entry to now, or to the finish); `running`
  adds `progress` and the exporter's `phase` when it has one; `done` adds
  every key `export` answered before this (the settings used, `bytes` read
  at the finish, `burn_in_timecode`, `dynamic_range`, `loudness`,
  `graphic_warnings`); `failed` and `cancelled` add `reason`, the queue
  row's sentence. `cancel_export {export_id}` is the row's Cancel
  (`ExportQueueController.cancel`) for a queued or running job, answered as
  `export_status` answers then, and leaves a finished one alone. **The
  records live in memory for the launch** (`AgentExports`,
  `AgentServer+ExportStatus.swift`), for ids `export` returned only — a
  person's own queued job is not reachable — and are copied from the queue
  inside its own change notification, synchronously on main, so a record
  outlives the row's Remove and Clear Finished; a record holds no project
  handle or graphic set. The Export Queue window is not opened for an agent
  export. The queue runs one job at a time, so an agent export waits
  behind a person's (`queued`), and the queue's quit question now covers an
  agent's export as it does a person's. Stop no longer reaches an export
  (AI-16 as amended): the call has already answered; a queued or running
  export stops by `cancel_export` or the Export Queue's Cancel. **Risk
  accepted:** an agent that never asks never learns the outcome, and the
  assistant cannot sleep between polls, so it asks again when its turn
  allows. `tools/proof/export_status_proof.py` (A1–A8, Z1) is the proof;
  every proof that expected the file on return follows the job through
  `MCP.export_with` in `tools/proof/mcp.py`, which returns an older build's
  blocking answer as it is.
  **Amended by CX-18** (codec-export C6a): `queued` adds `waiting`, the
  held job's "Waiting for memory: …" sentence, while the memory limit holds
  an `av1`, `av1_webm` or `vp9_webm` job, and `queued` and `running` add
  `estimated_seconds` on those rows; `export`'s answer is unchanged.
  **Amended by #486** (docs bugs b3): a call that could only fail still
  reached the queue when the rule lived in a writer, so `export` asks
  `Exporter.settingsRefusal` directly after the graphics gate and before
  `enqueue`. The 600-frame limit and G-33's same-shape rule now refuse at
  the call, in their own sentences, with no `export_id` (#470). The order
  is arguments, core settings, folder, graphics gate, then this.
  **Amended by #395** (hygiene a1): `done` also adds `message`, the queue
  row's sentence.
- **#336 — A composition audio track none of whose segments has a source
  (missing media, a pending reverse, a pending ramp render) holds bundled
  silence over [0, its last segment's end).** Measured at bb73b35
  (`tools/proof/missing_audio_proof.py --baseline`): with one audio track
  whose only clip's media file is missing, or whose reverse is pending, and
  no other track that sounds, both `audio_wav` and `prores_422` failed with
  "export: The operation could not be completed" (M1, M2, R1, R2), as did a
  missing `AV.mov` alone (V0); beside a track that sounds, both exports
  finished and matched that track alone (M3, M4, R3, R4). A composition
  audio track of nothing but empty edits is what the writer could not read.
  The silence is `app/Resources/Silence.caf`, 10 s of ALAC zeros at 48 kHz
  in two channels (spec §11 SY-23: an empty edit before a non-48 kHz segment
  is rate-converted wrongly, so the silence is 48 kHz), inserted back to back
  from 0 (`CompositionBuilder.fillSilence`, `CompositionBuilder+Silence.swift`)
  and never scaled, the last copy cut at the end. The track's id, its input
  parameters, its envelope, its onset (still nil, so no hold), its meter and
  its `sounding` spans (still empty, so the meter counts nothing there) are
  unchanged; only the empty edits become silent media. Every track with a
  resolved segment builds byte for byte as before. Where the resource is
  absent (the probes and the harness, which bundle no app resources), or its
  extent is not numeric or floors to 0 ticks, the track keeps its empty
  edits, as today. It applies to the preview and every export alike, through
  `addAudioTracks`. **Risk accepted:** one edit per 10 s of such a track;
  and the length is scored against the same project with its media present
  (control C), not the timeline (owner, 2026-10-24): every composition whose
  picture is the Blank placeholder exports one frame short of its timeline —
  814,400 frames for a 17 s timeline at 30 fps, the same in C and T before
  and after this change, and none short for a missing `AV.mov`, which has a
  video track — a shortfall beside #337. *Amended by #337:* the shortfall
  is the timeline's own. toneB.m4a is 2,986,400 ticks, and `add_clip`
  snaps it down to whole frames, so C's timeline is 10,180,000 ticks
  (16.967 s), not 17 s. Its exports are exactly 814,400 frames, which is
  that timeline, and its composition and audio track end there too.
- **#355 — The Audio inspector's Fade in, Fade out and Ducking Attack and
  Release write the typed length off the frame grid, as `set_audio` stores
  it (core/CLAUDE.md Times); dragging a fade handle on the timeline still
  snaps the length to whole frames, a deliberate gesture exception (owner,
  2026-10-25).** The four rows each snapped the seconds typed to the
  canvas's frame grid before the op was built (`AudioPane`'s two local
  `ticks`), so at 30 fps a 10 ms attack was written as 0 and a 0.26 s fade
  as 0.2667 s; the same `set_audio` from an agent is stored as sent,
  because the core's Times rule keeps the audio ramps — the fades, the
  duck's and the compressor's attack and release — off the grid on
  purpose: they are envelope lengths sampled at the audio rate, not
  positions in the picture. The rows now convert seconds to ticks with no
  snap (`AudioPane.rampTicks`), as the Compressor's millisecond rows
  already did. Three reasons: the core's rule; agent parity, one length
  stored for one length asked, whichever side asks; and the compressor
  rows, the same family, already unsnapped. The fade handle's drag
  (`FadeHandleSession`) keeps its snap, because a drag lands on whatever
  pixel the pointer reaches and a whole frame is what a person can see.
  The inspector's other seconds→ticks copies that do snap — Motion's In
  and Out Duration and Period, the transition's Duration, Reveal's In and
  Out, the action lane's duration field — become one
  `InspectorBinding.frameTicks(seconds:)`, which changes nothing stored:
  its only addition, a negative read as 0, is below every one of those
  fields' minimums.
  `tools/proof/audio_ramp_grid_proof.py` (A1–A5, G1–G3) is the proof;
  `--baseline` shows A1–A4 snapped on the old tree. **Risk accepted:** a
  field shows 2 decimals, so 10 ms is the smallest length a person can
  type, and a stored 0.083 s reads 0.08; a later handle drag re-snaps a
  typed length.
- **#337 — Every export's audio is exactly round(range × 48 000) frames, cut
  at the range's end and padded with silence after a read that ends early.**
  `ExportAudioEnd` counts the frames `ExportWriter`'s audio pump hands on,
  in order and never from their stamps. The target is ⌊(ticks · 48 000 +
  300 000) / 600 000⌋ of the range's ticks, round half up in integers. A
  buffer that ends at or before the target goes on unchanged. The one that
  crosses it keeps its first (target − written) frames
  (`CMSampleBufferCopySampleBufferForRange`). Every buffer after that is
  read and dropped, so the reader never stalls the video output, and the
  input is never marked finished early. When the audio output runs dry
  with the reader not failed and the write not stopping (the dry branch's
  own test, never `.completed`, which stays `.reading` while the video is
  still composed), zero buffers in `ExportWriter.decodedAudioSettings`'
  shape (48 kHz, two channels, 16-bit) are appended up to the target, each
  only while the input has room. The loudness measurement feeds the meter
  only the target's frames. Measured at HEAD 3f7c948
  (`tools/proof/retimed_audio_proof.py`, A1): CX2 (×2, Keep pitch off, a
  4 s timeline of 192,000 frames) wrote 192,047 frames in both runs of
  `audio_wav` and `prores_422`. CK05 (×0.5, Keep pitch on) wrote 190,787 and
  190,851 in `audio_wav` and 190,787 twice in `prores_422`. The writer passed
  on whatever the reader handed it: the mix read alone, with no writer,
  gave the same lengths (A3). An export whose read already ended exactly on
  the target is byte-identical to before. CX1 (×1) and C read exactly to
  their targets at HEAD (A3), so spec §7.8's "byte-identical by
  construction" still holds for such exports. The pad's shape is the one both arms
  already write: the 16-bit decode, and `ExportAudioGain`'s output. A file
  readers decode to more frames than were handed in (AAC's priming and
  remainder) is the encoder's own and outside this rule. **Risk accepted:**
  a Keep pitch on read that ends short is made up with silence at the end,
  up to ≈ 25 ms in CK05, rather than with the sound Apple's time-pitch
  did not deliver. The ×2 overrun is dropped rather than kept. After the
  change all 8 of A1's streams were 192,000 frames, and CK05's two runs per
  preset were PCM-identical.
- **#335 — The ×1 playback tap's early reading is the PostEffects tap's
  stamp on a track with no time-scaled segment. Preview audio is in sync
  with the export, and no product code changes.** Measured with
  `tools/proof/retimed_audio_proof.py`, 3 runs of each read, on this
  change's Debug build and again on its Release build, with the same
  readings. C1: on T335 (one track, A ×1 over [0, 3 s), B ×2
  over [3 s, 6 s), Keep pitch off, clicks), the PostEffects tap placed A at
  −0.979 ms by its stamps and −0.979 ms by order. By order means every frame
  counted from the first chunk stamped inside B. The tap placed B at
  −0.010 ms both ways. The `audio_wav` export placed A at −0.958 ms and B at
  +0.010 ms. C1 also reads CX1, a track holding a ×1 clip alone (SR1's
  `C-off-x1` shape, where #335 was read): the PostEffects tap read
  −85.333 ms by SR2b's coarse method in all 3 runs, reported. That is
  exactly one 4,096-frame tap buffer, past the 60 ms placement reach. The
  PreEffects tap, which is the product `AudioTap`'s flag, read +0.000 ms
  (20/20) by stamps and by the coarse method in all 3 runs, as did the
  export, and C1 scores it within 1.0 ms of the export. So the same
  samples carry different stamps at the two taps. The per-clip DSP spans
  `AudioTap.process` places from its PreEffects stamps land where the
  export puts them. SR1's −21.000 ms and SR2b's −86.333 ms were this stamp.
  `ramp_proof.py` P1's self-correction by m1 (SR-17) stands. C1's scored
  CX1 row and its mutant replace "unexplained": `--mutant stamp-place`
  scores CX1's PostEffects stamps as the product's, and C1 fails (none
  within the 60 ms reach, −85.333 ms coarse, 3 of 3 runs). On T335 the
  stamps were not early in any run, so its A row cannot tell the two taps
  apart. **Risk accepted:** an instrument that reads a
  ×1-only track through a PostEffects tap must correct by a measured
  control, as P1 does, and not trust the stamp.
- **#367 — A media cache pass's three audio decodes (`writePeaks`,
  `writeSyncFeatures`, `writeSpeech`) run on a lane of their own
  (`MediaImporter.CacheLane`): at most two at a time, FIFO, on the lane's
  own concurrent `.utility` GCD queue and never on the Swift cooperative
  pool. No synchronous `AVAssetReader` read may run on the cooperative
  pool.** The cause, measured on a Mac14,6 with 12 cores, where the
  cooperative pool is 12 threads: twenty imports of 250 s files that
  nobody waited for (#334's spike with `--no-settle`, and
  `tools/proof/reader_wedge_proof.py`'s P1) start twenty cache passes, and
  each pass's decode was a synchronous `copyNextSampleBuffer` loop inside
  its `Task`. On the build before this change W1's ramp render never
  landed (two runs out of two; the spike's first A row never landed in its
  1,500 s), and S0's `sample` showed all 12
  `com.apple.root.utility-qos.cooperative` threads in
  `copyNextSampleBuffer` under `writePeaks` and `writeSyncFeatures`, the
  ramp-audio queue's thread in `RampSourceReader.fill` →
  `copyNextSampleBuffer`, and 13 `readerOfflineMixer`, 16
  `audioqueue.source` and 16 `audiomentor` threads parked in
  `FigSemaphoreWaitRelative` at 0 % CPU. The probe's C1 measures the cause
  with no app and no reader on the pool: 30 s of audio read on a GCD queue
  took 0.10 s alone; with 12 of 12 cooperative threads held by blocking
  tasks it made no progress in 15 s, and finished only once they were
  released, 15.03 s from its start. So an `AVAssetReader` on a GCD queue
  needs the cooperative pool, and a pool filled by synchronous reads stops
  every reader in the process. The lane has two guards, each sufficient
  alone on this host, kept together as defence in depth. Guard 1, off the
  pool, is the rule above. Guard 2, width 2, can never fill a 12-thread
  pool; it also bounds the CPU and readers that cache passes take from
  playback, export and the ramp renderer, and it keeps passes FIFO. The two
  app mutants that take away one guard each survive by design, and their
  Release W1 times are the evidence: `unbounded` (width 64, off the pool)
  1.61 s, and `app-inline` (width 2, on the pool) 1.37 s, with a sample
  after P1 showing 2 cooperative threads in `copyNextSampleBuffer`. The
  scored mutants are `no-lane`, which takes away both and restores the old
  path (W1 FAIL on Release, S0 again 12 cooperative threads in
  `copyNextSampleBuffer`), and the probe's `wide` (L1, guard 2) and
  `inline` (L4, guard 1). With the lane on Release, W1's render landed
  1.37 s after its edit and W2 found all 60 of P1's cache markers 4.7 s
  after W1. Two is a concurrency bound, not a memory limit. Off the lane:
  thumbnails (`AVAssetImageGenerator`), the head checks
  (`peaksAreCurrent`, `syncFeaturesAreCurrent`, `speechIsCurrent`) and
  `pass.isCurrent()`, which run before a pass reaches the lane so a current
  cache never queues, and every other reader in the app (transcription's
  extract, the reverse renderer, export's loudness, the rate copy, the
  decoders, colour detection, sync analysis), which this change does not
  move. A pass's order (thumbnails, peaks, sync, speech, `retryPeaks`) is
  unchanged. W1 and W2 are `release_only` (V-4): they bound decode work in
  wall seconds, and a Debug decode runs about 17× slower (≈ 17.5 s for one
  250 s pass). **Risk accepted:** with many imports, later files' waveforms
  and sync and speech caches arrive later, two at a time in import order; a
  document closed while its passes wait still decodes them when their turn
  comes, as a running pass already did; and on a host whose cooperative
  pool is two threads or fewer, guard 2 alone would not hold, so there
  guard 1 is the only one.

  **Audited app-wide (#369).** Every `AVAssetReader` user in `app/Sources`
  was traced to the thread its loop runs on. `async`/`await` lives only in
  `MediaImporter.swift` and `SpeechEngine.swift` (W-8), so a reader is on
  the pool only when a `Task` body there reaches it; every agent tool call
  runs on the core's socket thread, an `AgentLane` queue or main, none of
  them the pool. Three reads were reached from a task and now run on
  `MediaImporter.readQueue` (`com.kgalligan.framejob.import-reads`, a
  concurrent `.userInitiated` GCD queue, neither the cache lane nor the
  serial import queue) through `MediaImporter.offPool`: the import probe's
  PQ sample read (`MediaImporter.firstSample` under `detectedPQ`) and its
  first-frame decode (`DecoderSupport.decodesFirstFrame`), one hop in
  `probeAsset` inside `waitForProbe`'s task, in their old order before the
  #216 refusal; and a thumbnail pass's `thumbnailReader` build, whose
  one-clip composition writes `AudioRateCopy`'s 48 kHz copy for an HLG, PQ
  or Camera Log video whose audio is not 48 kHz. The rest were already off
  it: the cache passes' peaks, loudness, sync and speech readers on this
  lane; `AnalysisFrames`, its input pass and `AnalysisSoundEvents` on the
  `AnalysisLane` picture and sound queues; `Transcriber+Extract` on
  `Transcriber.work`, `CloudTranscriber.work`, `TranscriptFill.queue` and
  the agent tools' threads; `ReverseRenderer`'s reads on the reverse sheet's
  global queue; `ExporterLoudness` on the export's `buildQueue`;
  `ExporterWriter`, `ExportEncodePump` (the camera and codec export pumps)
  and `ExportWebMWriter` on their own export queues; `ProcessedLoudness` on
  its queue; `RampAudioRenderer` on `ramp-audio`; `ScrubGrains` on
  `scrub-audio`; `DeepStillFrame` on the frame queues, the agent thread or
  main; and `AudioRateCopy` from every other `CompositionBuilder.build`
  caller (playback's rebuild queue, the export's `buildQueue`, the frame
  and analysis queues, `ProcessedLoudness`, `scrub-audio`) and
  `RampAudioCache` on `ramp-audio`. Synchronize Audio's analysis reads the
  sync and speech caches, not media, and `SpeechEngine`, camera recording
  and the thumbnail generator use no `AVAssetReader`. The witness is
  `ReaderPool.swift` (await-free, always compiled): `note` at the three moved
  sites records, only while a probe records, whether each ran on a thread
  whose queue label ends `.cooperative`. `cache_lane_probe.swift`'s L5 (the
  hop's queue), R0 (the witness's control), R1 (the probe's two reads) and
  R2 (a converted strip's audio copy) are each red under their mutant
  (`pool-blind`, `probe-inline`, `thumbs-inline`). **Risk accepted:**
  `readQueue` is unbounded; its callers bound it (one probe per waiting
  caller, one hop per thumbnail pass), and `AudioRateCopy`'s process-wide
  lock serialises the copies. A reader on the main thread is a different
  rule and out of this audit.
- **#378 — One reader per output in `ExportWriter`, each cancelled only by
  its own pump on its own queue after its own last read.** It amends G-17
  and applies CX-15 (2) and (6) to `ExportWriter`. The video composition
  output is read through `videoReader` and the audio mix output through
  `audioReader`. Both readers are made over the same composition and both
  take the export's range. An audio-only row has no video reader, and a
  silent movie (no composition audio track) has no audio reader. The plain
  pump (`pump`) cancels its own reader in its `stop`, after its last read,
  and only when the write is stopping, so a clean export cancels no
  reader. The `av1` row's `ExportEncodePump` is unchanged. Its reader is
  cancelled by a block that the writer queues on the video queue after the
  pump's read loop, again only when stopping. `allInputsFinished` cancels
  only the writer. `cancel()` still only sets the flag. WHY: two outputs of
  one reader are coupled, because an output nobody reads stalls the reader.
  On the shared reader, a stop on one pump could therefore leave the other
  blocked in `copyNextSampleBuffer` for good. `cancelReading()` cannot wake
  that pump: `AVAssetReader.h` forbids calling it concurrently with a read,
  and calling it from main under a running read crashed 12 of 30
  mid-export cancels (G-17). With a reader each, neither read waits on the
  other. The other pump sees the recorded stop at its next check and
  leaves, and no thread cancels a reader another thread reads. **Measured**
  before the change (`tools/proof/webm_readers_probe.swift`, run by
  `tools/proof/export_readers_proof.py`): A1's project read at `h264`'s
  settings on one reader carrying both outputs and on two readers, each on
  a thread of its own, gave the same 150 frames byte for byte (64RGBAHalf),
  the same 240,000 frames of the 16-bit decode (R2), and the same 240,000
  frames of the float mix a normalised export reads (R3), sample for
  sample. **Instruments:** `-RCDevExportFault audio@N|video@N|audio-hold@N`
  (`ExportWebMDevFault.writerKey`, dev tools only) puts a fault into an
  `ExportWriter` export's audio pump (before its Nth read) or plain video
  pump (before its Nth append). With a fault set, the writer logs its
  readers' states once every pump has left (`framejob export dev readers:
  video S, audio S`). F1–F4 export W9's 24-clip 1080p project:
  `audio@40` on `h264`, `video@30` on `h264`, and `audio-hold@40` cancelled
  during the hold on `h264` and on `av1`. Each ends within the 10 s bound
  with no file at the path and both readers cancelled (status 4). The
  three mutants are caught on exactly their rows: `shared-reader` on F1–F4,
  `no-own-cancel` on F1–F4, and `encode-cancel-dropped` on F4. **Risks
  accepted:** the audio tracks are decoded by a second reader, so the extra
  cost is their decode. A read that never returns because a volume stops
  answering is still not woken; G-17's other half stands. `video@N` does
  not reach the `av1` row's MP4 sink, whose packets go through
  `ExportPacketSink.swift`.

- **#465 — ⌥-drag is `duplicate {delta, track}`, checked once at the landing;
  a clip drag's tick of more than one op applies whole or not at all.** It
  applies §4.4's "⌥-drag duplicates", AU-91 and AU-96 to the drag. `duplicate`
  gains two optional arguments. `delta` is where the copies land, relative to
  their originals, snapped to the grid and clamped at 0 over the closure as
  `move_clip` clamps; absent, the copies land one span later, as they always
  did. `track` is a destination track, its index delta taken from the
  back-most, earliest clip the caller NAMED and applied to the copies of the
  named clips only; absent, each copy stays on its original's track. The
  drag used to duplicate one span later and then move the copies, so the
  interim spot had to pass the overlap rule, and a clip with another right
  after it failed there and the drag fell back to a move, with nothing said.
  The interim spot and the fallback are both gone: `duplicating` is the ⌥ key
  and nothing else, the drag sends the one op, and the rule is asked once, at
  the drop. **The track delta follows AU-91:** an unnamed linked partner's
  copy keeps its original's track and moves by the one time delta, so a
  picture ⌥-dragged a lane up lands on the lane under the pointer and its
  sound's copy stays on the sound's lane. That copy counts for the overlap
  rule, so a linked picture ⌥-dragged straight up, at no time delta, is
  refused by its own sound's copy, visibly. A copy of a named clip that would
  leave the track list is refused in `move_clip`'s sentence, naming the
  original's id; an unknown track is an `Err`. The span-length-0 identity
  stands only with `delta` absent: `delta: 0` on the same tracks reaches the
  rule and is refused. **A refused drop springs back.** `checkRefusal` asks
  one question of every clip drag, plain or ⌥, on a lane or past the lanes:
  did every dragged clip, or on ⌥ its copy, land at its own start plus the
  drag's change in time, on the track the core gives it? The core puts the
  back-most, earliest dragged clip on the track under the pointer, or past the
  lanes on the track the drop made, and keeps the rest the same distance from
  it; on the grabbed clip's own row every clip keeps its track. Anything else
  flashes from the proposed ghost to where the clip is, as a refused plain
  move always has. **The tick.** #88's fold in `ReelProject.applying` keeps
  a list that half applied, which is right for a compound gesture and wrong
  for a drop past the lanes, where an `add_track` that applied beside a
  refused move or duplicate would leave an empty track and an undo step. So
  the clip drag's tick goes through `timelineDragUpdated`: a list of more
  than one op is tried op by op through `SwitchAngle.Trial` on the live-edit
  base, and any refusal drops the whole tick, which leaves the last good
  frame as a refused one-op tick does (#8). #88's fold is not changed, and
  every other gesture keeps `onLiveUpdate`. **Risks accepted:** a refused ⌥
  drop flashes and says nothing else, as a refused plain drag does: no beep
  and no strip sentence. A refused drop after a good tick keeps that good
  frame with its one undo step, as a plain drag always has.
- **#472 — A marker on a tick another marker holds is refused, naming that
  marker.** Amends #88's list of the rules that speak. `add_marker` at a
  held tick, and `set_marker` with a `time` on one, answer `marker {holder}
  is already at {at} ticks; two markers may not share a frame`, written once
  in `edit_track.rs`'s `marker_taken`. They were an `Err`, and the reason is
  #88's for `detach_audio`: Mark ▸ Add Marker and M are live on any frame,
  and an `Err` is an error alert with the raw ids and ticks, where a refusal
  is a beep and the inspector's strip. No undo step, as before. An agent now
  reads `Add Marker was refused at add_marker: …`, which is what the
  catalog's "refused" already said. A marker drag's live ticks swallow every
  non-applied answer (`ProjectDocument.updateLiveEdit`), so nothing changes
  there.
- **#470 — A rule that can only stop an export is told before anything is
  queued or any file is touched, and a file is replaced only once its
  pipeline has been built.** Two rules can only stop a resolved export: an
  image row over `ImageSequenceWriter.maxFrames` and G-33's same-shape rule on
  an alpha row. Both lived in a pipeline's `init`, which ran after
  `Exporter.startWriting` had removed the file, so a job they stopped left
  neither the old file nor a new one. `Exporter.settingsRefusal(_:project:)`
  now answers both from the settings and the project: the image rows ask
  `ImageSequenceWriter.frameCapRefusal`, every other row asks
  `checkAlphaSurvivesTheSize` against `plan.renderSizeCG`, which is what
  `CompositionBuilder` hands `videoComposition.renderSize`. **Three doors ask
  it.** `export` refuses the call (#326 as amended by #486). The sheet's
  `syncReadout` shows the sentence in the readout in place of the summary and
  greys Export… and Add to Queue, with `resolved` left set so Save… can still
  name the choice; `commit(queue:)` asks once more, because a typed Custom size
  is resolved only by `endSheetFieldEditing`, inside the click, so that click
  beeps with no save panel. The writers keep their own checks as the backstop
  for `Exporter.export`'s direct callers. **The file.** `startWriting` moves
  the file aside to `.framejob-replaced-<UUID>` in the same folder, so a writer
  sees the empty path it always saw, builds the pipeline, then on a throw puts
  the file back and on success removes it and sets `replacedDestination`. A
  move that fails falls back to the removal this replaces. Any other throw past
  the doors, such as a stem naming the project's media, now leaves the old file
  too. **The cancel.** Both `finished` methods removed the path on a cancel
  whatever had happened, so a cancel during the build or the loudness pass
  deleted a file nothing had touched. They now remove it only when
  `replacedDestination` is true, and `finish` hands `graphicOutcome` the
  destination on the same condition. **Risk accepted:** a cancel or failure once
  writing has begun still loses the old file. Writing to a temporary file and
  swapping on success would close that, and needs room for both files at once,
  so it is the owner's call and not this decision. The queue's `superseded`
  mark stays at launch, as its comment's "being early is the honest direction"
  says, for a job that then leaves the file. Amends AU-108 (f).
  **Amended by #531** (ai-docs b2, the owner's answer of 2026-11-06): the
  move aside, the put back and the cancel's removal are gone. Every export
  is written to a hidden sibling and renamed over the path only when it
  succeeds, so the accepted risk above is closed, and the `superseded` mark
  moves to the later job's success.
- **#504 — The 600-frame sentence offers a lower frame rate only when the
  chosen rate is above the format's own.** A GIF at its own 12.5 fps has no
  lower row in the Frame rate popup, and `export` has no rate argument, so
  "or lower the export frame rate" named something neither reader could do.
  The sentence ends `Shorten the range.`, and `Shorten the range, or lower the
  export frame rate.` when `settings.fps` steps faster than the core's own
  answer for the preset with no overrides. No rate is written in Swift, and no
  answer from the core means no clause. **Accepted:** APNG's 24 and 23.976 fps
  rows are below its 25 and go unnamed, because they reach only ranges from
  24 s to about 25 s. The rule is the rate against the format's own; it never
  claims a lower rate exists only in that case, and the pages keep saying an
  APNG can go down to those rows.
- **#477 — The delegate refuses a quit while any Export… progress sheet
  writes, and brings it back.** Asked directly while a sheet's export was
  writing, `applicationShouldTerminate` answered `.terminateNow`, because the
  delegate asked only the recorder and the queue: a ProRes 422 MOV stopped at
  40 % left 197,659,360 bytes with no moov atom, and an H.264 MP4 left 0
  bytes, neither readable. `ExportProgressSheetController` now keeps a weak
  registry of the sheets whose export has begun and not finished (added in
  `viewDidAppear`, removed first thing in `finished`), and `revealWriting()`
  answers whether any writes. The delegate asks it after the recording branch
  and before the queue, and when a sheet writes it answers `.terminateCancel`
  with no alert, whether the sheet is on screen or not, as the recording
  branch does. A hidden app is unhidden with `NSApp.unhide(nil)`, which also
  activates it, and a sheet's minimised window is deminiaturized; when neither
  holds, nothing is moved or activated. The queue's alert is unchanged and is
  asked after. **Unmeasured:** whether AppKit lets ⌘Q or Dock ▸ Quit reach the
  delegate at all with the sheet on screen, minimised or hidden. The decision
  does not depend on it, and `docs/manual-checks.md` SE-44 asks a person.
  **Accepted:** the document review has already run by the time the delegate
  is asked (AppKit's order, as for the recording and the queue), and a logout
  is cancelled while a sheet writes.
