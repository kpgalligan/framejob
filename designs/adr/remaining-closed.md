# What the old remaining list closed

- **Status:** Closed record (2026-09-26). The items `designs/reelcut-remaining.md` recorded as
  CLOSED or DONE between road map 2's close (2026-09-17) and 2026-09-26, with the lessons each
  closure taught. What was still open became GitHub issues, and the document was deleted: its
  size ledger is `wc -l` plus the file-history ADRs' "Named next cuts", and its build settings are
  `designs/adr/rust-build-settings.md`.
- **Original:** `archive/remaining.md` (2088 lines) — the full record; sections cited below
  as "orig §x" refer to it. Code and proofs cite §1b, §2a and §2b; those sections are summarised
  under the same names here.
- **Spec decisions:** spec §5.6 (the cache marker); D7-1, D7-2, D7-3 (the time bounds that closed
  #24, #25, #26 and #31); E2-27 (#27); R6-10 (the caption path's speed and millisecond clamps);
  R6-12 (no `region` key); R6-15 (#30); R6-16 (#32); D4-4 and D4-6 (unnest re-snaps; the Speed
  sheet asks the core); K-1 (#35), K-2 (#37), R2-1 (#34); CI-10 (the refusal strip).

## Context

The file began as the honest remainder when road map 2 closed: the debt two large phases left,
plus the checks no script can make. It then became where every later road map and issue left its
dated size readings, residue and "filed, not fixed" defects, and grew to 2088 lines, most of it
history. The history moved into this record; the open items became GitHub issues.

## Decisions and lessons

### §1 — two fixes that shipped without a permanent proof (orig §1)

- **§1a. The marker-scope refusal is `phase9_proof.py` section 9.** The untracked lane script's 28
  checks (not 29: a bare `grep -c` counted `def check`) were transcribed with their wording. One
  check was tightened because it passed VACUOUSLY under the mutant (`None == None`). Two were
  added: the wrong-typed-tick refusal's text, and the undo of an inherited-scope `remove_marker`
  landing on the document with the nest still open. Gate: `checkDocumentLevelTicks` made a no-op,
  and `scopeLanding` reverted, each fail five rows.
- **§1b. The breadcrumb is a probe compiled from `app/Sources` (`phase9_chrome.py`), not a
  harness photograph.** A harness render sits at scroll 0 and the defect only shows scrolled; a
  photograph cannot read a click count or a validator. The untracked instrument's fixture was not
  really scrollable (six tracks at 306 pt in a 324 pt pane: an unclamped over-scroll the app never
  reaches), and it never ENDED a rename. The tracked one uses ten tracks and asserts the scroll is
  real. The gate had to be a mutant on a tree copy, because no commit has the old z-order WITH a
  breadcrumb.
- **Lesson:** an instrument left in git-ignored `tools/proof/work/` is not evidence. Check a new
  instrument's fixture reaches the state the app reaches, and that every mutant can fail it.

### §2 — two live defects, found and deliberately left (orig §2)

- **§2a. `generateCaches`' "a cache on disk is not rebuilt" was false; now it is true, through a
  completion marker keyed to the source file's identity** (spec §5.6, `MediaCacheFiles.swift`).
  The doc-only cure left every open re-decoding a long recording. The plain existence check was a
  WRONG PICTURE, because `relink_media` keeps the media id. `CacheStamp` holds the byte size,
  modification second and the constants that size a cache, and deliberately NO path, so a moved,
  consolidated or copied package keeps its filmstrips. It is written LAST as
  `thumbs/<id>/complete.json` and `peaks/<id>.complete.json`, and only for a strip the pass can
  vouch for. A mismatched cache is deleted and rebuilt, and the old `.bin`'s withdrawal is posted
  at once. The first post of a replacing pass says `replaced`, so `TimelineView` drops that
  media's tiles. Passes for one media run in CALL ORDER through `CacheLedger`, an `NSLock`,
  because two `Task` hops from one thread are not ordered.
- **Lesson (§2a):** the first landing passed its own gate and was still wrong twice. Its review
  found the titled-document save (NSDocument's package swap loses frames written between listing
  and swap, and the marker certified the holes) and the old `.bin` readable through a rebuild.
  Every fix got a row that a copy without it fails. Twelve mutants, none surviving
  (`remaining_proof.py` 79/79, `remaining_probe.py`). `copyItem` preserves `st_mtime_ns`, so
  Consolidate rebuilds nothing.
- **§2b. A caption, Save Frame and export panel name is stripped of the DOCUMENT's extension
  through `ProjectDocument.displayStem`** (`ProjectDocument+DisplayStem.swift`, an extension
  because the base file was over the cap). The item's premise was half wrong and the scout caught
  it. The format popup's site wanted `CaptionExporter.renamed` over `{srt, vtt}`; the title-bar
  site wanted `{framejob}`; and two siblings had the same bare strip.
- **Lesson (§2b):** both sites were PANEL-only and the MCP path was right all along, so an MCP
  check passes against the unfixed build and is not evidence. An unwired site with correct helpers
  beside it scored 60/60 on behaviour; only a STRUCTURAL read that the sites call their helpers
  caught it.

### Issues closed from the "filed and not fixed" paragraphs (orig §5)

- **#24, #25, #26, #31 were closed 2026-09-22 by D7-1..D7-3 (`e1411be`, road map 7 §12.6–§12.7).**
  #24: a clip's `start` was bounded per call, not cumulatively; ~1020 maximum `move_clip`s walked
  it to `Int64.max` and the app trapped on `ClipSnapshot.end`. #31: a hand-written
  `duration: Int64.max` killed `open_project`. D7-1 bounds stored times and computed ends to ±9e15
  at admission (`core/tests/time_bounds*.rs`, `extreme_time_proof.py`). #25: the transition
  step-down walked one frame per pass over caller-sized clips (a measured ~6.7 hours); D7-2's
  bounded search (`transition_search.rs`). #26: an fps change left `video.motion` and
  `text.animation` timings off the grid, and `resnap` skipped clips inside nests; D7-3's
  `frame_grid.rs` covers stored nests, property timings, paste, attributes and unnest.
- **Lesson:** where a bound belongs is a spec §11 decision taken before code. #24 and #25 were
  deliberately labelled `bug` and not `ready-for-agent` until it was taken.
- **#27, E2-27 (`71f3a8d`):** a zero-duration In/Out stays legal, stored and inactive; the
  timeline draws no wedge, and the inspector and Clip ▸ Motion name the inactive edge.
- **#23 (road map 4 §9):** the peaks pass certified a partial decode; a peaks-only versioned marker
  and a strict reader keep a failed decode pending. **#28–#30, #32, #33** (road map 6
  §10.14–§10.20): lost-submit recovery (R6-14), an unwritable cache's impossible retry promise,
  transcript identity without display constants (R6-15), keyless reuse of cached transcripts
  (R6-16), Verify's stale answer. **#34–#37** (road map 2 §2): one composition audio track per
  source format (R2-1); Space routed by the window (K-1); the canvas editor sized on every change;
  Return applies and Esc asks (K-2). **#38**: the export Cancel crash, fixed in G3c and merged.
- **The playhead echo (2026-09-26, `538db30`):** `Playback` reported its own restore seeks as
  playhead moves; it now reports only seeks someone asked for. Paid first: `Playback.swift` 600 →
  546 by moving the meter to `Playback+Meter.swift`.

### Smaller closures (orig §5)

- **The triage labels:** `needs-triage`, `needs-info` and `ready-for-human` were created
  2026-09-20; `spec` is a sixth label that never takes `ready-for-agent`. Issues #23–#27 predate
  the labels and were not relabelled.
- **The frame-rate pair readers** read each half with `intValue` (29.97 became 29 in silence, and
  `Int(1e30)` trapped). Now `rateTerm`/`fpsPair` refuse by path (`op_argument_proof.py`).
- **Remove Silences' open sheet kept stale spans after an MCP relink.** The guard existed "because
  no proof could drive the sheet"; `silence2_probe.py` claim 17 drives it. **Lesson:** "no proof
  can reach it" is a belief to test, not a reason.
- **The Speed sheet's readout is the core's answer** (D4-6): the sheet applies its own `set_speed`
  ops to the immutable handle and reads the durations back, with no second copy of the arithmetic
  and no new export.
- **`make app` wrote an exported `RC_ASSEMBLYAI_KEY` into Xcode's build database.** Now `unexport
  RC_ASSEMBLYAI_KEY` covers every recipe (`makefile_env_proof.py`, 2/2, 1/2 under the mutant).
  Build databases are a cache; delete them where the key was ever exported.
- **c1-parts and C1 reader-review nits:** the per-media closing publish sends a real detail;
  `ms × 600` goes through a clamped `sourceTicks(milliseconds:)` (R6-10); `SecretStore.writeAll`
  retries `EINTR` only. `sink(_:)?.progress?` was REFUTED as a race (written once before the sink
  is published under the lock). The order-dependent probe row counts only new requests. The
  caption path clamps a finite but tiny `speed` in `Double` before the conversion (R6-10).
- **`app/CLAUDE.md`'s Hygiene paragraph** gained C1's two `DispatchQueue` seams (R6-7), by hand,
  outside any pipeline — the one rule C1 changed.
- **Detector pauses are not owed** for word captions: W4a's P10 found the pangram's pauses break
  by punctuation alone. Measure again only on a recording whose pauses carry no punctuation.
- **W1a's root `CLAUDE.md` baseline** (0 errors, 7 warnings) was written.

## Measured knowledge worth keeping

- **This Mac's 16 kHz audio extract is not bit-deterministic.** A decode lands on one of two byte
  strings differing in one sample's low bit, about one in five. `media/speech.mov`'s AAC extract is
  not repeatable at all (four extracts, four byte strings, 60–115 samples apart). A row wanting
  bytes from an extract must be a population or use an uncompressed fixture. It is the second
  AVFoundation audio non-determinism after the export's 8 ms duck-ramp window. Not worth chasing.
- **The estimate and the run classify a media in two places on purpose** (`CloudEstimate.fate`,
  what a run WOULD do before money is spent; `CloudTranscriber.transcribe`, what it DID). A
  `chrome` row compares them over two rounds; a later merge must keep a comparison.
- **`transcribe` has no `region` key** (R6-12): every proof instance runs under
  `-RCAssemblyAIEndpoint`, so the key would be false where it is proved. An `endpoint` host key is
  the honest shape, and it landed (#94): the run's client's host alone, absent on a keyless run.
- **Proof instruments are not held to the 400-line cap.** Road map 6 §10.13 corrected earlier
  sentences that said they were.

## §3 — how the size tolls were paid (orig §3)

- **The rule held:** a file over the cap paid first and alone, as a pure move gated by `make test`
  / `make lint` or `make typecheck` (0 errors, 7 warnings) before any behaviour landed. Examples:
  `edit_transition_shift.rs` out of `edit_transition.rs` (E1 review, toll T); `source_window.rs`
  out of `model_query.rs` and its callers (road map 7 phase A); `Transcriber+Languages/+Extract/
  +Jobs` (934 → 553) and `AgentCatalog+Captions.swift` (C1 tolls, two files off the list in one
  pipeline); `LayerRenderersReveal.swift`, `TextProps.swift` and `TextPatch.swift` (W3);
  `RecipeSource.swift` and `MediaDescriptor.swift` out of `ReelCore.swift` (G1a, G4b);
  `ExporterErrors.swift` out of `Exporter.swift`, taking it off the list (G3c);
  `ClipPane+Timing.swift` (G5a); `ClipSelectionHeader.swift`, `ClipPinnedBlock.swift`,
  `InspectorSection.swift`, `InspectorBinding+Writes.swift`, `InspectorSectionHeader.swift`,
  `InspectorSlider.swift` and `VideoPane+Obscure.swift` (road map 9, `InspectorPane.swift` 1679 →
  1156, `VideoPane.swift` 1411 → 1001).
- **Deepening can shrink a file without a move.** D3 took `AgentCatalog+Clips.swift` 941 → 791 by
  deleting what the core now publishes; D1 took `AgentServer+Clips.swift` 1196 → 847 by deleting
  what the app used to check by hand.
- **A fix that makes a file smaller needs no toll** (G3c's cancel fix, `ExporterWriter.swift`
  1114 → 1096).
- **Frozen files took wiring only**, counted per phase against an allowance the phase's spec set.
- **A new file at 399 is the warning for the next phase**, not a success: `MediaTranscript.swift`
  went to 411 mid-build and had its doc comment cut to fit; `SettingsWindowController.swift` went
  from 376 to 453 unnoticed (#58).
- **Dated line counts in prose go stale within days.** The live ledger is one table measured on one
  date, with the command to regenerate it.

## §4 — person checks judged (orig §4)

- **Graphics at 4K** were judged by the user on 2026-09-25 ("no performance issues" on an M2 Max,
  96 GB, with the bundled graphics), so G6 was deferred, not triggered. Scrubbing and an action's
  fade on a graphic clip were judged "smooth enough" and "worked perfectly".
- **`phase8_chrome.py` stopped failing on a locked console.** It reads `IOConsoleLocked` and skips
  the six key-window rows by name (150/150 unlocked, 144/144 with 6 skipped). **Lesson:** a host
  state is a proof input; skip it by name so a skip never reads as a regression or as a pass.

## §6 — the Rust build settings run (orig §6)

- Measured in a copy of `core/` with one target directory per variant, on an M2 Max at 12 jobs
  (cargo's default). A comment edit is all but skipped by incremental hashing. A real statement in
  the inlined `time.rs::snap_to_frame` measured 4.5 s for the staticlib, 6.1 s for every test
  binary and 8.7 s for all of `cargo test --release`.
- Landed in `[profile.release]` itself, not a custom profile, because `make rust`, `make test`,
  the Xcode pre-build script and `LIBRARY_SEARCH_PATHS` all hard-code `release`.
- In place afterwards: first `make test` 28.9 s (671 passed), then 6.5–8.6 s per edit against
  ~173 s before; `make app` built; the app answered over MCP with an empty parity log.
- **Lesson:** a build setting is measured before it is trusted. `lto = true` did the reverse of
  what it was there for, and the parent `~/devel/rasterize/core/Cargo.toml` carries the same
  line, unmeasured there.

## What it built — where it lives now

- The cache marker: `app/Sources/MediaCacheFiles.swift` (`CacheStamp`, `CacheLedger`),
  `MediaImporter+Peaks.swift`, `MediaPeakBuckets.swift`; proofs `tools/proof/remaining_proof.py`
  and `remaining_probe.py`.
- The display stem: `app/Sources/ProjectDocument+DisplayStem.swift`, `CaptionExporter.renamed`.
- The phase 9 instruments: `tools/proof/phase9_proof.py` §9, `tools/proof/phase9_chrome.py`.
- The time bounds: `core/src/time_bounds.rs`, `transition_search.rs`, `frame_grid.rs`.
- The build settings: `[profile.release] incremental = true` in `core/Cargo.toml` and
  `graphic/Cargo.toml`; `unexport RC_ASSEMBLYAI_KEY` in `Makefile`.

## Known limits

The limits these closures recorded and did not fix are open issues: the caption name
`chart.png.srt` in the panel against `chart.srt` over MCP (#43).

## Open items

None of its own. Everything still open from the original is a GitHub issue.

## Where to look in the original

- orig §1a, §1b: the two instruments' transcription, their gates and mutant scores.
- orig §2a: the cache marker's design, both review rounds, the twelve mutants and their scores.
- orig §2b: the three display-stem sites, and why the MCP path could not be the evidence.
- orig §3: every phase's dated `wc -l` readings from road map 7 D3 to the playhead echo, and the
  road map 3 table of seams.
- orig §4: the person checks as each pipeline wrote them (now regrouped into the `ready-for-human`
  issues, #47–#57).
- orig §5: the road map status paragraphs, the C1 residue blocks (c1-chrome, c1-parts, the reader
  review, c1-close), the filed-and-not-fixed issues, and the closed smaller items.
- orig §6: the build-settings table and the run narrative.
