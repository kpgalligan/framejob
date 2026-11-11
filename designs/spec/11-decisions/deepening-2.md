# Spec §11 — decisions: Deepening, a clip's speed range onward (road map 7)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The entries continue [`deepening.md`](deepening.md), so a citation never has to say which file. This
file holds #190, #87, #86, #178, #216, #216-R, #228-P, #228-V, #228-O and #232. #231 on are in
[`deepening-3.md`](deepening-3.md). It is new because `deepening.md` had passed the spec's ~500-line
split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below" in one
may now point into a sibling file.

- **#190 — A clip's speed runs ×0.1–×1000; above ×12, in both pitch modes,
  the plan leaves the clip's audio out, and the inspector says so.** The
  range replaces ×10 in R6-10, D4-1 and D4-2: `SPEED_MIN` and `SPEED_MAX`
  (`core/src/edit_clip_timing.rs`) are 0.1 and 1000, `set_speed` clamps to
  them, `rate_stretch` stays inside them, and the reader refuses a speed
  outside them. **What B52a measured** (`tools/proof/README.md`'s B52a
  section): preview at ×120 showed 841 of 869 frames with a 3.445 s stall;
  preview at ×1000, 14 of 936 frames with a 30.285 s stall; export at ×120
  took 157.0 s for 30 s of output; export at ×1000 took 1480.5–1624.5 s for
  32.3 s in the earlier complete run. **The owner's decisions of
  2026-10-01:** keep ×1000, accept that the preview cannot keep up past
  about ×120, and test it later (`docs/manual-checks.md`, SE-7); and leave a
  clip's audio out above ×12, in both pitch modes.
  - **Why ×12.** An h264 export's loudness pass ("Measuring loudness…")
    never finishes once a clip's audio plays fast enough (B52b's notes; all
    on a 320x180 200 Hz tone). First round, at B52a's ×24/×32: a lone
    180 s clip missed a 45–60 s deadline at ×20 and ×24 in either pitch
    mode and at ×28 varispeed (B52a's binary does the same at ×24), and after a 2 s ×1
    clip a ×32 varispeed clip missed 120 s every time, while ×24 (both
    modes) and ×31 varispeed finished there. Second round, at ×16: a
    keep-pitch clip that starts its audio track stalled at ×15 and ×16
    (180 s, 600 s, and trimmed to 2 s), while ×14 (3.4 s) and ×12 (2.8 s)
    finished, as did ×16 varispeed and every ×16 after a ×1 clip. ×12
    leaves a margin below both stalls; `tools/proof/README.md`'s B52b
    section proves ×12 finishes in both modes and every shape. **Background,
    not the ceiling:** B52a's mixer limits — L.speech.spectral = 24 (the
    spectral algorithm hangs at ×31–×32) and L.speech.time_domain =
    L.speech.off = 32 (above ×32 no algorithm produces audio) — hold only
    for the mixer and an audio-only export, and are retired as the
    product's ceiling. The one number is `AUDIO_SPEED_MAX` = 12.0.
  - **The ceiling rule:** `assign` (`core/src/evaluate.rs`) places a clip's
    audio segment only when its speed is at or below `AUDIO_SPEED_MAX`. The
    video segment, the recipe and persisted state do not change, so crossing
    the ceiling is a plan difference and nothing else. The Speed section
    shows "Audio is silent above ×12" under the first selected clip that has
    crossed it.
  - **One pitch per plan audio track.** `place` puts an audio segment only
    on a track whose last segment has the same `keep_pitch`, so every plan
    audio track has one `pitch`, `CompositionBuilder`'s first-segment read
    of the algorithm is correct, and each clip's own pitch setting holds
    (#211). With the ceiling at ×12 no hang depends on it. **Accepted
    cost:** `audio_ramps` exempts only duckers on the voice's own
    COMPOSITION track, so a neighbour abutting a ducking clip on the same
    timeline track, with the other pitch mode, now sits on another
    composition track and is ducked by the ducker's extent and release.
    Today's exemption already depends on A/B placement (an overlapping
    neighbour on the B lane is ducked), so it is accepted, not avoided, and
    pinned in `core/tests/speed_x1000.rs`.
  - **The Fit arm:** `set_speed` takes a `rate` or a `duration`, exactly one;
    a duration is snapped to the grid, held to a frame, and turned into the
    rate that plays the clip's content in it, which is then clamped like any
    rate. The current duration keeps the current rate (no phantom step). The
    Speed section's "Fit to" row sends it, and the Speed sheet's presets gain
    ×10 and ×100.
  - **One home for the numbers:** `speed_limits()` publishes
    `{"min":0.1,"max":1000.0,"audio_max":12.0}` through `rc_speed_limits`,
    and no Swift file types a speed bound. No persisted field changes; the
    format stays 10.
  - **The question (#212, the owner's ask of 2026-10-01).** A person who
    sets a speed that takes a clip with sound from at or below `audio_max`
    to above it is asked first, once, on a sheet: "“N” will be silent at
    ×S." (or "k clips will be silent at ×S." / "… at their new speeds."),
    with Set Speed (the default) and Cancel — the owner's wording, option
    B, 2026-10-02. **The doors:** the Speed sheet's Apply (the question on
    the sheet's own window), the inspector's Speed section — Rate, its
    presets, Keep pitch, Reset and Fit to — through `inspector.onEdit`, and
    the timeline's ⌥-drag rate stretch at its live end
    (`SpeedAudioDrop.swift`, `EditorViewController+SpeedAudio.swift`).
    **The rule** is judged on the core's trial answer against `audio_max`
    (D4-6), never a rate computed in Swift (D2-1): a media clip whose audio
    is enabled, whose media has sound, that plays above `audio_max` after
    the edit and at or below it before. **Not asked about:** a clip already
    above, a clip without sound or with its audio off, and a clip new in
    the answer — a paste, split, duplicate or detach mints it, and
    `paste_attributes` carries no speed (`edit_paste_attributes.rs`'s
    module doc). **Cancel adds no undo step**, and one question covers
    every clip a multi-clip edit takes over. **A rate stretch that
    crosses is put back before the
    question** (`endLiveEdit(_:cancelled: true)`, no step, no change
    count), so nothing is live while the question is up: a save writes the
    base and an agent call is not held (AI-12). Set Speed re-applies the
    gesture's last applied ops as one step named "Rate Stretch". **An agent
    gets no dialog:** every op tool's answer gains `audio_left_out` (the
    clip ids) and `audio_note` (a sentence naming them and the ceiling) when
    its edit crossed, and neither key otherwise (`AgentServer.editResult`).
    The export's loudness stall itself stays unfixed; ×12 keeps it
    unreachable.
- **#87 — On one composition audio track, a gain change with sound on both
  sides takes up to 25 ms — accepted; a track's first segment is held from
  time 0.** AVFoundation's audio mix slews every volume change on an input
  by at most full scale per 1200 frames (25 ms at 48 kHz), starting AT the
  change, and an input sits at the default 1.0 before its first ramp.
  Measured by B59's design spike on a standalone composition read at
  48 kHz in 2 ms blocks: a step 1 → 0 at a cut reads 0.96 0.88 0.80 … 0.08
  0.01 and is silent from cut + 1200 samples, and the same step mid-clip
  slides the same way. **What is done:** `CompositionBuilder.volumeLegs`
  holds each composition track's envelope at its own first segment's value
  from time 0, per composition track as `addAudioTracks` builds it. That
  includes a second source format's track, which carried the plan track's
  ramps up to its own first segment. So a clip that opens its composition
  track muted, fading in, or as a crossfade's incoming clip starts at the
  gain it asks for: in B59's runs, e1's overlap edge went from 0.507 to
  0.002 of full scale, a muted clip alone on its track from −27.2 to
  −240.0 dBFS in its first 25 ms, and `mixed_audio_proof.py`'s muted WAV
  after an AAC clip from −28.8 to −200.0 dBFS. The hold reaches the preview
  too, because `Playback` and the exporter read the same `audioMix`.
  **What is accepted:** every gain change on one composition track slides
  for up to 25 ms. At a hard cut to a muted clip on the same track, e1's
  limit row reads `cut_edge` 0.496 of the tone in the incoming clip's first
  25 ms, then −139.9 dBFS. A volume or mute step mid-clip slides the same
  way, and at a step up after a gap it is a 25 ms attack: the 0 → 1 step
  at a WAV's start that `mixed_audio_proof.py` measured before B59 at
  3.000–3.026 s (3.0000208–3.0249896 s). **Rejected:** starting the step
  25 ms early, which silences the incoming clip at the cut but leaves the
  OUTGOING clip reading 0.13 at cut − 4 ms and 0.04 at cut − 2 ms; an A/B
  composition track per format family, so that no two clips share a track,
  which changes family assignment (R2-1) for a 25 ms edge; and an envelope
  applied in the processing tap, which breaks "no tap on an untouched
  export". The owner decided this on 2026-10-01. **Amended by #217**
  (issue batch B61): the hold ends at the track's first SOUNDING segment,
  one whose source resolved; a missing-media or pending-reverse segment
  before it is held over, because it is empty time — `mixed_audio_proof.py`'s
  `missing-first` row, whose muted WAV after a missing AAC copy read
  −28.8 dBFS in its first 25 ms before the fix and −200.0 dBFS after.
- **#86 — A normalised export reads the mix as float, gains it and
  quantises once to the unchanged 16-bit encoder format; an un-normalised
  export keeps the Int16 decode.** Before B60 the write pass decoded the mix
  to 16-bit integer and applied the loudness gain to that, so a mix past full
  scale was clipped by the decode before the gain turned it down, and every
  normalised sample was rounded twice. Now `ExportWriter` reads a gained
  export through `ExportAudioGain.floatMixSettings`, the same dictionary the
  measurement pass reads, so the gain is applied to the signal that was
  measured. `ExportAudioGain` multiplies, clips and rounds to 16-bit once,
  and the encoder gets the format it always got. **Why this shape:** the
  encoders' input format does not change, and neither do any
  un-normalised export's bytes. `export_gain_proof.py`'s G1 proves that
  byte for byte, per audio preset, against a reference from the build
  before. And the gain now sees what was measured: the true-peak ceiling is
  at most 0 dBTP, so a gained hot mix cannot clip. **The risk it accepts:** an
  un-normalised hot mix is still clipped by the Int16 decode, and
  `ExportLoudness.mixClipped` (true only for a mix past full scale written
  with no gain) is what reports it. #86's part 2, a 24-bit WAV/AIFF option,
  is not decided here, and nothing here closes it off: the 16-bit output is
  one constant in `ExportAudioGain`.
- **#178 — The cache passes' save gate has five accepted limits** (issue
  batch B14, #115, #169; the owner, 2026-10-01). The save bracket is
  `ProjectDocument+CacheSaves.swift` and the ledger `MediaCacheLedger.swift`
  (`CacheLedger.publish`, `waitLimit` 30 s, `saveLimit` 120 s);
  `cache_pass_probe.py` is the probe. (1) A first save or a Save As loses,
  for the session, any cache file published after its listing: nothing
  swaps, and nothing re-runs the passes after a save that moves
  `cacheDirectory`. (2) Frames lost between a save's listing and its swap
  leave the strip unmarked, with holes, until the next open. (3) The head
  clears are not gated, so a withdrawal in that window is undone by the
  swap until the pass publishes again. (4) A write that began before its
  pass was superseded, and outlasts `waitLimit`, can land after the
  successor's clear. (5) A save whose completion never arrives gates its
  package's publications until `saveLimit`, 120 s after it began — the
  undo-flush hang `app/CLAUDE.md` names; publications and peaks retries in
  that window are lost for the session, and the expiry is not probed.
  **Why accepted:** each is a cache — regenerable, never required to open
  (§5.6) — lost or stale for at most the session, and each window is
  bounded by a save or by the two limits. The review's two nits are not
  limits: they landed in 9cfa035 (issue batch B29) — `awaitPass` cancels
  its sleeper (`cache_pass_probe.py` W1, mutant `no-cancel-sleeper`) and
  the doc lines say one CURRENT pass per key. **The bound it keeps by
  design:** a relink away from a stuck pass starts only after the full
  30 s wait (S1a measured 30.32 s).
- **#216 — Every Frame Job process opts in to macOS's supplemental VP9 and AV1
  decoders, and an import of a video track is a one-frame decode** (issue
  batch B72; the owner, 2026-10-02). `DecoderSupport.enable()` calls
  `VTRegisterSupplementalVideoDecoderIfAvailable` for VP9 and AV1 once per
  process: at launch, before a cache pass, before a composition looks up a
  track, and in the harness and the formats probe. **What is accepted:** a
  file whose first video frame decodes to 32BGRA through an `AVAssetReader`
  — VP9 Profiles 0 and 2 in MP4 on every Apple-silicon Mac, AV1 on an M3 or
  later — alongside everything that imported before. **What is refused**, at
  `probeAsset`, as `ImportError.undecodable`, with nothing added and no undo
  step: AV1 without hardware decode ("`<file>` is AV1 video, which needs an
  M3 or later Mac."), VP9 Profile 1 or 3 ("`<file>` is VP9 Profile `<n>`
  video, which this Mac cannot decode; VP9 Profiles 0 and 2 import."), VP8
  ("`<file>` is VP8 video, which this Mac cannot decode.") and any other
  codec with no decoder, named by its four-letter code. **Only a reader
  failure whose error is `AVError.decoderNotFound` (-11833) or
  `AVError.undecodableMediaData` (-11855) refuses** (`refusingErrorCodes`).
  Damaged or truncated data in a codec this Mac decodes (measured: -11821,
  -11880) imports as it did before; the check cannot and does not judge a
  file's damage, and a track that yields no sample but completes imports.
  **No bundled decoder:** AV1 software decoding is dropped and VP8 is out of
  scope (the owner, 2026-10-02). **No ffmpeg offer** for `.undecodable`: the
  refusal is final, since a rewrap would carry the same codec. **The risks
  it accepts:** one extra frame decode per import, relink and recording
  segment; VP9's alpha is lost in MP4; HDR VP9 is treated as HDR HEVC is;
  AV1 on an M3 is unmeasured until manual check HS-6; AV1 media already in
  a project on an M1/M2 still shows black, since nothing re-checks at open.
- **#216-R — A WebM or Matroska file is opened by a built-in rewrap, with no
  question: the Rust core indexes the container and Swift copies its first
  video and audio streams, unchanged, into a QuickTime movie** (issue batch
  B73, #216 stage 2 phase 1; the owner, 2026-10-02). **The core reads the
  container** (`container*.rs`, `ffi_container.rs`): it is byte parsing of
  untrusted input, bounds-checked, panic-caught at the FFI and testable
  black-box in `make test`, and the frame grid, the decode times, a laced
  frame's time, the codec setup records and the space estimate are
  DECISIONS. It opens the file read-only and reads no payload but the first
  VP9 keyframe's header and each Opus packet's TOC. **Swift does the rest** (`ContainerRewrap.swift`,
  `ContainerRewrapWriter.swift`): `AVAssetWriter` passthrough, the
  destination and its folder, the free-space query and the refusals' words.
  Neither side touches a pixel or a sample. **Its own walker, not
  `matroska-demuxer`** (measured): the crate reads every payload and exposes
  no file offsets, drops a BlockGroup's keyframe flag (`is_keyframe: None`),
  and its frame-at-a-time order deadlocked a single-thread writer feed.
  **Always `.mov`**, in `~/Library/Application Support/Frame Job/Rewrapped/`
  beside ffmpeg's conversions, under `FFmpegRewrap.destination(for:)`'s
  digest name, so a re-import reuses the copy: `AVAssetWriter` refuses
  Vorbis in `.mp4`, which phase 2 needs, and vp09, av01, avc1, hvc1, Opus
  and AAC all write to `.mov` and read back. **The space check comes first:**
  the core's `required_bytes` (the copied payload, 64 bytes a sample and
  16 MiB) is compared with `volumeAvailableCapacityForImportantUsage` on the
  destination's nearest existing folder, and a copy that will not fit
  writes nothing. **The pre-check:** the codec facts in the Tracks element
  feed #216's sentences — VP8, AV1 without hardware decode, VP9 Profile 1
  or 3 — so nothing is copied that would then be refused; #216's one-frame
  decode stays as the backstop after the copy. **A codec that is not
  copied** (Vorbis, FLAC, MP3, AC-3, MPEG-2 and the rest, or a compressed
  or encrypted track) is refused in its own sentence and FALLS THROUGH to
  the opt-in ffmpeg step; every other refusal is final. **Timing:** video
  is snapped to its frame grid (`nominal_fps` from DefaultDuration, else
  the median gap) when every frame is within a quarter frame of a grid
  point and no two share one, and is written at that grid's timescale, so
  an exact-time request lands on its frame; otherwise — most browser
  recordings — the raw millisecond times and their timescale are kept.
  Decode times are the sorted presentation times shifted back by the
  largest reorder. Audio is timed in samples from the Block time less
  CodecDelay; an Opus packet's sample count is its TOC's. A laced frame is
  its Block's time plus the frames before it in the lace; a laced COPIED
  video track with no DefaultDuration is refused at open. **Amended by
  #232** (issue batch B79): the movie's own timescale, the grid of each
  track's edit and duration, is the least common multiple of 600 and the
  tracks' timescales, where it was the writer's default 600. **What is
  dropped:** every video and audio track after the first of each kind,
  subtitles, chapters, attachments and VP9 alpha. **The risks it accepts:**
  no progress or Cancel in this phase (a copy runs at about disk speed); a
  document opened from the Finder blocks the main thread for the copy, as
  ffmpeg's conversion already does; the Media tab names the copy, not the
  original (amended by #228-O); the copy lives outside the package until Consolidate.
  **Amended by #228-V** (issue batch B77): Vorbis is copied.
  **Amended by NM-4 and NM-5** (rename R0):
  `~/Library/Application Support/Reelcut/Rewrapped/` is now
  `~/Library/Application Support/Frame Job/Rewrapped/`; a codec that is not
  copied is refused in a sentence ending "… which Frame Job cannot copy out
  of a WebM or Matroska file.", where it was "… which Reelcut cannot copy
  out of a WebM or Matroska file.".
- **#228-P — A person's WebM or Matroska copy shows its progress in a small
  window with Cancel, and a tool call's copy shows nothing** (issue batch
  B76, #228 part 1; the owner, 2026-10-03, O1–O8). **Every click door
  reports:** File ▸ Add Media…, a drop into a project, the Media tab's and
  the missing-media sheet's Relink (`ProjectDocument.probeNext` and
  `relinkNext`, through `copyWatch`), and File ▸ Open, a Finder double-click
  and a drop on the Dock or the welcome window (`readMediaFile`, through
  `probeForOpening`). Each hands `ContainerRewrap.assist` a watch, called
  once when a copy really starts (a reused copy calls none), and the copy
  reports its bytes to a `RewrapProgress` (`RewrapProgress.swift`).
  **The window** (`RewrapProgressWindowController.swift`) is a non-modal,
  titled panel with no close box, the same for every door, titled
  "Copying Movie", headed "Copying “`<file>`”", with the bar, "Reading the
  file…" until the copy begins and then "`<copied>` of `<total>`", and one
  Cancel button. **It appears only when the copy is still running 1 s after
  it starts**, so a copy of a few hundred megabytes shows nothing. **It never
  takes the keyboard from a Frame Job window:** while any window is key it is
  ordered front and not made key, so typing and Escape keep reaching the
  editor during an Add Media copy; it becomes key only when no window is
  (File ▸ Open, a Finder double-click), or when the person clicks into it,
  and only then does Escape cancel. It raises no modal and no sheet, and the
  project stays usable. **Cancel** reads "Cancelling…" and is disabled; the
  copy stops at once (each pump stops before its next sample, so at most the
  append in flight lands), the half-written `.partial.mov` is deleted, the
  file is not added and no alert appears; the other files of a multi-file
  import or drop still land; File ▸ Open of the file opens no project (the
  read answers `CocoaError(.userCancelled)`, which no door presents). A
  Cancel while the index is still being read takes effect when the read
  ends. **A re-import** reuses a finished copy silently; a cancelled copy
  leaves nothing, so the next import copies again. **A tool call passes no
  watch:** `import_media`, `relink_media`, `record_screen` and
  `open_project` (which reads on the main thread inside `withoutAsking`,
  where `probeBlocking` drops any watch and `probeForOpening` passes none on
  main) show no window, wait as before and answer exactly as before. MC-5
  holds: there is no MCP progress message and no way for an agent or the
  person to cancel a tool call's copy. **Amended by #231** (issue batch
  B79): `open_project` reads on the lane's thread, not main, still inside
  `withoutAsking`, where `probeBlocking` drops any watch; it shows no window
  and answers as before. **The risks it accepts:** an agent's
  `open_project` of a WebM still copies on the main thread and freezes the
  window for the copy's length (O7, #231; amended by #231: it copies off
  main and the windows stay usable); a quit during a copy
  leaves its `.partial.mov` in `Rewrapped/` until the next import of that
  file removes it (O8); ffmpeg's opt-in conversion still shows no progress.
- **#228-V — A WebM or Matroska file's Vorbis sound is copied into the
  rewrap's `.mov` unchanged, as Opus is** (issue batch B77, #228 part 2).
  **The format:** subtype `vorb` with `mFramesPerPacket` 0, the track's
  CodecPrivate — Matroska's Xiph-laced three header packets — verbatim as
  the cookie, and no channel layout. AVFoundation's own Ogg reader describes
  Vorbis the same way (cookie `02 1e 1c 01 'vorbis'…`); `AVAssetWriter`
  writes it into `.mov` (`.mp4`: `canAdd` false), and the copy decodes
  through `AVAssetReaderTrackOutput` and through `AVMutableComposition` +
  `AVAssetReaderAudioMixOutput`, mono, stereo and six channels (measured,
  macOS 26.5.1, ffmpeg 9.0.2, libvorbis 1.3.7). **The core reads the three
  headers** (`container_vorbis.rs`): the identification header gives the
  rate, the channels and the two block sizes; the setup header is walked to
  its mode table for each mode's block flag. **Each packet carries its own
  sample count**, by the overlap rule: n = prev/4 + cur/4, a packet's block
  size read from its mode number. **Packet 0 is bs0/4 + its own
  blocksize/4**, ffmpeg's convention (ffprobe reads 1024 for ffmpeg's
  2048/2048 encoder and 128 for libvorbis's short first packet), because
  the writer refuses a later append after a 0-frame packet (-11800/-12633);
  counts of 32–2048 there all decode the whole stream. A packet whose mode
  cannot be read — empty, not an audio packet, or past the mode table —
  counts as a short block. **Every packet is placed lead = packet 0's count
  later** than its Block time less CodecDelay, because packet 0 decodes to
  nothing and AVFoundation starts the decoder's output at the track's first
  sample time: on an ffmpeg WebM remuxed so its first Block is at 0 ms (its
  picture 22 ms in), a click ffmpeg places at 1.022 s decoded at 1.020 s
  shifted and at 1.000 s unshifted; where the first Block is at −21 ms, as
  ffmpeg's encoder writes it, both decode at 1.000 s, the writer laying the
  track out from 0 (the probe's T22 and T20). **Rate and channels come from the
  identification header**, over the TrackEntry's; a rate of 0 or above
  10,000,000 is unreadable, as the TrackEntry rate is capped today. **A
  track whose headers do not parse** keeps #216-R's sentence ("… has Vorbis
  audio, which Frame Job cannot copy …") and falls through to the opt-in
  ffmpeg step. **The risks it accepts:** the movie's 1/600 s edit grid
  (a remuxed libvorbis click read 1.0017 s against ffmpeg's 1.003, 1.0027
  with a 48 kHz movie timescale), which affects every copy written before
  #232 (amended by #232, issue batch B79: a copy written from then on has a
  movie timescale that contains its tracks' grids); no end
  trim, so the copy's sound may run up to one packet past the source's
  (144384 samples decoded where ffmpeg decodes 144000); and the headers'
  parse on every open. **Amended by #235** (issue batch B81): **the lead's
  reading holds, and the copy is not wrong.** The 0.000667 s B79 measured
  between the copy's click and ffmpeg's (#232) was the reference's, not
  the copy's. Read from the fixture (ffprobe, 2026-10-03, the designer's
  run and the batch's own): `p22.webm`'s audio Blocks are stamped 0, 22, 43, 64, 86 and
  107 ms for packets 1024 samples apart, with the picture at 22 ms, and
  `p22.ogg`'s packets sit at −1040, −16, 1008 … /48000, each 1024 long.
  ffmpeg's first decoded frame carries the SECOND Block's stamp, 22 ms, so
  its timeline reading puts the click at sample 49056 (1.022 s) where its
  plain decode puts it at sample 48000. The copy puts it at the first
  Block's time, 0 ms, plus (1024 + 48000) / 48000 s: the lead, then the
  decode, 1.021333 s. The 32 samples between the two readings are the two
  stamps' millisecond rounding — the first Block's true time is 16 samples
  (stamped 0), the second's 1040 (stamped 22 ms, 1056) — so each reading is
  0.333 ms from the source and neither is the better one; the lead stays as
  it is. **T22's reference is now sample-exact** (`click_reference` in
  `container_rewrap_probe.py`): the first audio Block's `pts_time` in
  `p22.webm`, plus (the first packet's duration in `p22.ogg`, in samples,
  plus the sample of ffmpeg's plain decode of `p22.webm` that first passes
  0.3) / 48000, held to 0.0001 s; the row prints ffmpeg's timeline reading
  and its difference beside it, held to nothing.
  **Amended by NM-5** (rename R0): "… has Vorbis audio, which Reelcut cannot
  copy …" is now "… has Vorbis audio, which Frame Job cannot copy …".
- **#228-O — A WebM or Matroska copy remembers its original: the media
  is named after it, Reveal in Finder opens it, a relink to another WebM
  records the new one, and a copy that is gone is copied again on open**
  (issue batch B78, #228 part 3; the owner, 2026-10-03, O10–O13 and Q1–Q4).
  **What is stored:** the media key `original`, `{path, bookmark}`, last in
  the media object, written `null` when there is none — format version 11,
  because an older build would drop it. The built-in copy records it on the
  descriptor (`MediaImporter.probeCopy`, the original's path and a
  bookmark of it); `path` and `bookmark` stay the copy's, so everything that
  plays, caches or consolidates reads the `.mov` as before. ffmpeg's opt-in
  conversions record none and keep the `.mov`'s name (Q4; amended by #233:
  a conversion records its original too). **Display:**
  `MediaSnapshot.name` is the one spelling of a media's display name — the
  original's last path component, else the path's — so the Media tab, clip
  labels, the relink sheets, Consolidate's messages and the search all read
  `talk.webm`. **The tooltip** of a Media tab row says where the copy lives,
  on its own line above the drag hint: "`<original path>` — copied into
  Frame Job's Rewrapped folder." while the copy's folder is
  `…/Frame Job/Rewrapped`, and "`<original path>` — copied into this
  project's package." otherwise, as after Consolidate (Q1, Q2). There is no
  badge and no path line. **Reveal in Finder** opens the original, or the
  copy when the original is gone (O11). **Relink:** the probe carries
  `original`, so a relink to a WebM records the new original (copied again,
  with #228-P's window) and a relink to any other file clears it (O12).
  Consolidate and the open-time re-anchor relink with no probe and keep it;
  Consolidate still copies the `.mov`, and the name stays the original's
  (Q2). **The re-copy on open** (`ProjectDocument+MissingCopies.swift`,
  after the re-anchor): a media whose copy is gone — `mediaURL(for:)`
  resolves nothing, or resolves inside the Trash, where Finder's delete
  moves the copy and its bookmark follows — whose original resolves and is
  still a Matroska file is copied again by the built-in copy only (never
  ffmpeg, never a question) and relinked to it with its probe, with no undo
  step, nothing dirtied and no alert. Each copy has #228-P's window after
  1 s, unless the read is on the main thread (amended by #231: or inside
  `withoutAsking`, an agent's `open_project`). A Cancel or a failure skips
  that media: it opens missing (the slate, the badge, Relink…), with no
  alert, and the next open tries again (Q3); a copy in the Trash keeps
  playing from there. The Trash counts as gone for this re-copy only; every
  other reader of `mediaURL(for:)` is unchanged. **Tool calls:**
  `open_project` reads on main inside `withoutAsking`, so its re-copy shows
  no window and raises no question (MC-5) and blocks the main thread for the
  copy's length (#231). **Amended by #231** (issue batch B79): it reads on
  the lane's thread inside `withoutAsking`, so its re-copy still shows no
  window and raises no question, and main is free for its length.
  `import_media` and `relink_media` answer
  `"original"`, the original's path, when one is recorded; `add_media`'s
  descriptor takes `original` as `{path, bookmark?}`; `get_project` carries
  it as the model's own JSON. **The risks it accepts:** a copy that is gone
  while its original has also moved stays missing until a Relink; a re-copy
  on an agent's `open_project` freezes the window, as #228-P's does (amended
  by #231: it no longer does); the
  copy's folder is still Application Support until #226.
  **Amended by NM-5** (rename R0): the tooltip's "copied into Reelcut's
  Rewrapped folder." is now "copied into Frame Job's Rewrapped folder."; the
  folder it is shown for, `…/Reelcut/Rewrapped`, is now
  `…/Frame Job/Rewrapped`.
- **#232 — A WebM or Matroska copy's movie timescale is the least common
  multiple of 600 and its tracks' timescales, so a track's start no longer
  rounds to 1/600 s** (issue batch B79; amends #216-R's Timing and #228-V's
  first risk). **The rule** (`ContainerRewrapWriter.movieTimeScale`, pure):
  `video` and `audio` are the described `timescale` of each track that is
  written, absent when the track is not written or its timescale is not
  positive. The candidates, in order, are lcm(600, video, audio); then,
  only when audio is present, lcm(600, audio); then none. The first
  candidate `s` with (seconds + 1) × `s` ≤ 2³¹ − 1 is set as the writer's
  `movieTimeScale` before `startWriting()`; none leaves the writer's default
  alone. A video-only copy takes lcm(600, video), else none. Overflow in the
  arithmetic is a candidate that does not fit. `seconds` is the largest,
  over the written tracks, of the last decode-order sample's end —
  max(pts, dts) + duration for video, pts + its sample count for audio (the
  described `frames_per_packet` when the packet carries 0) — over the
  track's timescale. **What does not change:** sample times stay in each
  track's media timescale (`mediaTimeScale` on the video input, the sample
  rate on audio, where it is never set); the movie timescale is only the
  grid of each track's edit and duration. The new grid contains the old
  1/600 grid and each track's own, so no time that was exact becomes
  inexact. **The 31-bit guard** exists because what `AVAssetWriter` does
  with a movie duration past it was not measured. **Accepted limit:** it
  reaches only a copy written after it. `ContainerRewrap.assist` answers a
  copy already on disk by its digest name (`FFmpegRewrap.existingRewrap`)
  before the writer runs, so a file copied before #232 keeps its 1/600 grid
  until that copy is deleted or copied again on open (#228-O); the name is
  `FFmpegRewrap`'s and old copies are not invalidated here. **Measured**
  (2026-10-03, macOS 26.5.1, Apple M2 Max; `python3
  tools/proof/container_rewrap_probe.py`, three runs alike, and its
  `--mutant movie-600`, which leaves the writer's default): each copy's
  `mvhd` timescale, read from the file, is 48000 for VP9 at 30 fps with
  Opus (P1), 240000 at 30000/1001 with Opus (P2), 48000 for H.264 with AAC
  (P3), 48000 for Opus alone (P14), 48000 for a variable-rate file's
  millisecond times with Opus (P15) and 30000 for 30000/1001 alone (P23),
  and 600 for all six under the mutant (G24). A Vorbis click whose first
  Block is at 0 ms (P22, T22) decodes at 1.021333 s from the copy against
  ffmpeg's 1.022 s on the source's timeline, 0.000667 s apart; under the
  mutant it decodes at 1.020 s, 0.002000 s apart. The other three clicks
  (P17 AAC, P18 Opus, P20 Vorbis; T17, T18, T20) decode at 1.000 s against
  1.000 s, 0.000000 s apart, with and without the mutant. The probe's
  bounds are therefore 0.0007 s for T22 and 0.0001 s for the other three
  (amended by #235, issue batch B81: T22's 0.000667 s was ffmpeg's timeline
  reading's own millisecond rounding, #228-V; its reference is sample-exact
  now and its bound 0.0001 s like the others).
