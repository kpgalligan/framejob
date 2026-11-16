# Spec §11 — decisions: Creator jobs, the analysis lane (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md), so a citation never has to say
which file. This file holds CJ-20…CJ-27 (CJ2a). The series goes on in
[`creator-jobs-2.md`](creator-jobs-2.md), which is why this file is lettered; `creator-jobs.md` says
what the road map builds and how its IDs are made (CJ-7). It is new because `creator-jobs.md` had
passed the spec's ~500-line split rule (#548, 2026-11-11); the entries moved here unchanged, and an
"above" or "below" in one may now point into a sibling file.

CJ-20…CJ-27 are CJ2a's (the analysis lane, its store and reader, `shots`, the dev tool `analysis_job`), recorded before its code.

- **CJ-20 — Analysis is a cache, made on demand.** It never runs at import, is never project
  state, and is never read by the composition plan or the frame recipe; a planner reads it and
  writes ordinary edits. A render drawn from it (CO's masks) is substituted by Swift, as a reversed
  file is (§5.6). No analysis kind bumps the format, adds an `rc_*` export or changes the core. The
  speech cache's import-time rule stands for speech.
- **CJ-21 — One lane, `AnalysisLane`, process-wide, with two queues:** a picture queue
  (`com.kgalligan.framejob.analysis-picture`, decodes and Vision) and a sound queue
  (`com.kgalligan.framejob.analysis-sound`, audio decodes and Sound Analysis, serial and idle until
  FC3), so a sound job never waits behind a face job. Each is a `DispatchQueue` at `.utility`,
  never the cooperative pool, never `MediaCacheLane`. A job is a source, a window's missing ranges
  and its kind; kinds that share a reader, a size and a grid decode once (`faces` and `subjects`,
  CJ3 and VR1). Jobs are wanted by owners — a document's command, a tool call, an export — as ramp
  audio's renders are (SR-12): `want` replaces an owner's set, an unwanted job is cancelled, a job
  wanted again while running is not, an owner whose `alive()` answers false is dropped at the next
  50 ms poll, `wait` returns on landing, failure, cancellation or its deadline, and an owner's
  `settled` runs on main after a landing or a failure. The lane keeps each of the last 256 jobs'
  runs (queued, started, ended, in process uptime, and the outcome). A job takes no `CachePass` and
  writes only through `AnalysisStore.publish`, inside `CacheLedger.publish(in:for: nil)`, so an
  import pass and an analysis job of the same media never cancel or wait on each other; it
  publishes at each range's end and after every 30 s of wall time. `-RCDevAnalysisHold <s>`
  (`FRAMEJOB_DEV_TOOLS` only) holds each job before its first frame, polling cancellation every
  50 ms. **Spike CJ-S3 (2026-11-01, `rule_sha256` `209c6f01…ce830`, matching CJ0a's table; OS
  build 25F80, Apple M2 Max, on AC, three lanes loading the machine; synthetic files, S-TH4
  owed):** frames a second, median of three, at long sides 256 / 1280 — the 4K HEVC 10-bit HLG
  file direct 213 / 244 and converted 668 / 618, two jobs at once 395 / 484 and 704 / 707; the
  1080p H.264 file direct 582 / 736, two jobs 1,124 / 1,465. **(a) The picture queue's width is
  1** (`AnalysisLane.pictureWidth`): rule (a) is applied at shots' size on each file through the
  reader (c) gives it, and two converted jobs reach only 1.05× one (the 1080p file's direct jobs
  reach 1.93×). **(b), measured with the lane built** (`lane_spike.py --playback`, the Debug
  app): `play_preview` composed 598 of 600 frames over 20 s of a 1080p30 timeline idle and 593
  while another document's ten-minute `shots` job ran (medians of 600 / 580 / 598 and
  593 / 588 / 599), a drop of 0.84 %, under 2 %: the picture queue does not pause while a
  transport plays, and `BackgroundRender.anyPlaying` is not added.
  **Amended by #435 (2026-11-09):** A job that is cancelled — its owner released (a tool call past
  its wait), its want replaced, its document closed, or Stop pressed — publishes what it had
  decided before it ends, by its kind's own mid-range rule (shots through the last stored index,
  `faces` and `subjects` through the samples decided, masks through `covered`, `sound_events`
  through the contiguous answered prefix). That publish only merges: when, under the publish lock,
  a marker is on disk that does not answer for the job's stamp (another stamp, canned, or its
  payload gone), it writes nothing and leaves that cache as it is, so a want replaced by a stamp
  already cached never loses it. A job cancelled before its first frame (in
  `-RCDevAnalysisHold`, or in the pre-roll) publishes nothing. A failed publish there is logged
  and the job still ends cancelled.
- **CJ-22 — The store.** A kind's results for one media are a marker `cache/analysis/<kind>/<media
  id>.json` and a payload folder `cache/analysis/<kind>/<media id>/` holding the files the kind
  names (`shots` a `frames.bin`, `faces` a `samples.bin`, CO's masks one movie per chunk and its
  mirrored chunks, FC's `sound_events` a `windows.bin`). A kind whose variants must coexist puts
  the variant in its name (`masks`, `masks_best`). Every kind has a grid on source time and stores
  per grid point only values that depend on that point's input and a fixed neighbourhood the kind
  names, never on where a job began or what else is cached; thresholds over time, minimum lengths,
  smoothing and identity are applied when a request is answered. The marker holds the
  `AnalysisStamp`, the payload's files and the COVERAGE: the sorted ranges of grid indices stored,
  merged where they overlap or touch, inclusive. A request is a hit when the coverage holds every
  index of its window plus the kind's read margin; otherwise a job runs only the missing ranges,
  each with the kind's pre-roll, and the coverage grows. **The publish** (`AnalysisStore.publish`):
  under a lock keyed by (cache folder, kind, media id), inside `CacheLedger.publish(in:for: nil)`,
  it re-reads the marker, deletes marker then payload when the on-disk stamp differs from the
  job's, reads the payload as it is on disk, applies the job's merge, writes it through a
  `.partial` and a rename, then writes the marker with the union of the on-disk and the job's
  coverage, sorted keys, `.atomic`; nothing in it waits on the main thread, so two jobs of one
  media merge rather than overwrite. The `AnalysisStamp` is the source's identity (`CacheStamp`'s
  size, modified second and duration; no path), the kind and its version (Vision request revisions
  inside it), a SHA-256 of the sorted-key JSON of the parameters the stored values depend on
  (never T or m), the OS build (`kern.osversion`), the compute device (`cpu` for `shots`), and the
  reader's input (`raw`, or `converted` with the conversion as `ConvertedThumbsStamp` records it).
  A stamp that differs in any field is a miss, compared field by field; relink, consolidate and
  `set_media_color` therefore invalidate as for every cache. Coordinates are normalised 0…1 in
  the media's display orientation, origin top-left, and every answer carries the display size;
  times are forward-media source ticks, so any clip, speed, ramp or reversal reuses them through
  `SourceMap` and `ReverseMirror`.
  **Amended by CO-4 (CO0):** masks keep one payload file per media in the media's folder, the pack
  `masks.pack` (CO-S2's verdict; the draft's one movie per chunk, and its mirrored twin, were not
  kept).
- **CJ-23 — The frame reader.** `AnalysisFrames.swift` has a direct reader
  (`AVAssetReaderTrackOutput` over the first video track, 32BGRA, scaled to the kind's long side,
  turned upright from the track's `preferredTransform`) and a converted reader
  (`AVAssetReaderVideoCompositionOutput` over `MediaImporter.oneClip`'s composition, its
  `renderSize` the kind's size as Preview Quality sets one, read in the compositor's one format,
  64RGBAHalf, through step 0, so analysis sees what the person sees; its `RecipeSource` key is
  unregistered after). **Spike CJ-S3 (c): converted for converting media** — whenever
  `ThumbnailInput(media:urls:)` (a converting Camera Log or a PQ peak) or `ThumbnailInput(track:)`
  (an HLG or PQ track) exists — **and direct for the rest**, unless CJ-S2's rule 5 says otherwise
  for a kind; the converted reader cost 0.32× the direct one per frame on the HLG file. Frames
  arrive in presentation order; a frame's grid index is round(pts × fps) on the media's rate and
  the first frame on an index wins; a sample at k / rate takes the first frame at or after it. **The
  pre-roll is decoded frames, not indices:** a range's read starts two frame durations before its
  first index and, while fewer than two kept frames precede that index, restarts from twice as far
  back, until two do or the media's start is reached; only indices inside requested ranges are
  stored. CO-7 adds a third arm for masks (CO1).
  **Amended by CO-7 (CO0):** the masks' third arm reads with `AVAssetReaderTrackOutput`, every
  frame's presentation time kept, and converts a converting media's frames through step 0's own
  `InputPass` on the GPU, never through the one-clip composition.
- **CJ-24 — `shots`: hard cuts from a deterministic picture difference, no ML.** **Spike CJ-S4
  (2026-11-01, `rule_sha256` `eea6c190…46f9d1`, matching CJ0a's table; S-TH1 missing, so the
  no-cut input is ten minutes of the moving still and S-TH1 is owed):** the signature is a 4 × 4 × 4
  colour histogram (the top two bits of each of R, G, B) of the frame at long side 256, in
  whole-pixel counts; the distance is their L1 summed exactly and divided once by the pixel count
  (0…2, equal counts give equal values), stored as `Float32`. **T = 0.34, m = 12, PASS:** recall
  39 of 39 (100 %) on the 40-clip export at every T from 0.04 to 0.64, with no false cut on the
  ten-minute no-cut input from T = 0.08 (the 32-bin luma histogram also reached 100 %, from 0.20 to
  0.62; the tie went to the wider band, the colour histogram, whose median T is 0.34); every m of
  4, 6, 8 and 12 kept every cut of the fixture. **Stored per frame** (`frames.bin`, one 16-byte
  little-endian record per grid index from 0: `Int64` pts in ticks, −1 for no frame, `Float32` d1,
  `Float32` d2): d1(i), the distance to p1(i), the greatest index below i holding a frame, and
  d2(i), to p2(i), the greatest below p1(i); none → 0. **When answered,** frame i is a cut when
  d1(i) ≥ T; d2(n(i)) ≥ T, n(i) the least index above i holding a frame, the test passing when no
  frame lies in i+1…i+m+1 or at the media's end (a single flash frame returning to the shot is not
  a cut); and d1(i) is the largest d1 over i−m…i+m, an empty index counting 0, ties to the earlier.
  The read margin is m + 1 indices each side, clamped to the media. **Measured limits, stated in
  the guide:** a dissolve whose per-frame distances stay under T is not a cut (the fixture's, between
  two photographs, peaked at 0.16), but a dissolve between flat-coloured pictures (test patterns,
  slides, title cards) moves whole bars across a bin in one frame and peaked at 1.04, so it can be
  answered as one cut; and the flash rule rests on the return frame's d1 not exceeding the flash
  frame's — exact when the flash shares no bin with the shot (a white frame over the fixture: both
  2), not when the frames either side differ in the flash's bin.
- **CJ-25 — `get_media_analysis {media | clip, kind, from?, to?}` reads any kind, running or reusing
  it.** Exactly one of `media` and `clip`; `kind` from the kinds built (`shots` here); `from` and
  `to` integer forward-media source ticks, not snapped; with `clip` they default to, and are
  clamped to, the clip's played source window (`SourceMap`, `ReverseMirror`), and each cut is also
  answered as `clip_time` (ticks from the clip's start in its playing direction, a reversed clip
  through `pivot − source` first) and `timeline` (clip start + `clip_time`). It runs off main
  (`creatorOffMainTools`): one main-thread hop resolves the document, the arguments, the cache
  folder, the file and the request; the call wants it under an owner of its own (alive while the
  document is open and the call is not stopped), waits **holding the agent lane's lock**, as
  `get_transcript` does, and releases the owner on every exit. It answers `ok`, `kind`, `media`,
  `clip`, `from`, `to`, the display `size`, `cached`, the `stamp`, `run` (`queued_at`,
  `started_at`, `ended_at` in process uptime, only when it ran a job), `count`, `cuts`
  (`{frame, source}` and with `clip` `clip_time` and `timeline`) and `project`. **The bound,
  `AnalysisLane.callWaitLimit`, is 60 s** — CJ-S3's ten minutes of 4K HLG through the converted
  reader at 256 (26.9 s), × 2, rounded up to 10 s, inside 30…300 s; past it the call refuses naming
  the seconds of the window covered and "call again to continue", the job's published ranges kept.
  **The cap** is 512 KiB of `cuts` JSON; over it the call refuses naming the largest `to` from
  `from` that fits. Refusals, in order: not exactly one of `media` and `clip`; an unknown id; not a
  media clip, or a media with no moving picture; the file missing; `to` ≤ `from`; the bound; the
  cap. It is `get_transcript`'s counterpart for pictures and sounds; every kind answers through it.
  On device, no network, no key (CJ-3).
- **CJ-26 — A canned analysis is honoured only for a proof:** a marker with `"canned": true`
  carries only the source identity and is read only in a `FRAMEJOB_DEV_TOOLS` build launched with
  `-RCDevAnalysisCanned YES` and a matching `source`, so a planner's proof is byte-exact on any Mac
  and Distribution never reads one. Without the flag a canned marker is a miss and the next store
  replaces it.
- **CJ-27 — `analysis_job`, a dev tool (`FRAMEJOB_DEV_TOOLS` only), stands in for a document's
  command owner (CJ2b) in proofs,** because the MCP server answers one request at a time
  (`core/src/agent.rs`), so no call can overlap a held `get_media_analysis`. `analysis_job
  {project?, media?, kind?, from?, to?, wait?}`, off main: with `media` (then `kind` required, the
  window as `get_media_analysis`'s `media` form) it wants the window's missing ranges under that
  document's dev owner — one owner per document, alive while it is open, each want passing the
  owner's earlier requests too — and returns at once; with `wait` (seconds, 0…`callWaitLimit`) it
  then waits until every dev-wanted request has ended. It answers `{ok, now, wanted: {project,
  media, hit}?, jobs}`, `jobs` being every request a dev owner wanted since launch with its
  `ranges`, `queued_at`, `started_at`, `ended_at` and `outcome` from the lane's runs, and `now` the
  process uptime. Without `media` it targets no document. The assistant never sees it (AI-7's
  dev-tool rule).
