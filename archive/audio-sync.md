# Road map "audio-sync" — lining clips up by their sound

**Opened 2026-10-15** (AS-1, in the worktree `~/devel/framejob-audio-sync` on branch
`audio-sync`, from `ad86760`); **closed 2026-10-15** at AS-2 into `designs/adr/audio-sync.md`. The request and the spec this phase was built from live outside
the repo (`~/.claude/litecode/framejob/audio-sync-1/`); everything a later phase needs from
them is written here. Its decisions are spec §11 SY-1..SY-10, in
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

## AS-2 — the plan (built; see its record)

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

## AS-2 — the record

Filled from runs only. Built from `~/.claude/litecode/framejob/audio-sync-2/03-spec-final.md`
(outside the repo; everything a later reader needs is here and in SY-6..SY-10).

**What landed.** The drift section left `AudioSyncMatch.swift` (340 → 253 lines) for the new
`AudioSyncDrift.swift` (193), rewritten as SY-7's least-squares line through windows every
`max(500, ⌈(|O| − 2000)/63⌉)` buckets plus one flush with the end, and `resampled`, which puts a
near-×1 clip's onsets on its timeline grid. The new `AudioSync+Correction.swift` (121) holds
SY-8's decision, SY-9's band (`rateProblem`), SY-10's duration and op order, and SY-6's
corrected delta. `AudioSync.swift` (342 → 389) reads each clip's speed and in point, resamples,
fits, corrects and checks the FINAL span. `sync_audio`'s row gained `speed`, `drift_corrected`,
`drift_error_ms`, `residual_ms` and `drift_note`; the menu applies the same ops and shows no drift
figure. No core, header, FFI, op, format, tool name or argument changed.

**The STOP and the owner's decision.** SY-8 as first specified left a drift whose estimate was
uncertain by more than 2 ms. On the Debug app S10 measured the +200 ppm fixture (199.96 in the
tool's sign) at 197.358 ppm, 29.604 ms over the overlap, uncertain by ±2.134 ms (SY-7's
√(2000/step) widening kept), so it was left, and SY-7's calibration rule stopped the phase. The
owner chose the significance test (2026-10-15): correct when `|drift_ms| ≥ max(5, 3 ×
drift_error_ms)` and the speed stays in the band; the uncertainty is reported, not a cap.
SY-8 records it. S18's control, which errored and ended the MCP session when the recorder was
still at ×1, now fails by name (and a tool error in S18 is scored rather than raised).

**Deviations.** The band is tested as the closed range `(1 − 0.002)…(1 + 0.002)`: `abs(1.002 −
1)` is just over 0.002 in binary, which would refuse P8's in-band edges. P7's first fixture (a
160 s anchor, a mover drifting ±1,000 ppm across it) was refused by SY-3's coarse match (r 0.26,
q 1.27 and r 0.25, q 1.29); the shipped fixture sounds over 8,000 buckets (r 0.547, q 4.92 and
r 0.549, q 3.90), and the limit is #300.

**Probe** (`audio_sync_proof.py --only P1,…,P8`, Debug tree): 8/8. P5 within ±5 ppm (+200 →
199.88, −150 → −150.08, 0 → 0.01 over 27 windows; +100 at the 6,000-bucket minimum → 100.39 over 9
windows); the span note on a mover sounding in its first 3,000 of 15,000 buckets; the count note
"only 2 of the overlap's windows matched" on the two-end-windows case. P7: rate 0.9990013 for 1/k
0.9990010 (+1,000 ppm) and 1.0009995 for 1.0010010 (−1,000), delta 18,000,000 as hand-worked in
both, the centre-line control 18,100,000 and 17,900,000, `move_clip` then `set_speed` when it grows
(117,120,000) and the reverse when it shrinks (116,880,000), a neighbour abutting the old end
refused and the same 10 frames later planned (`set_speed` alone). P8: the significance test's
edges, the band, and a reading at 1/k making no op (re-measured −0.0078 ppm) while one at ×0.9999
is set to 0.9990021.

**MCP rows on Debug** (S1, S6, S10, S13, S17, S18 after the owner's decision): 6/6, the same
readings as the Release run below.

**Gate:** `make gate` PASS in 219 s (names 1 s, typecheck 5 s — 0 errors and the 4 baseline
warnings, fmt and lint skipped as unchanged, test 115 s, app 97 s).

**Release** (that gate's `make app`, `proof_app.py launch --app release`, no `Frame Job: ` line):
`audio_sync_proof.py` 26/26.
- S1: frame 206, r 0.493, q 3.06, drift 14.15 ppm, 2.12 ms ±2.89 ms, left under 5 ms, speed 1.
- S10: 197.358 ppm, 29.60 ms ±2.13 ms (13.9× its uncertainty), corrected to ×0.99980264 —
  `|s·k − 1|·150,000` = 0.39 ms against 2 — `keep_pitch` false, the recorder on frame 206, its
  duration 91,860,000 → 91,880,000, r 0.307, q 1.82; one undo back to speed 1, start 0.
- S17: the second call `moved` false, "already in sync", re-measured 1.24 ppm, 0.19 ms ±2.89 ms;
  one undo still S10's.
- S18: the corrected mix's lag −2.20 ms on [12 s, 22 s) and −2.53 ms on [148 s, 158 s), Δ −0.33 ms;
  the control at ×1 +24.09 and −2.39 ms, Δ −26.49 ms.
- Every other row as in AS-1 (S6 now reads "plays at ×2; … within 0.2% of it.").

`recording_probe.py --only catalog` 31/31: both 7b rows pass. The catalog was right and the probe
stale: c47d97d added `set_media_color` among the media rows, after `remove_media`; the probe's
order now includes it and reads the last twelve. The tool set and arguments did not change, so
`op_argument_proof.py` and `phase9_proof.py` were not re-run.

**Found on the way** (Release, S18's method on the fixtures): an `audio_wav` export puts a ×1
camera `.mov` clip +37.9 ms and a ×1 WAV clip +25.7 ms late, and a near-×1 varispeed clip about
2–3 ms early: a measured gap of about 28 ms between the ×1 and varispeed paths on the same
16 kHz WAV. Against this fixture's camera (an ffmpeg-muxed `.mov` with PCM audio) a corrected
recorder exports about 40 ms ahead, unconfirmed for real camera files (#298); a ×0.99999 clip
with Keep pitch on stops matching its source in the export (#299).
S18's |lag| ≤ 20 ms holds only because the varispeed path's offset is near 0 against SOURCE.

**Mutants** (`--mutants`, probe-only, the AS-1 eight kept with `ppm-scale` re-pointed to
`AudioSyncDrift.swift`, run against the tree the Release proof ran): 18/18 killed, no failed
control — `lag-sign` (P1; P6, P7 too), `anchor-inverted` (P2), `ratio-dropped` (P4),
`before-zero-dropped`, `overlap-dropped`, `same-track-dropped`, `neighbour-dropped` (P6; P7 too),
`ppm-scale`, `min-windows-dropped` (P5), `small-drift-corrected`, `uncertain-corrected`,
`rate-limit-dropped`, `speed-not-compounded`, `resample-dropped` (P8), `rate-sign` (P7; P8 too),
`order-inverted`, `end-unchecked`, `pivot-dropped` (P7).

**Review fix pass** (AS-2's review: two should-fix, one nit).
- `sync_audio`'s description still named the replaced 2 ms cap; it now says a drift is left
  "under 5 ms or under 3× its uncertainty (drift_error_ms)", as SY-8 does. Read back from the
  Release catalog.
- A clip at speed ×1 whose segment is time-scaled could pass the band on the segment's ratio and
  then be read, placed and corrected at speed 1. It is refused again, as AS-1 did, with "plays at
  ×N though its speed is ×1; Synchronize Audio lines up clips whose speed is the rate they play
  at." (`AudioSync.stretched`), and SY-9 records it. No row reaches it: the core's own ops never
  make such a clip, and the probe's rows start from readings, after `read`.
- The "40 ms ahead of the camera" sentence above, the ADR's and #298's were narrowed to the
  measured ~28 ms gap between the paths, the 40 ms named as this fixture's camera only.
- Re-run: `make typecheck` 0 errors and the 4 baseline warnings; `--only P1,…,P8` 8/8; `make
  gate` PASS in 233 s (names 1 s, typecheck 5 s, fmt and lint skipped, test 114 s, app 113 s);
  Release (`proof_app.py launch --app release`, no `Frame Job: ` line) `audio_sync_proof.py`
  26/26 with S10, S17 and S18 reading as above (197.358 ppm → ×0.99980264, 0.39 ms; 0.19 ms;
  Δ −0.33 ms, control Δ −26.49 ms); `recording_probe.py --only catalog` 31/31. No mutant's anchor
  line was touched (each still matches once), so `--mutants` was not re-run.

## Person checks

SE-10 in `docs/manual-checks.md`: real camera and recorder footage, judged by eye and ear at
the start, middle and end of a long take, in playback and in the export, and whether the
corrected recorder sounds clean.

## Owed

Reviewed against the tree at the close; each filed `ai-drafted`, `low-priority`:
- #298: the export's per-path audio offsets (×1 +26/+38 ms, varispeed −2 ms).
- #299: Speed with Keep pitch at ×0.99999 no longer matches its source in the export.
- #300: a large drift over a long take can defeat SY-3's coarse match before drift is measured.

Done: AS-2; `recording_probe.py`'s 7b rows (fixed, above).
