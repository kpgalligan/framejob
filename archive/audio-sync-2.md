# Road map "audio-sync-2" — Synchronize Audio, round 2: features, search scope, candidates, refinement

Round 2 of Synchronize Audio (round 1 is closed: `designs/adr/audio-sync.md`, SY-1..SY-10). It is
worked in `~/devel/framejob-sync2` on branch `sync-2`, one litecode pipeline per phase. Its
decisions are SY-11..SY-16 in spec §11 (`designs/spec/11-decisions/audio-sync.md`), recorded
before AS-3's code.

## Goal

The owner tried Synchronize Audio on a real project and it refused. This round makes the match
work on the owner's case: features that survive a rumbling recorder, the clips' played windows
searched before the whole files, a choice among candidates instead of a flat refusal, the mover's
head trimmed where it would start before 0, and (AS-4) a sub-frame refinement.

## The owner's words (verbatim, 2026-10-15)

> There's a project file in ~/Downloads/IMG_0018.framejob. There is a video clip and an audio
> clip. The audio has much more space in front of it before the matching audio starts. I trimmed
> the audio in the project to be closer. Trying to sync says no matching audio found.

> When I play both camera audio and 'record.aifc' with the trimming I've done, the matching audio
> of me speaking plays about 1s apart, with the 'record.aifc' portion starting later.

> I think you should do some internet research on this to find existing approaches before we
> attempt more fixes. Since you seem to be struggling to match the audio in the sample I gave,
> which is not very complex. In the untrimmed file 'record.aifc', my speaking starts around
> 2:29:27. In the untrimmed video, 00:31:06.

After the research summary and the five-point proposal below, the owner said: **"Go ahead"** — to
all five points.

Asked, when syncing would push the audio clip before the start of the timeline, what Synchronize
Audio should do, the owner chose (2026-10-15):

> **Trim the audio's head** — the audio clip stays at 0:00 and drops its first 0.77 s, so what
> remains plays in sync. The video doesn't move. Only trims the moving clip, and only by the
> amount that would fall before 0.

## The owner's case, measured

The project: the camera clip is `IMG_0018.MOV` (55.27 s, HEVC, AAC 48 kHz stereo), placed at 0
from source 29.72 s for 25.52 s; the audio clip is `record.aifc` (165.0 s, PCM 24-bit 48 kHz mono,
a Mac recording), placed at 0 on another track from 147.63 s for 17.34 s. The owner's ground truth:
recorder − camera ≈ 118.7 s (speech at about 149.9 s in the recorder, 31.2 s in the camera), which
with those trims plays the recorder about 0.7–1 s late — what the owner heard.

| Method (recorder − camera, file seconds) | whole files | the owner's trimmed windows |
|---|---|---|
| AS-1's matcher (peaks cache, onset envelope) | −41.92 (r 0.13, ratio 1.25 — refused) | 123.2 (r 0.14 — refused) |
| BBC `audio-offset-finder` as published (MFCC, norm across coefficients) | 103.0 (z 3.7) | 110.1 (z 2.7) |
| standardised MFCC frames, SUMMED correlation (`mfccsync.py`) | −41.92 (z 6.3), runner-up **118.64** (z 3.7) | **118.68 (z 4.3)** |
| a crude landmark fingerprint (`landmark.py`) | nothing usable | nothing usable |

Why AS-1's matcher fails: the recorder is dominated by low-frequency rumble (about 54% of its
energy under 100 Hz), and the broadband 10 ms max-peak cache drowns the speech; the recorder holds
only about 5 s of clear speech (about 149.5–155 s) inside its trimmed window. And the files share
a SECOND, unrelated stretch: the recorder's first ~13 s matches the camera's last ~13 s at
−41.92 s (spectral-flux r 0.85 on 7 s; sample-level checks consistent to about 10 ms). It wins any
whole-file search.

## Research

- **BBC R&D, `audio-offset-finder`** (github.com/bbc/audio-offset-finder): the cross-correlation of
  standardised MFCC frames — 8 kHz, a hop of 128 samples, 26 coefficients — with the peak's z-score
  against the whole correlation curve as its confidence ("> 10 trustworthy, < 5 check"). Its
  published form takes the norm across coefficients; the round's `mfccsync.py` sums them instead,
  which is the form that found the owner's offset (the table above).
- **Bryan, Smaragdis & Mysore, ICASSP 2012** ("Clustering and synchronizing multi-camera video via
  landmark cross-correlation") and **`audalign`**: landmark fingerprinting to find candidate
  offsets, then cross-correlation to refine them. A crude landmark fingerprint (`landmark.py`)
  found nothing usable on the owner's files.
- **GCC-PHAT**: the standard time-delay estimator for reverberant rooms, sharp but prone to false
  peaks on its own — so it refines around a coarse offset rather than finding one (AS-4).

## What the owner approved (the five points)

1. Better features: standardised MFCC frames from decoded audio, cached per media, correlated as
   the SUM across coefficients, a z-score as confidence. Drift moves onto them in AS-4.
2. The played windows searched first; the whole files only when that finds nothing confident
   (reverses AS-1's whole files).
3. Candidates instead of a flat refusal: the candidate near the current placement when it is
   plausibly confident, else a refusal naming the top candidates; `sync_audio` returns them.
4. GCC-PHAT refinement on decoded PCM around the chosen offset (AS-4).
5. A test fixture from the owner's files, and a committed synthetic fixture with the same traits.

## AS-3 — the plan

Items 1 (without drift), 2, 3 and 5, and the head trim. SY-11 (the cache), SY-12 (the match),
SY-13 (played first), SY-14 (candidates, the choice, the refusal, the answer, the calibration
rule), SY-15 (the fixtures), SY-16 (the head trim). The files: `SyncFeatures.swift` (the
extractor), `MediaImporter+SyncFeatures.swift` (the cache's await-free half), `syncFeatures` in
`MediaImporter.swift` after a pure move of `ProbeBox` and `hasAlphaChannel` into
`MediaImporter+Probe.swift`, the feature search in `AudioSyncMatch.swift`, `AudioSync+Search.swift`
(played windows, the order, the choice, the sentence), `AudioSync.swift`'s plan with the trim,
`AudioSync+Correction.swift`'s `ops`, the tool's row and catalog text, the probe's P9–P12 and the
proof's S19–S21.

## AS-4 — the plan (not built)

GCC-PHAT refinement on decoded PCM around the chosen offset (and the PCM it needs); drift (SY-5,
SY-7) moved onto the features with SY-8's constants re-checked; #300 (large drift defeats the
coarse match) re-tested and closed when the features fix it; 118.68 s re-verified with PHAT; the
round's close into `designs/adr/audio-sync.md`, the original into `archive/` with its
`INDEX.md` row.

## AS-3 — the record

**What landed.** SY-11..SY-16 were recorded first (with amendment notes on SY-1, SY-3, SY-4 and
SY-10). Then, alone, the pure move that paid `MediaImporter.swift`'s toll (`ProbeBox` and
`hasAlphaChannel` to `MediaImporter+Probe.swift`, 596 → 567 lines; typechecked alone at 0 errors
and the 4 baseline warnings, the moved text byte-equal but for `private`). Then the cache:
`SyncFeatures.swift` (the extractor), `MediaImporter+SyncFeatures.swift` (the await-free half),
and `syncFeatures` in `MediaImporter.swift` (598 lines), called between `peaks` and `speech` and
once inside `retryPeaks` after an attempt that lands. Then the search: `AudioSyncMatch.swift`'s
onset matcher replaced by the feature search (`standardised`, `isSilent`, `summedCorrelation`,
`search`, `resampledFrames`), `AudioSync+Search.swift` (played windows, the order, `choose`,
`find`, the refusal), `AudioSync.swift`'s plan on `find` with SY-16's trim, and `ops`' `trimTo`.
The tool's row and catalog text, the spec (§5.6, §7.4, §7.9a), the README, SE-10 and the proof.

**The extractor against its reference.** On S19's two played windows the Swift extractor and
search measured recorder − camera 118.7181 s at z 15.17; a numpy run of `mfccsync.py`'s recipe
(`frameCount`'s `+1` added) on the same decoded windows measured 118.7191 s at z 15.15. The
whole files in the same numpy run: −47.0016 s at z 26.18 — the competing stretch, which the
played-first order exists to avoid.

**Calibration (SY-14's rule), Debug, 2026-10-15** — every printed z, and whether the fixture was
classified as it should be (each was; no constant changed):

| Row | What | Chosen | z |
|---|---|---|---|
| S1 | RECORDER against CAMERA | played, by confidence | 44.32 (next 1.25) |
| S2 | the same, the recorder the anchor | played, by confidence | 44.30 |
| S3 | UNRELATED against CAMERA | refused | best 5.98, then 4.61, 4.59, 4.51 |
| S8 | S1's files both at 0 (trimmed) | played, by confidence | 44.30 |
| S9 | windows that never meet | refused (never meet) | — |
| S10 | DRIFT against CAMERA | played, by confidence | 42.08 |
| S19 | OWNERLIKE | played, by confidence | 15.17 (next 1.73) |
| S20 | the owner's files, camera the anchor | played, by placement | 4.19 (next 4.15, 4.25 s from the placement) |
| S21 | the owner's files, recorder the anchor | played, by placement | 4.19 |

S3's unrelated recording reached z 5.98, 0.02 under `confidentZ`, and the owner's true match is
4.19 against `plausibleZ` 4: both margins are thin. In the probe, white-noise features near a
placement reached z 5.28 (1,500 against 1,500 frames) and 4.39 (500 against 500): with z taken
over every lag, the short-overlap lags at the ends lower the sd, so the full-overlap lags' noise
reads high. P4 and P11 therefore place their unrelated movers beyond every searchable lag.

**The calibration stopped (SY-14's rule; AS-3's review, findings 1 and 3; fix pass 1,
2026-10-15).** The review found the placement branch cannot tell a match from noise: the
calibration set had no unrelated pair placed where the near-placement rule can reach it. Two
scored rows were added, and both fail on the shipped constants:

| Row | What | Debug | Release |
|---|---|---|---|
| S22 | CAMERA and UNRELATED both at 0 (placement lag 0) | SYNCED by placement, z 4.59 (UNRELATED trimmed 1.667 s); candidates 6.00, 4.61, 4.59, 4.51 | the same, z 4.57; candidates 6.02, 4.66, 4.57, 4.55 |
| P13 | four pairs of 30 s bursts (seeds 131–138) and one of white-noise frames, both at 0 | bursts 1 refused (near 2.87); bursts 2 SYNCED by placement, z 4.14; bursts 3 SYNCED by CONFIDENCE, z 6.83 (near 3.63); bursts 4 refused (near 3.13); white noise SYNCED by placement, z 4.39 | identical |

On Release S3's best candidate (camera at 10 s, UNRELATED at 0) is z 6.04, over `confidentZ`; it
is refused only by the margin (1.37 against 1.5). The owner's match on Release is z 4.15 for S20
(the competitor at −113.65 s also 4.15, and listed first) and 4.16 for S21.

Statistics tried against the same cases, in a numpy reproduction of `search` over the app's own
`cache/sync/` frames (it reproduces the Swift z's to within 0.03: S3 6.01, S22's near 4.62, S20
4.20):

| Statistic | S20/S21 (true) | S22 near | S3 best | Separates? |
|---|---|---|---|---|
| z over every lag (shipped) | 4.20 | 4.62 | 6.01 | no: S22 ≥ S20 |
| z over the scored lags only | 4.02 | 4.59 | 5.97 | no |
| z of `c(L)/√overlap(L)` (each lag's null variance equalised), over the scored lags | 3.57 | 3.46 | 4.88 | only by a 0.11 split of these two numbers; see the sweeps |
| the same, over every lag | 3.54 | 3.48 | 4.91 | the same |
| margin over the best other candidate | 0.07 (4.20 − 4.13) | — | — | any margin above 0.07 refuses the owner |
| agreement across coefficients (t of the 26 per-coefficient correlations) | 4.09 (19/26 positive) | 5.22 (23/26) | — | no |
| mean per-coefficient correlation at the peak | 0.057 | 0.020 | — | no: unrelated windows of the owner's lengths reach 0.13 |

The sweeps that rule out the 0.11 split. With the near-placement peak taken at every placement
(steps of 10 frames, ±248 frames of each true peak excluded), CAMERA against UNRELATED gives a
near-placement z ≥ 4 at 10% of placements (shipped z; ≥ 3.5 at 17%, maximum 6.01) and, with the
√overlap normalisation, ≥ 3.5 at 18% (maximum 4.88). At the owner's window lengths (1,595 against
1,083 frames, 60 random draws of unrelated windows placed centred, for each of CAMERA/UNRELATED,
the owner's camera/UNRELATED, the owner's camera/RECORDER2, the owner's recorder/CAMERA and
CAMERA2/the owner's recorder) the shipped z reaches ≥ 4 in 10–45% of draws and the normalised z
≥ 3.5 in 5–32%; the owner's true 3.57 sits inside that null. The owner's own pair with the
placement swept away from both of its peaks stays low (played windows: maximum 2.10), because
its true peak widens the sd.

So no constant and no statistic tried classifies S20 and S21 as synced and S22 and P13 as
refused: under the rule the phase stops here, and the choice rule waits on the designer and the
owner. Nothing was loosened; the constants are as shipped.

**S19 (review finding 2): the fixture moved, the claim kept.** The original offset of 118.71 s put
the true landing at 35.7 frames, 6.7 ms from a snap boundary, inside the coarse match's error of
about 8 ms. SY-15 is amended: UTTER is 118.70 s later (`recorder2-v2.wav`), so the true landing is
1.2 s, a whole frame, 16.7 ms from either boundary. S19 now lands exactly on frame 36 (Debug:
118.6940 s, z 15.24; Release: 118.6945 s, z 15.20), an error of about 6 ms.

**S19 missed by one frame (before fix pass 1).** The recorder landed on frame 35, not 36: the
true value (snap of 714,000 ticks, 35.7 frames) sat 6.7 ms from the snap boundary, and the coarse
match measured 8.1 ms long (118.7181 s for 118.71 s; the numpy reference 118.7191 s). That is the
precision of a parabolic peak on 16 ms frames. The fixture moved in fix pass 1 (above).

**The owner's case.** S20: the recorder stays at 0 with its in advanced by 0.767 s (460,000
ticks), the camera unmoved; T = 118.6667 s (want 118.68 ± 1/30); unsnapped −offset 118.6706 s
(to be re-verified with PHAT in AS-4). S21: the camera moved +0.767 s, no trim, T 118.6667 s.

**Recorded runs** (Release, 2026-10-15, after `make gate` passed — names, typecheck at its four
warnings, fmt, lint, test, app): `audio_sync_proof.py` 32/33, S19 the one FAIL (118.7188 s, frame
35 for 36). Release's z's differ from Debug's in the second decimal (S3 5.97, S20 4.17, S21 4.14,
where S21's candidates list the −113.65 s stretch first at z 4.16 and the near placement chooses
118.67 s); every fixture classified as on Debug. `--mutants` 25/25 killed, no failed control;
`recording_probe.py --only catalog` 31/31; `cache_pass_probe.py` 13/13. Fix pass 1 (Release,
the same build; no app source changed): `audio_sync_proof.py` 33/35, S22 and P13 the two FAILs,
which are the stop above; S19 ok; no `Frame Job: ` line.

**The stop resolved: the owner's choice (2026-10-15).** Asked "When Synchronize Audio finds only a
weak match, what should it do?", the owner chose **"Ask, then apply"**:

> Strong matches apply as now. A weak match near where you placed the clip shows
> 'Weak match: move the recorder 0.77 s (trim 0.77 s)? Apply / Cancel'. Over MCP
> the tool returns the candidate and applies only with an explicit accept_weak
> flag. Also add speech-only matching (it lifted your match from z 4.3 to 5.9).
> Unrelated clips are never moved silently.

SY-17 (speech-only matching on the cached Silero VAD), SY-18 (the confident and weak tiers;
`confidentZ` 6 → 10, BBC's "> 10 trustworthy") and SY-19 (the Weak match sheet and
`accept_weak`) were recorded before the code, with notes on SY-11, SY-14 and SY-15.

**The designer's measurement (SY-17).** A numpy reproduction of `search` over the S20 session's own
`cache/sync/` and `cache/speech/` (`tools/proof/work/audio-sync/sync-s20-12734.framejob`):

| Mask | z | At | Notes |
|---|---|---|---|
| None | 4.18 | 118.672 s | the app's own number |
| Both stretches | **7.92** | 118.688 s | next candidate 4.43 |
| Recorder only | 5.50 | | |
| Camera only | 6.95 | | |
| Pairs where either is speech | 4.12 | | loses to 113.856 s |

The owner's recorder time-reversed, against 47 camera windows, reached at most z 6.04 masked. The
VAD caches: the owner's played windows hold 244 speech frames (the camera) and 248 (the
recorder); REC2 holds no speech chunk, so S19 matches on sound; the burst fixtures hold 0–1, so
S1–S18, S22 and P13 match on sound.

**What landed (fix pass 2).** `AudioSyncMatch.swift`: `confidentZ` 10, `speechProbability` 0.5,
`minimumSpeechFrames` 125, `frameCentreTicks` (19,200), `MatchedOn`, `speechMask`,
`resampledMask`, the masked `standardised`, and `search` taking both masks
(`SearchResult.matchedOn`). `AudioSync+Search.swift`: `find` slices the masks to the played
windows, `Found.matchedOn`, the refusal's rule sentence ("A match applies on its own at
confidence ≥ 10 and 1.5 above the next candidate; one ≥ 4 within 3 s of where clip N sits now is
offered as a weak match."). `AudioSync.swift`: `Reading.speech` (loaded once per media; with the
model available and no speech cache, "still being analysed"), the masks resampled in `plan`,
`Synced.matchedOn`. `AudioSync+Weak.swift` (new): `weakMoves`, `weakQuestion`, `weakNote`.
`MediaImporter.swift` (599 lines): `retryPeaks` also runs `speech` after the features.
`EditorViewController+Audio.swift`: the weak path and `askToApplyWeakMatch`'s alert sheet, Apply
committing through `performGroupedEdit` only on the asked-about handle and scope.
`AgentServer+Audio.swift` and `AgentCatalog+Audio.swift`: `accept_weak`, `weak`, the weak
not-applied answer, `matched_on`, the description's tiers from the constants.
`UIMenuTable.swift` and `inventory.json`: `synchronizeAudio:` is `sheet`, with its
`beginSheetModal` site. The proof: S3, S15, S20, S21, S22 retargeted, S23 (the masked null, with
its speech-frame control) and S24 (the sheet) added; P11 written from the constants, P13
retargeted, P14 and P15 added; seven mutants added and `standardise-dropped` re-anchored. The
proof's per-file cache wait is 120 s (from 60): in one Debug proof run the owner's recorder's
features landed just over 60 s after its import (the cause was not shown). On Release (fix pass
3, below) each owner file is ready in about 3 s.

**Calibration (fix pass 2; Debug, 2026-10-15; no constant tuned)** — every z, what it matched on
and its class; each fixture landed in the class the amendment named:

| Row | What | Class | On | z |
|---|---|---|---|---|
| S1 | RECORDER against CAMERA | confident, applied | sound | 44.29 (next 1.27) |
| S2 | the same, the recorder the anchor | confident, applied | sound | 44.31 |
| S8 | both at 0 (trimmed) | confident, applied | sound | 44.33 |
| S10 | DRIFT against CAMERA | confident, applied | sound | 42.06 |
| S19 | OWNERLIKE | confident, applied | sound | 15.25 (next 1.59) |
| S20 | the owner's files, camera the anchor | weak, then accepted | speech | 7.99 (next 4.40) |
| S21 | the same, the recorder the anchor | weak, then accepted | speech | 7.99 |
| S3 | UNRELATED against CAMERA (at 10 s) | refused | — | best 6.09, then 4.65, 4.60, 4.49 |
| S22 | CAMERA and UNRELATED both at 0 | weak, not applied | sound | 4.62 (candidates 5.98, 4.62, 4.58, 4.48) |
| S23 | the owner's recorder reversed (244 and 186 speech frames) | weak, not applied | speech | 5.53 (next 4.70) |
| S9 | windows that never meet | refused | — | — |
| P13 | bursts 1 / 2 / 3 / 4 / white noise, both at 0 | refused / weak / refused / refused / weak | sound | near 2.87 / 4.14 / 3.63 / 3.13 / 4.39 |

S20 and S21 land with T = 118.7000 s (want 118.68 ± 1/30; unsnapped 118.6851 s), the recorder
trimmed 0.80 s (480,000 ticks) or the camera moved +0.80 s. P13's bursts pair 3, confident at z
6.83 under the old 6, is now refused. The Weak match sheet (S24) reads "Weak match: move
“record.aifc” 0.80 s earlier (trimming 0.80 s off its head)?" and "Its sound matches
“IMG_0018.MOV” with confidence 7.99: under the 10 a match needs to apply on its own, and the best
match within 3 s of where it sits now. Cancel leaves everything as it is."

**Fix pass 2's recorded runs** (Release, 2026-10-15, after `make gate` passed — names,
typecheck at its four warnings, test, app; fmt and lint skipped, no Rust changed; own instance,
no `Frame Job: ` line): `audio_sync_proof.py <dir>/agent.sock` 39/39 (S1–S24, P1–P15). Release's
z's: S1 44.32, S2 44.33, S8 44.29, S10 confident on sound (197.374 ppm corrected to ×0.99980263,
frame 206), S19 15.26 (frame 36, recorder − camera 118.6938 s); S20 weak on speech at 7.93 (next
4.31), then accepted, T 118.7000 s, unsnapped 118.6848 s, trimmed 480,000; S21 weak on speech at
7.91, then accepted, the camera +0.800 s, T 118.7000 s; S3 refused (best 6.06, then 4.70, 4.59,
4.56); S22 weak on sound at 4.63 (candidates 6.07, 4.64, 4.63, 4.52); S23 weak on speech at 5.54
(speech frames 244 and 186); S24's sheet at confidence 7.99; P13 as on Debug. Every fixture in the
class the amendment named. `--mutants` 32/32 killed, no failed control;
`op_argument_proof.py` 160/160 (`sync_audio`'s gate names `accept_weak`); `phase9_proof.py`
231/231; `recording_probe.py --only catalog` 31/31; `cache_pass_probe.py` 13/13;
`v2_menu.py --only H` 5/5; `capture_spike/inventory.py --check` 5/5.

**Fix pass 3** (AS-3's second review). The read refusal names what is missing: "is still being
analysed — its waveform has not been written yet" only when the peaks are missing, else "… for
Synchronize Audio — its sound features have not been written yet" or "… its speech has not been
detected yet" (each driven on Release by deleting that cache of a placed clip). The weak tier's
sheet and note word a mover listed only for its drift correction (no delta, no trim) as the speed
it will play at — "play “lapel.wav” at ×1.0004, correcting its drift" — with each sheet item
carrying its own verb (P15's new case). The catalog prints the speech floor and the placement
radius from the constants. **Time to ready** — each marker's seconds after `import_media`, now
printed by `Session.media` — on Release (2026-10-15, AC power, own instance), the recorded run:
the owner's camera `IMG_0018.MOV` peaks 2.8–2.9 s, sync 2.9–3.0 s, speech 3.1–3.2 s (four
imports); the owner's recorder `record.aifc` peaks 0.1 s, sync 0.1 s, speech 0.5–0.6 s (three);
the generated 150–165 s fixtures 0.1–1.5 s peaks and 0.5–1.9 s speech. Both owner files imported
back to back, as a drop of the two, three runs on fresh projects: all six markers by 3.4 s, 3.0 s
and 3.0 s (the camera last). So a press straight after import may refuse "still being analysed"
for about three seconds on Release; no issue is filed, the time being a few seconds. Recorded
runs: `make gate` PASS (names, typecheck at its four warnings, test, app; fmt and lint skipped),
then on Release `audio_sync_proof.py <dir>/agent.sock` 39/39 (S20 weak on speech at 7.91, S21 at
7.86, S24's sheet at 7.94), no `Frame Job: ` line.

**Owed.** The thin margins are now a person's call, not a silent one: a weak match is asked
about (SY-19), and the confident tier's 10 stands well above every unrelated z measured (6.09 at
most, S3). Owed to AS-4 as before: GCC-PHAT refinement and drift on the features.
`app/CLAUDE.md`'s AudioSync entry (the orchestrator's): `AudioSync+Weak.swift` (the tiers'
question and note), the speech-only match, and the menu's Weak match sheet; and the map entries
for the three AS-3 files and `cache/sync/`. SE-11 (how the sheet reads) is the owner's.

## AS-4 — the record

**What landed.** SY-20 (the GCC-PHAT refinement) and SY-21 (drift on the features) were recorded
first, with notes on SY-1, SY-3, SY-5, SY-6, SY-7 and SY-11; SY-21's slice and robust filter and
SY-22 (the cost and the background run) after the phase's stop, before their code.
- `MediaImporter+SyncFeatures.swift`: the cache's version 2; the pass keeps the samples it fed the
  extractor as `cache/sync/<id>.pcm` (int16, 8 kHz), written after the `.bin` and before the marker
  in one publish; `syncSamplesURL`, `loadSyncSamples`; `clearSyncFeatures` takes both files.
  `MediaImporter.swift` was not touched (599 lines).
- `AudioSyncPHAT.swift` (new, 235 lines): `slice`, the band-limited `correlation` (300–3,400 Hz,
  `vDSP_fft_zrip`), `refine` (z over every lag, the peak within ±384 samples, the clear rule), and
  `FFT`, the one setup a plan shares.
- `AudioSyncDrift.swift` (rewritten, 249 lines): stage 1 on the features (1,250-frame windows, the
  mover's slice ±62 frames wider, `search` with a ±62-frame radius, the z-6 floor), the
  Theil–Sen + MAD filter (`inliers`), SY-7's count and span rules, the OLS line; stage 2, each kept
  window refined by PHAT along it, filtered alike and refitted. `resampled` and `windowLag` gone.
- `AudioSyncMatch.swift` (370 lines): `onsets`, `crossCorrelation` and `minimumCorrelation`
  deleted; `search` takes `radius`.
- `AudioSync.swift` (504 lines): `Reading.samples` in place of the onsets (the peaks loader gone;
  missing or mismatched samples read "its sound features have not been written yet"); `plan` makes
  one `FFT`, runs the new drift, refines over the overlap's centre 30 s along the line, and answers
  `Synced.coarseLag` and `Synced.refinement`. `AudioSync+Correction.swift`: `correctedDelta` at 75
  ticks a sample.
- `AudioSyncSheetController.swift` (new, 119 lines) and `EditorViewController+Audio.swift`: the menu
  reads on main, runs `plan` under the Synchronizing Audio sheet on a background queue and applies
  it in `finishSynchronizeAudio` only to the project and scope it read (`performGroupedEdit`), else
  the stale refusal. The hand-back waits a main-queue turn after the sheet goes, or the Weak match
  sheet found the window taken (S24 beeped in the first run).
- `AgentServer+Audio.swift`: `sync_audio` off main (read on main, plan on the server thread, the
  stale test and the answer on main); `AgentServer.swift` (frozen) adds it to
  `productOffMainTools` with one clause. Each row adds `coarse_offset`, `refined`,
  `refine_confidence`, `drift_on` and `drift_windows` (the last a deviation: S10/S17 print the
  windows, and no key carried them). `AgentCatalog+Audio.swift`: the description, from the
  constants. `inventory.json`: the sheet's `presentAsSheet` site, the weak sheet `reached_after`.
- The probe: P1, P3, P5, P7, P8, P12, P15 retargeted, P16–P18 new, P19 behind `cost <dir>`. The
  proof: S1, S10, S14, S17, S19–S24 retargeted, S25 and S26 new (an instance launched with
  `-RCDevSyncHold 3`), `--cost`, 39 mutants. §5.6, §7.4, §7.9a, the README, SE-10/SE-11's sources
  and SE-12.

**The stop (2026-10-16) and its resolution.** Two findings in the first implementation:
1. With equal 1,250-frame slices the triangular overlap envelope pulled every stage-1 window's
   peak toward the coarse lag: P7 read 986.6 ppm for 999 (`set_speed` 12.4 ppm off), P8's
   ×0.9999 and P12's +1,000 ppm cases failed, P5's clean cases read 199.21, −148.83, 95.88.
   Widening the mover's slice by ±62 frames gave 200.18, −150.01, 0.05, 99.99, P7 0.9990022 for
   0.9990010; ratified in SY-21.
2. P5's new noise case (the mover's frames 4,000–7,000 seeded noise) read 211.43 ppm for 199.96:
   windows partly in noise passed the z floor (12.8–16.9) with lag errors of 0.06–0.42 frame, and
   no floor short of the clean windows' own z band (17.3–17.7) helped; the phase stopped under
   SY-21's rule. The orchestrator ruled a principled stage-1 fix; the designer measured fitting at
   each window's matched-sound centroid (209.68, not taken) and Theil–Sen + MAD inliers (201.06;
   every k 2–6 passes, 7 fails), now SY-21's filter with k fixed at 3. The ruling also set SY-22:
   S10's call had taken 7.43 s on Debug (184.5 s under a host load of about 100) on the main thread.

**Calibration (SY-20's rule; Debug, 2026-10-16).** At `clearZ` 8 the owner's recorder reversed
(S23, a negative) was clear at z 10.24. `clearZ` moved to 15, the only other value tried, which
classifies every fixture:

| Row | Class | PHAT z (Debug) | PHAT z (Release) |
|---|---|---|---|
| S1 | positive | 433.8 | 434.2 |
| S2 | positive | 433.5 | 431.9 |
| S8 | positive | 433.9 | 433.8 |
| S10 | positive | 423.3 | 423.4 |
| S19 | positive | 131.5, 187.9 | 183.8 |
| P16, the planted 37.4-sample delay | positive | 162.5 | 162.5 |
| P17, 1.204 s and the +200 ppm pair | positive | 514.1, 516.0 | the same |
| S22 | negative | 4.03 | 4.52 |
| S23 | negative | 10.24 | 10.20 |
| P16, unrelated pips | negative | 4.71 | 4.71 |
| S20, S21 (the owner's; recorded, not inputs) | — | 9.00, 9.01 | 8.84, 8.06 |

**The owner's offset.** With PHAT at 15 the owner's files keep the coarse offset (`refined`
"coarse"): S20 unsnapped 118.6864 s, S21 118.6853 s (AS-3's coarse 118.686), T 118.7000 s in both,
the recorder trimmed 0.800 s or the camera moved +0.800 s. At 8 (Debug) PHAT would have refined
them to 118.6601 s (T 118.6667 s), 25 ms away, with no ground truth to say which is right (#303).

**SY-21's numbers (the recorded runs).** P5: 199.76, −150.01, −0.30, 99.99 ppm, the noise case
201.06 over 15 of 21 windows, the noise-ends case "only 2 of the overlap's windows matched". P17:
the +200 ppm pair 199.930 ppm on phat over 21 windows; with the mover's [40 s, 70 s) noise 200.322
features-only (18 of 21 windows) and 199.908 on phat. S10: 199.920 ppm on phat over 28 windows,
±0.022 ms, corrected to ×0.99980008 (0.006 ms over 150 s against SY-7's 2); S17 re-measured 0.013
ms; S18 Δ 0.10 ms (control −26.49 ms); S1 −0.077 ppm. `driftWindowZ` stayed 6. SY-8's 5 ms and 3×
and SY-9's 0.2% re-checked, unchanged (their notes in §11).

**#300 (P18).** 160 s of pips against a mover at ±1,000 ppm: z 41.23 and 41.36 by confidence, drift
998.95 and −1,001.04 ppm on phat over 29 windows, `set_speed` 0.9990011 and 1.0010010 for 1/k
0.9990010 and 1.0010010; the plan 6.86 s and 6.93 s in the unoptimised probe. #300 closed.

**SY-22's budget (P19, `--cost`, -O whole module, 2026-10-16, host load 12–78).** One hour of pips
against a +100 ppm mover: both files' loads 0.061 s of CPU, `plan` 0.731 s, total 0.793 s (≤ 1.5);
confident at z 113.31, drift 99.995 ppm (true 99.990) on phat over 64 windows, refined clear.
Drift alone with the shared setup 0.383 s, with a setup per call 1.704 s. On Release S10's whole
call took 0.23 s and S17's 0.24 s (Debug: 6.89 s and 7.00 s). The menu's sheet was up 0.01 s
(S14, Release) and 6.6 s (Debug); under the 3 s hold, 3.04 s and 3.09 s (S25, S26).

**Debug runs** (own instances, no `Frame Job: ` line): P1–P18 18/18; S1, S2, S8, S10, S13, S14,
S17–S26 all ok after two proof fixes found by them (S24's hand-back, above; S25 read the foot after
`last_step`'s undo had cleared it, and S26 set the selection before `last_step` reset it).

**Recorded runs** (2026-10-16). `make gate` PASS (names, typecheck at its four warnings, fmt and lint
skipped as unchanged, test, app; 341 s). Then on Release, own instance, no `Frame Job: ` line in it
or in S25/S26's held instance: `audio_sync_proof.py <dir>/agent.sock` 44/44 (S1–S26, P1–P18).
`--cost` P19 ok (above). `recording_probe.py --only catalog` 31/31. `inventory.py --check` 5/5.
`--mutants` 39/39 killed, no failed control (each new one on its named row: `phat-clear-z`, `phat-edge-dropped`, `phat-reach-dropped` on P16; `phat-shift-dropped`, `drift-phat-dropped` on P17; `drift-window-z`, `drift-inliers-dropped` on P5).

**Filed** (each `ai-drafted`, `low-priority`): #301 a file under 64 ms reads "still being
analysed" for good (SY-11's edge); #302 the refinement reads only the overlap's centre 30 s; #303
the owner's files are not refined (z 8–9 under 15); #304 features-only drift loses about 20 ppm
when the last third of a 120 s take is unrelated sound (the designer's `d2`: 179.38 ppm
features-only, 198.865 composed).
