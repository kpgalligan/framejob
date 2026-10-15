# Road map "audio-sync" — lining clips up by their sound

**Opened 2026-10-15** (AS-1, in the worktree `~/devel/framejob-audio-sync` on branch
`audio-sync`, from `ad86760`). The request and the spec this phase was built from live outside
the repo (`~/.claude/litecode/framejob/audio-sync-1/`); everything a later phase needs from
them is written here. Its decisions are spec §11 SY-1..SY-5, in
`designs/spec/11-decisions/audio-sync.md`.

**AS-n are this road map's phases, not manual-check IDs.** The person check this road map adds
is SE-10 in `docs/manual-checks.md`; the Assistant's checks are AS-1..AS-5 there, a different
series that shares the prefix by accident.

## Goal

Selected clips that play sound are lined up by their sound: one ANCHOR stays and every other
clip moves by a frame-snapped `move_clip` (one undo step), or the whole command refuses in a
sentence. The owner's case is a camera clip and a separate audio recorder: the camera stays and
the recorder moves. AS-1 lines clips up and MEASURES drift, reporting it in the tool's answer;
AS-2, straight after, corrects it.

## The owner's answers

**2026-10-15**, verbatim. The first message:

> I want to add a new feature. When two tracks are selected that both have
> audio, the new feature should attempt to sync them. Describe to me how you
> think this could be implemented (but don't make any changes)

And the three answers to the questions the description ended with:

> 1. frame-snapped is fine
> 2. I'd guess if one has video, that stays and the audio moves. Your use case
>    of a separate audio track synced to video is my plan.
> 3. Start with drift reported, but we'll almost certainly need to add
>    correction immediately. If easier to do that in this pass, do that as
>    well.

"Two tracks are selected" means two selected CLIPS (`ProjectDocument.selection` is a set of
clip ids), each on its own track. Correction was not folded into AS-1: it lifts the speed
refusal, changes the overlap and the pitch, and needs its own decisions (below, AS-2).

## AS-1 — the plan

A composite, not an op — `normalize_clip`'s and `detect_silence`'s shape, peaks in, ops out
(SY-1). No core, header, FFI, op or format change.

- `app/Sources/AudioSyncMatch.swift` (new): the signal arithmetic, pure — onsets, the FFT
  cross-correlation, its confidence (SY-3), drift (SY-5).
- `app/Sources/AudioSync.swift` (new): `canOffer`, `read` (the edited project's snapshot, plan
  and peaks; every per-clip refusal by name), `chooseAnchor` (SY-2), `plan` (readings → one
  `move_clip` per mover, or every reason; SY-4).
- `app/Sources/EditorViewController+Audio.swift` (new): Normalize's body and validator arm,
  moved whole out of the frozen `EditorViewController.swift` (its comment asked a second sound
  command to do this), then Clip ▸ Synchronize Audio and its arm. A refusal beeps and posts
  `projectDocumentDidRefuse` (the inspector's strip, CI-10).
- `sync_audio {clips, anchor?}` in `AgentCatalog+Audio.swift` / `AgentServer+Audio.swift`, an
  app-state composite with no `scope`, on the main thread (`normalize_clip`'s reason). The
  catalog grows to ninety-two product tools (thirty-one app-state).
- The menu item after Normalize, `UIMenuTable`'s `.plain` row, the inventory's row; the
  Assistant prompt's audio topic names `sync_audio`.

## AS-2 — the plan (not built)

Correct the drift AS-1 measures: most likely a `rate_stretch` (or `set_speed`) of the mover by
the measured rate, so its sound stays under the anchor's across the overlap. It lifts AS-1's
"plays at ×N" refusal for the mover as far as the correction needs, has to decide what the
stretch does to the pitch (`keep_pitch`), to the mover's end against its own track's
neighbours and to the overlap rule, and whether the menu shows the drift. Its decisions are new
SY- entries recorded before its code; AS-2 then closes this road map into `designs/adr/`.

## AS-1 — the record

Filled from runs only.

**What landed.** As planned above; no deviation from the spec's interfaces. Every refusal
sentence is the spec's but three, which the implementation wrote (`AudioSync.swift`):
- A nest: "clip N: is a nest, and a nest has no sound of its own to match: the waveform cache
  is per media file and the clips inside a nest each have their own. Open it (⌘↓) and
  synchronize the clips inside." Normalize's reasoning, reworded, because Normalize's own
  sentence tells the user to normalize.
- An anchor named but missing from the readings (reachable only from the probe: the tool
  refuses an `anchor` not in `clips`, and a reading problem refuses first): "clip N: is not one
  of the clips being synchronized, so it cannot be the anchor."
- A clip with no onset energy (the spec gave only "is silent…"): "clip N: has no sound that
  rises anywhere to line up by.", filed against the silent clip itself: a silent anchor once,
  not against every mover, and a silent mover alone.

**Probe** (`tools/proof/audio_sync_probe.swift`, through `audio_sync_proof.py --only
P1,…,P6`, Debug tree, 2026-10-15): 6/6.
- P1: five placements at 30 fps, each delta, start and lag as worked by hand (k 301 → 2,406,000
  ticks snaps to 2,400,000; k 33 → 198,000 snaps to 200,000); the lag within 1 tick of k·6000.
- P3: the FFT correlation against a brute-force sum over 649 lags, worst |Δ| 2.30e-06 of a
  scale of 16.3; a peaks envelope 9 dB quieter and 313 buckets later matched at lag −313.000,
  r 1.000.
- P4: the boundaries (r 0.25 with q 2 confident, r 0.2499 not; q exactly 1.5 confident, 1.4994
  not; runner-up −0.1 → q +∞ confident; no runner-up not confident); two unrelated random
  arrays r 0.094, q 1.12, not confident; two equal 300-bucket arrays no runner-up, refused "too
  little room to compare its sound with clip 1's".
- P5: +200 ppm → 200.7, −150 → −149.9, 0 → 0.0 over 15,000 buckets; +100 ppm at exactly the
  6,000-bucket minimum → 100.4 (SY-5's minimum-overlap rule held at the first value tried); one
  bucket under the minimum not measured.

**MCP rows** (`audio_sync_proof.py`, the Debug app, 2026-10-15): 16/16. The readings SY-3 and
SY-5 cite: S1 recorder → camera r 0.493, q 3.06, offset −1,881,359 ticks against the fixture's
−1,879,987.5 (2.3 ms), landed on frame 206 exactly, drift −14.6 ppm; S3 unrelated r 0.14,
q 1.10, refused; S10 the +200 ppm fixture (199.96 in this sign) measured 172.2 ppm over 150 s.

**Gate:** `make gate` PASS in 326 s (names, typecheck, fmt, lint, test 192 s, app 100 s).

**Release** (the gate's `make app`, `proof_app.py launch --app release`, no `Frame Job: ` line):
`audio_sync_proof.py` 22/22, every reading as on Debug, and S10's drift match r 0.307, q 1.82
(the closest of the fixtures to SY-3's thresholds); `op_argument_proof.py` 160/160 (EXACTLY 92
product tools); `phase9_proof.py` 231/231. `recording_probe.py --only catalog` 29/31: 7a (the
catalog is the ops plus the thirty-one app-state tools) passes; the two 7b rows (the file rows'
order: `set_media_color` and the media ops among the last eleven, `import_media` earlier) fail
the same way over `ad86760`'s untouched sources (28/31 there, 7a failing only because the
probe's set now names `sync_audio`), so they predate this phase.

**Mutants** (`--mutants`, probe-only): 8/8 killed — `lag-sign` (P1, and P6), `anchor-inverted`
(P2), `ratio-dropped` (P4), `before-zero-dropped`, `overlap-dropped`, `same-track-dropped`,
`neighbour-dropped` (P6), `ppm-scale` (P5). The first run "killed" `neighbour-dropped` by a
compile error (its edit left the closure's argument unused); the edit became `false && $0.start <
end` and a copy that does not build is now a failed control, never a kill.

**Review fix pass.** The review found the silence refusal filed against every mover even when
the ANCHOR was the silent one, and the ×N rate read from the first segment rather than the
time-scaled one. Both fixed in `AudioSync.swift`; P6 gained a silent-anchor case (refused
"clip 1: has no sound…" alone) and a silent-mover case (refused "clip 2: has no sound…" alone).
Probe 6/6 on the Debug tree; no mutant's anchor line changed, so the mutants were not re-run.
`make gate` on the fixed tree: PASS in 239 s (typecheck 0 errors and the 4 baseline warnings,
test 136 s, app 97 s). The proof's S rows had not changed, but every S row's plan now passes
the new silence check, so `audio_sync_proof.py` was run whole once more on that gate's Release
app (no `Frame Job: ` line): 22/22, every reading as before (S1 r 0.493, q 3.06, frame 206;
S10 172.2 ppm, r 0.307, q 1.82).

**Orchestrator.** The CLAUDE.md edits the phase owed were applied by hand: the root's
"ninety-two product tools", and in `app/CLAUDE.md` the thirty-one app-state tools, three
composites, and the map entry for `AudioSync`, `AudioSyncMatch` and `EditorViewController+Audio`.

## Person checks

SE-10 in `docs/manual-checks.md`: real camera and recorder footage, judged by eye and ear, and
how far a long take's end drifts.

## Owed

- AS-2 (above).
- `recording_probe.py`'s two 7b rows (the catalog's file-row order), failing before this
  phase (above).
