# Spec §11 — decisions: Audio sync, round 2 onward (road map "audio-sync-2", #298's export offsets, and round 3's waveform gate)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the SY- series of [`audio-sync.md`](audio-sync.md), so a citation never has to
say which file; that file names the condensed record and the originals, and what stands beneath
every SY- decision.
SY-11…SY-16 were
recorded in round 2's AS-3 (`archive/audio-sync-2.md`) before its code, from the owner's "Go ahead" to
all five points of 2026-10-15 and the owner's choice of the head trim (SY-16). SY-17…SY-19 were
recorded in AS-3's second fix pass, before its code, from the owner's "Ask, then apply" of
2026-10-15, which resolved SY-14's calibration stop. SY-20 and SY-21 were recorded in round 2's
AS-4 before its code, from point 4 of the owner's "Go ahead"; SY-21's slice and robust filter and
SY-22 were recorded after AS-4's stop, from the orchestrator's ruling of 2026-10-16. SY-23…SY-27
were recorded in #298's phase 2 before its code: the export's audio offsets phase 1 measured and
located (`tools/proof/export_offset_proof.py`), removed at their causes; their numbers are the
designer's scratch measurement of 2026-10-16, SY-22's precedent. SY-28…SY-30 were recorded in
round 3 (the waveform gate) before its code; their numbers are the designer's scratch measurement
of 2026-10-16, SY-22's precedent, and SY-29's fail-closed clause is the orchestrator's ruling of
2026-10-16 on the round's spec review.

SY-23…SY-30 are in [`audio-sync-2b.md`](audio-sync-2b.md), moved there unchanged on 2026-11-11
because this file had passed the spec's ~500-line split rule (#548).

- **SY-11 — The sync-features cache (`cache/sync/`).** Each media file with audio gets
  `cache/sync/<media id>.bin`: f32 little-endian MFCC frames, 26 coefficients each, one frame per
  128 samples at 8,000 Hz (16 ms of source, 9,600 ticks; about 6.5 KB a second, 23 MB an hour),
  frame-major. The recipe is BBC R&D's `audio-offset-finder` (github.com/bbc/audio-offset-finder:
  8 kHz, a hop of 128, 26 coefficients, the correlation of standardised MFCCs), as the round's
  `mfccsync.py` wrote it: mono 8 kHz float, a 512-point frame holding a Hann(256) window centred
  in it, the power spectrum through 40 triangular HTK-mel bands from 0 to 4 kHz, `log(P·FB +
  1e-10)`, a DCT-II (unnormalised) to c0…c25. Frame f starts at sample 128·f; a file of n
  samples holds `(n − 512)/128 + 1` frames (0 under 512). Its marker `<id>.complete.json` is
  `{"source": CacheStamp, "version": 1}`, `PeaksStamp`'s shape; the version is bumped on ANY
  change to a recipe constant. The pass reads the first audio track (the one `peaks` reads) with
  speech's output settings at 8 kHz, keeps nothing unless the reader ends `.completed`, and writes
  the `.bin` and then the marker inside one `CacheLedger.publish`. It runs in `generateCaches`
  after `peaks` and before `speech` (which stays last), clears at its head when stale or when the
  media has no audio, and posts NO `.mediaCacheDidChange`: nothing memoises features. A
  `.bin` is read only under a current-version marker, its size a positive multiple of 26·4 bytes,
  every value finite; anything else is "still being analyzed" (amended by #526), never silence. **Its one retry:**
  `retryPeaks` runs the pass once, with that attempt's fresh stamp, straight after an attempt whose
  `peaks` answers true — so a file unreadable on the first pass and readable on a retry gets its
  features in the same session. Nothing else retries it. **The edge:** a file with sound but
  under 512 samples (64 ms) holds no whole frame, so the pass publishes nothing for it and it
  reads "still being analyzed" (amended by #526) for good rather than "too short to match" (AS-3's review, finding
  6; recorded, not handled). **Amended by SY-17 (AS-3's second fix pass):** the same retry also
  runs `speech` once, straight after the features, with the same stamp, so a file whose speech
  pass failed with its waveform gets its VAD probabilities in the same session too. **Amended by
  SY-20 (AS-4):** the marker's version is 2, and the pass also keeps the samples it fed the
  extractor as `cache/sync/<media id>.pcm` (int16 little-endian mono at 8 kHz, each `round(clamp(x,
  −1, 1)·32767)`; 16 KB a second, about 58 MB an hour), written after the `.bin` and before the
  marker inside the same publish; a failed write removes both files. A `.pcm` is read only under a
  current-version marker, its size a positive even number of bytes, and the features are current
  only when it is; clearing removes the marker, then both files. A version-1 marker is another
  version, so its media reads "still being analyzed" (amended by #526) until the next cache pass rewrites both — no
  migration. **Amended by SY-31 (#301):** a completed read with no whole frame publishes a
  zero-byte `.bin` beside its `.pcm`, read as no frames, so the edge above reads "too short to
  match"; sizes of 0 are read. **Amended by SY-34 (#305):** the pass decodes at the file's own
  rate and `SyncResampler` brings it to 8 kHz, so two passes write the same bytes; version 3.

- **SY-12 — The feature match and its confidence (supersedes SY-3 for the coarse match).** The
  two stretches compared (SY-13) are taken onto the timeline grid (SY-6's resampling, applied to
  each frame vector) and standardised per coefficient over the stretch (mean 0, sd 1; a
  coefficient with sd under 1e-6 is 0, so a silent stretch is all zeros). The correlation is the
  SUM over the 26 coefficients of each coefficient's full cross-correlation, `c(L) = Σ_k Σ_m
  x_k[m + L]·y_k[m]` (L the anchor frame minus the mover frame), by one zero-padded `vDSP_fft_zrip`
  per coefficient and ONE inverse transform of the summed cross-spectrum. The confidence of a lag
  is its z-score, `(c(L) − mean)/sd` with the mean and sd taken over EVERY lag (every overlap of at
  least one frame), as `mfccsync.py` does; z is 0 when sd is 0. A lag may be a candidate only when
  its overlap is at least 125 frames (2 s), or the shorter stretch when that is shorter. The
  summed correlation, not BBC's norm across coefficients, is the one the owner's files told apart:
  on the owner's trimmed windows the norm put the best lag at 110.1 s (z 2.7), the sum at
  118.68 s (z 4.3), the owner's own ground truth being about 118.7 s (round 2's request, its
  table). BBC's README reads its z-score as "> 10 trustworthy, < 5 check"; landmark
  fingerprinting then cross-correlation (Bryan, Smaragdis & Mysore, "Clustering and
  synchronizing multi-camera video via landmark cross-correlation", ICASSP 2012; and `audalign`)
  was tried by the round's `landmark.py` and found nothing usable on the owner's files. A file
  under 125 frames is "too short to match: its file holds under 2 s of sound."; a file whose
  every coefficient is constant is "has no sound to line up by.", named on that clip alone (SY-4's
  rule). **Corrected by SY-28:** "the owner's own ground truth" of about 118.7 s was never a true
  offset — the owner's two files are two takes of similar words, not one recording.

- **SY-13 — The played windows first (reverses SY-3's whole files).** Each clip's PLAYED window is
  the frames `[⌊(start − zero)/9600⌋, ⌈(end − zero)/9600⌉)` of its file on its timeline grid,
  clamped to the file. When both hold at least 125 frames they are searched first; only when that
  search chooses nothing (SY-14) and either window is a strict part of its file are the whole files
  searched. AS-1 searched the whole files because a user's trim could cut the shared sound out.
  **The reversal's reason is the owner's case:** the owner's recorder (165 s) and camera (55 s)
  share a second, unrelated stretch — the recorder's first ~13 s against the camera's last ~13 s,
  at −41.92 s — and that stretch wins any whole-file search (z 6.3 against the true 118.64 s's
  3.7, `mfccsync.py`), while the owner's trims hold only the real utterance. Where the user put
  the clips is evidence of what they mean to line up. **Corrected by SY-28:** −41.92 s is the
  only sound the owner's files SHARE and 118.64 s is not a true offset; the rule stands on its
  own reason, that the trims are the evidence.

- **SY-14 — Candidates, the choice and the refusal.** A search answers its CANDIDATES: the local
  maxima of c among the lags that may be candidates (a lag above its left neighbour and at least
  its right, a neighbour that may not be a candidate counting as no rival — so at an overlap of
  exactly 125 frames the last scorable lag of a slope rising into the unscorable edge is a
  candidate though it is a flank; recorded from AS-3's review, finding 5), highest first, each more than 60 frames
  (0.96 s) from every one already kept, at most 4, each refined parabolically; and its NEAR
  PLACEMENT: the highest local maximum of c (both neighbours scorable and strictly lower) within
  188 frames (3.008 s) of the lag at which the mover already sits, `(zeroN − zeroA)/9600`, refined
  — nil when there is none, so the flank of a peak outside the radius is never chosen. **The
  choice:** the best candidate when its z ≥ 6 and it stands at least 1.5 above the second (or
  there is no second), chosen "by confidence"; otherwise the near placement when its z ≥ 4,
  chosen "by placement"; otherwise nothing. **The refusal**, when no search chooses: "no matching
  sound found between clip A and clip N: in the played windows, moving clip N by +0.77 s
  (confidence 4.31) or −12.40 s (3.90); in the whole files, …. A match needs confidence ≥ 6 and
  1.5 above the next candidate, or ≥ 4 within 3 s of where clip N sits now." — each search that
  ran, with its candidates as the frame-snapped move each would make, and the rule printed from
  the constants; with no candidate in any search, "…: too little room to compare their sound."
  **The answer:** each `sync_audio` row drops `correlation`; `confidence` is the chosen lag's z;
  it adds `search` ("played" | "whole"), `chosen_by` ("confidence" | "placement"), `candidates`
  (`[{offset, delta, confidence}]`: the chosen search's candidates, plus the near placement when
  that was chosen and is not among them) and `trimmed` (SY-16). **Calibration rule:** the
  constants (6, 1.5, 4, 188 frames) are initial; when the proof's fixtures (S1, S3, S9, S10,
  S19, S20, S21, and from AS-3's review S22 and the probe's P13, unrelated sound placed where it
  overlaps) are misclassified they change, and every value tried is recorded here and in the
  road map; when no set classifies them all, the phase stops and reports the printed z's.
  **AS-3 stopped here (2026-10-15).** S22 (CAMERA and UNRELATED both at 0) is synced by
  placement at z 4.59 and P13's unrelated pairs at 4.14 and 4.39 by placement and at 6.83 by
  confidence, while the owner's true match is z 4.19 with a competitor at 4.15: no `plausibleZ`
  separates them, and neither does z taken over the scored lags, z of `c(L)/√overlap(L)` (the
  owner 3.57, S22 3.46; unrelated sound at the owner's window lengths reaches ≥ 3.5 in 5–32% of
  placements), a margin guard (the owner's margin is 0.07) or the mean per-coefficient
  correlation (the owner 0.057, unrelated windows up to 0.13). The numbers are in road map
  "audio-sync-2"'s AS-3 record; the choice rule waits on the designer and owner.
  **Resolved by SY-17..SY-19 (the owner's choice of 2026-10-15):** "chosen by confidence" is now
  the CONFIDENT tier and its z is 10, not 6 (BBC's own "> 10 trustworthy"); "chosen by
  placement" is now the WEAK tier (SY-18), which is never applied without asking (SY-19); and a
  search between two stretches that both hold speech correlates their speech frames only (SY-17).
  The refusal's rule sentence now reads "A match applies on its own at confidence ≥ 10 and 1.5
  above the next candidate; one ≥ 4 within 3 s of where clip N sits now is offered as a weak
  match." The 1.5, the 4 and the 188 frames are unchanged. **Corrected by SY-28, amended by
  SY-29:** "the owner's true match" here was a false pair; a choice of either tier now stands only
  on SY-29's clear GCC-PHAT peak, and the rule sentence gains "Either counts only when the two
  waveforms line up there (a clear GCC-PHAT peak of at least 15 within 48 ms)."

- **SY-15 — The fixtures and the owner's rows.** Beside AS-1's, a committed SYNTHETIC pair with
  the owner's traits, made by the proof from a seed (16 kHz, `camera2-v1.mov`,
  `recorder2-v2.wav`): a 60 s camera with a 5 s speech-like utterance at 31.2 s and a 13 s
  competing stretch at its end, and a 165 s recorder of heavy low-frequency rumble holding the
  competing stretch at 0 s and the utterance 118.70 s later than the camera does. S19 places them
  as the owner did (trimmed to the utterance, the camera at 2 s) and must land the recorder
  exactly on the snapped true offset by the played search. **Amended in AS-3's fix pass:** the
  offset was 118.71 s (`recorder2-v1.wav`), whose true landing (35.7 frames) sat 6.7 ms from a
  snap boundary, inside the coarse match's measured error of about 8 ms (the numpy reference of
  `mfccsync.py` erred the same way), so S19 missed by a frame. At 118.70 s the true landing is
  1.2 s, a whole frame, half a frame (16.7 ms) from either boundary; the exact-landing claim is
  kept, not loosened. **Amended by SY-18 and SY-19 (AS-3's second fix pass):** S20 and S21 are
  weak matches: a first call answers `moved: false` naming the recorder (or the camera) in
  `weak`, and a second with `accept_weak: true` must meet the landing below. S22, S23 (the owner's
  recorder time-reversed, placed where it overlaps the camera — a null that does run the
  speech-only search, both windows holding at least 125 speech frames) and P13 must never apply
  without `accept_weak` and never be confident; S24 puts the Weak match sheet up and cancels it.
  **The owner's own files**
  (`tools/proof/media/owner-sync/IMG_0018.MOV`, `record.aifc`; gitignored, never committed or
  copied out) are rows S20 (the camera the anchor) and S21 (the recorder the anchor), placed as the
  owner placed them; each needs recorder − camera within one 30 fps frame of 118.68 s. A row
  whose files are absent is a scored FAIL, never a skip: the owner's case is the reason for the
  round, and a proof run without it has not shown the round works. **Corrected by SY-28, amended
  by SY-30:** the owner's files are two takes, so S20 and S21 are refused nulls with no 118.68 s
  bound; the one-recording rows are owner-sync-2's (S27–S29).

- **SY-16 — The head trim (amends SY-4 and SY-10; the owner's choice of 2026-10-15).** Asked what
  Synchronize Audio should do when syncing would push the audio clip before the start of the
  timeline, the owner chose: "**Trim the audio's head** — the audio clip stays at 0:00 and drops
  its first 0.77 s, so what remains plays in sync. The video doesn't move. Only trims the moving
  clip, and only by the amount that would fall before 0." So with S the mover's start, I its in
  point, δ the final snapped delta, s' its final speed and d' its SY-10 duration: when `S + δ <
  0`, the excess `e = −(S + δ)` (on the frame grid) is trimmed off its head. Its span becomes
  `[0, d' − e)` and its in point `I + e·s'` (`trim_start`'s own arithmetic at s'), so source tick
  μ still plays at `S + δ + (μ − I)/s'`, SY-6's line. The ops are `set_speed` (only when
  corrected), `trim_start {clip, to: S + e}`, `move_clip {delta: δ}`, in that order, one undo
  step; `trimmed` is e (0 with no trim). The anchor never moves or trims. Refused by name before
  any op: `d' − e` under one frame ("would have to lose X s of its head to start at 0, leaving
  under a frame of it."); the trimmed span not meeting the anchor's (SY-4's sentence); a neighbour
  on the mover's track meeting the trimmed span or, when it is corrected and grows, `[S, S + d')`
  (SY-4's sentence). With `S + δ ≥ 0` nothing is trimmed and SY-10 stands.

- **SY-17 — Speech-only matching (AS-3's second fix pass; the owner's choice of 2026-10-15).** A
  search whose two stretches each hold at least 125 SPEECH frames (2 s) correlates their speech
  frames only: frame f of a file is speech when the cached Silero VAD probability of the chunk
  holding its centre, `cache/speech/<id>.bin` at `⌊(f·9600 + 19200)/19200⌋` (the frame's centre is
  256 samples at 8 kHz, 19,200 ticks, after its start; one chunk is 19,200 ticks), is at least
  0.5 (Silero's default, and `detect_silence`'s default `voice_confidence`); a mask is resampled
  onto the timeline grid as the frames are (frame k is source frame `round(k·speed)`). Each
  stretch is then standardised per coefficient over its own speech frames, and every other frame
  is 0, so only frames speech in BOTH stretches correlate; everything after the standardisation
  (SY-12's sum, z over every lag, SY-14's candidates and near placement) is unchanged. Otherwise,
  or when the model cannot be used this process (`SileroVAD.isAvailable` false), the search is on
  every frame, as SY-12 says. Each `sync_audio` row says which, `matched_on` ("speech" |
  "sound"). With the model available, a clip whose speech cache is not yet written is "still
  being analyzed" (amended by #526), as one with no features is. **Why the VAD and not an energy gate:** the app
  already caches Silero per media for `detect_silence` (road map 4), so a mask costs no new
  pass, and an energy gate would mark the owner's recorder rumble as sound. **The measurement**
  (a numpy reproduction of `search` over the S20 session's own `cache/sync/` and
  `cache/speech/`): the owner's true match is z 4.18 at 118.672 s unmasked (the app's own
  number), **7.92 at 118.688 s with both stretches masked** (next candidate 4.43), 5.50 with the
  recorder's mask only, 6.95 with the camera's only, and 4.12 when a pair is kept where EITHER is
  speech (it then loses to 113.856 s). The owner's recorder reversed, against 47 camera windows,
  reached at most z 6.04 masked. The owner's played windows hold 244 speech frames (the camera)
  and 248 (the recorder); REC2 holds no speech chunk, so S19 matches on sound, and the burst
  fixtures hold 0–1, so S1–S18, S22 and P13 match on sound. **Corrected by SY-28:** the 7.92
  "true match" is a false pair (two takes); SY-30 keeps speech-only matching on other evidence.

- **SY-18 — The two tiers (resolves SY-14's stop).** A search's choice (SY-14's shape) is
  CONFIDENT when its best candidate's z is at least 10 and 1.5 above the second (or there is no
  second) — `chosen_by` "confidence" — and WEAK when it is not but the near placement's z is at
  least 4 within 188 frames — `chosen_by` "placement"; otherwise nothing, and the refusal names
  the candidates (SY-14). The search order (SY-13) is unchanged: a played search that chooses
  either tier ends the search. A confident match applies as before. **A weak match is never
  applied silently** — the owner's reason: "Unrelated clips are never moved silently." AS-3's
  stop showed noise near a placement reaching z 4.6 and the owner's true unmasked match 4.2, so
  the near placement alone cannot tell them apart and a person must. A run's WEAK MOVES are its
  movers chosen by placement whose plan changes something (a non-zero delta, a trim, or a
  corrected drift); a weak mover already in place is not asked about. One tier decision serves
  both callers (`AudioSync.weakMoves`), so the menu and the tool cannot disagree. **Amended by
  SY-29, corrected by SY-28:** either tier stands only on a clear GCC-PHAT peak; "the owner's true
  unmasked match 4.2" was a false pair.

- **SY-19 — The Weak match sheet and `accept_weak` (the owner's choice of 2026-10-15).** Asked
  "When Synchronize Audio finds only a weak match, what should it do?", the owner chose **"Ask,
  then apply"**: "Strong matches apply as now. A weak match near where you placed the clip shows
  'Weak match: move the recorder 0.77 s (trim 0.77 s)? Apply / Cancel'. Over MCP the tool
  returns the candidate and applies only with an explicit accept_weak flag. Also add
  speech-only matching (it lifted your match from z 4.3 to 5.9). Unrelated clips are never
  moved silently." So: **the menu**, when a plan has weak moves, puts up one alert sheet on the
  editor's window — "Weak match: move “record.aifc” 0.77 s earlier (trimming 0.77 s off its
  head)?", its detail naming the anchor, each confidence, the 10 a match needs to apply on its
  own and the 3 s radius — with Apply (the default) and Cancel (Escape). Cancel changes nothing
  and makes no undo step. Apply commits the plan's ops as one grouped undo step ("Synchronize
  Audio") only when the project and the open scope are the ones the sheet was asked about;
  otherwise it beeps and puts "the project changed while the weak match was being asked about,
  so nothing moved. Choose Synchronize Audio again." at the inspector's foot. With no window, or
  a sheet already up, it beeps. **`sync_audio`** takes a new optional boolean `accept_weak`
  (default false). Every success answer carries `weak`, the clip ids of its weak moves; with weak
  moves and `accept_weak` not true it answers `{ok: true, moved: false, anchor, synced, weak,
  note, project}` — no op, no undo step, not an error — the note naming each move and saying to
  call again with `accept_weak: true`. With `accept_weak: true` it applies, as the sheet's Apply
  does. **An agent passes `accept_weak: true` only after the person has agreed to that weak
  match, naming the move** (the orchestrator's ruling): the catalog's description and the weak
  answer's note both say so, and there is no per-argument ask-first machinery in the assistant's
  lane (AI-7 names tools, not arguments); the edit is one undo step.

- **SY-20 — The GCC-PHAT refinement (round 2's AS-4; point 4 of the owner's "Go ahead").** Each
  chosen match's offset is refined on the two files' decoded samples (`cache/sync/<id>.pcm`, SY-11
  as amended). The REGION is the coarse overlap — the anchor timeline frames both clips play once
  the mover sits at the coarse delta — ×128, in anchor timeline samples, centred and capped at
  240,000 samples (30 s). Along the LINE `lag(a) = c + ρ·a` (a an anchor timeline sample at 8 kHz;
  c and ρ the measured drift's, SY-21, else c the coarse lag ×128 and ρ 0), the anchor's samples
  over the region and the mover's at `a·(1 − ρ) − c`, each read at `position·speed` of its file
  by linear interpolation (0 outside it), are correlated by band-limited GCC-PHAT: one zero-padded
  `vDSP_fft_zrip` each (the least power of two holding every lag), the cross-spectrum `X·conj(Y)`
  kept only on bins whose frequency `k·8000/n` lies in [300, 3,400] Hz (the speech band), each
  divided by its magnitude (0 under 1e-20), DC and Nyquist 0, and one inverse. Its z is taken over
  EVERY lag, as SY-12's. The PEAK is the highest r within ±384 samples (±3 feature frames, 48 ms)
  of the line; it is CLEAR when its z ≥ 8, it lies strictly inside the reach and it is strictly
  above both neighbours. A clear peak, refined parabolically (SY-3's ±0.5), shifts the line's
  intercept (or, not measured, the coarse lag) by its sub-sample shift, so the true lag is
  `line(a) + shift`. Without a clear peak, or with a region under 16,000 samples (2 s), or a slice
  all zero, the coarse value stands: the FALLBACK, which is a designed answer, not a failure.
  **Why only near the coarse lag:** GCC-PHAT whitens every bin, so any shared stretch can own its
  global peak however little of the speech it holds: round 2's analysis ran whole-file GCC-PHAT
  on the owner's files (`pcm.py`, the AS-3 handoff) and it was fooled by a burst, where the summed
  MFCC correlation found the owner's offset. PHAT is the refiner, never the finder. **The tier is
  untouched:** `confidence`, `chosen_by`, the candidates and SY-18's tiers are the coarse match's,
  and placement stays frame-snapped (SY-4). **The answer:** each `sync_audio` row's `offset` is the
  refined lag at the overlap's centre in ticks (the line's value there when drift was measured),
  and it adds `coarse_offset` (the coarse lag, ticks), `refined` ("phat" when the peak was clear,
  else "coarse"), `refine_confidence` (the peak's z; null when no refinement ran) and `drift_on`
  (SY-21). **Calibration rule:** `clearZ` 8 is initial. The positives (S1, S2, S8, S10, S19, the
  probe's planted delay in P16, and P17) must be clear, and the negatives (S22, S23, P16's
  unrelated pips) must not; on a misclassification only `clearZ` moves, to a value that classifies
  them all, every value tried recorded here and in the road map; when none does the phase stops and
  reports every printed z. S20 and S21 (the owner's files) are recorded, never calibration inputs:
  they have no 1 ms ground truth and hold only about 5 s of clear speech. **Calibrated (AS-4,
  Debug, 2026-10-16):** at 8, S23 (a null) read z 10.24 and was clear — a misclassification; 15 was
  tried and classifies every fixture (positives S1 433.8, S2 433.5, S8 433.9, S10 423.3, S19 131.5 and 187.9 (two runs),
  P16's planted delay 162.5, P17 514.1 and 516.0; negatives S22 4.03, S23 10.24, P16's unrelated
  pips 4.71). The owner's files read 9.00 (S20) and 9.01 (S21), so they keep the coarse offset.
  **Amended by SY-29, corrected by SY-28:** the refinement is now the gate — not clear, or with
  samples not run, refuses — its region falls back to the files' overlap under 2 s, and "the tier
  is untouched" no longer holds; S20's 9.00 and S21's 9.01 were PHAT reading a false pair
  correctly. **Amended by SY-32 (#302):** an overlap over 30 s gives the 30 s whose features
  agree most along the line, not its centre.

- **SY-21 — Drift on the features, each window refined by PHAT (supersedes SY-5's and SY-7's
  onsets; amends SY-6's units).** Drift's inputs are the readings' timeline-grid features and
  speech masks (SY-12, SY-17) and their samples (SY-20), the coarse lag in frames and the overlap O
  in anchor timeline frames. Under 3,750 frames (60 s) it is not measured, with SY-5's sentence
  ("the two play together for under 60 s, too short to measure drift."). Windows of 1,250 frames
  (20 s) start at O's start every `max(312, ⌈(|O| − 1250)/63⌉)` frames, plus one flush with O's
  end (at most 64). **Stage 1, the features:** each window is searched by `search` (SY-12, SY-17)
  against the mover's frames `[s − round(lag) − 62, s − round(lag) + 1250 + 62)` clamped to its
  file (the masks sliced alike), so every lag within the search overlaps the whole anchor window,
  its near placement taken within ±62 frames (0.992 s) of the coarse lag; a window whose near
  placement is missing or under z 6 is skipped. A kept window gives the point (its centre ×128,
  its near placement's lag ×128), in samples. When at least 3 windows are kept they pass through
  the ROBUST filter below; then SY-7's count rule (at least 3 windows, the count the survivors')
  then its span rule (their centres spanning at least (|O| − 1250)/2 frames), with their
  sentences, then an ordinary least-squares line F through the survivors. **Stage 2, PHAT:** each
  kept window is refined (SY-20) along F over its own samples (the window ×128); each CLEAR one
  gives the point (centre ×128, F(centre) + shift). When at least 3 are clear they pass through the
  same filter; when at least 3 survive and their centres span at least (|O| − 1250)·128/2 samples,
  those points are refitted by least squares; otherwise F stands. **The robust filter:** the
  Theil–Sen line (its slope b the median of `(yⱼ − yᵢ)/(xⱼ − xᵢ)` over every pair with xⱼ ≠ xᵢ, its
  intercept the median of `y − b·x`; a median the middle value, or the mean of the middle two),
  the residuals r about it and `MAD = median |r|`; a point is an inlier when `|r| ≤ max(3 × 1.4826
  × MAD, 1 sample)`. **Why the slice is wider** (the implementer's runs, 2026-10-16): with equal
  1,250-frame slices the overlap shrinks as `1250 − |d|` away from the coarse lag, and that
  triangular envelope pulled every window's peak toward it (about σ²/W, 0.02 frame): P7 read
  986.6 ppm for 999 (its `set_speed` 12.4 ppm off, P7 failed), P8's ×0.9999 and P12's +1,000 ppm
  cases failed, and P5's clean cases read 199.21, −148.83 and 95.88 ppm (for 199.96, −150.02,
  99.99). Widened: 200.18, −150.01, 0.05 and 99.99; P7 0.9990022 for 0.9990010 and 1.0010019 for
  1.0010010; P8 and P12 pass. **Why the robust filter** (the STOP of 2026-10-16): with the
  mover's frames 4,000–7,000 seeded noise (P5), the windows only partly in noise passed the z
  floor (z 12.8–16.9) with lag errors of 0.06–0.42 frame, and the least-squares line read 211.43
  ppm for 199.96; no window floor short of the clean windows' own z band (17.3–17.7) helped.
  Fitting each point at its window's matched-sound centroid read 209.68 (the error is the noise's,
  not the point's place), so it was not taken. Theil–Sen with MAD inliers read 201.06 (15 of 21
  windows); −150 ppm with noise −150.09, a 2,000–3,500 gap 201.10, +1,000 ppm with noise 998.47,
  noise at the end 202.06; every k from 2 to 6 passed and 7 or more failed (5.79 ppm off). **Units:** ρ is samples per sample and c samples
  at anchor timeline sample 0; `ppm = ρ·10⁶`, `milliseconds = ρ·|O|·128/8`, and
  `errorMilliseconds` the slope's standard error × √(1250/step) (when the step is under 1,250) ×
  |O|·128/8. **The answer** adds `drift_on` ("features" | "phat"; null when not measured) and
  `drift_windows` (the windows the line was fitted through; null when not measured). **Calibration
  rule:** S10's 2 ms, S17's 2 ms, P5's ±5 ppm and S18's 3 ms stand; on a miss only the window floor
  `driftWindowZ` (6) may move, every value tried recorded here; a miss that no value fixes stops
  the phase. The inlier scale k (`driftInlierScale`) is FIXED at 3 and the floor at 1 sample: a
  miss is a stop, never a new k (the measured passing band, 2–6, is recorded above). **Measured
  by SY-33 (#304):** a z²-weighted stage-1 line and a span fallback were tried on a late unrelated
  stretch and neither corrected it; stage 1 is unchanged.

- **SY-22 — The call's cost and its background run (AS-4, the orchestrator's ruling of
  2026-10-16).** **The budget:** a whole sync of a one-hour pair — the cached features and samples
  of both files loaded, then `plan` — costs at most 1.5 s of CPU on Release (-O, whole module),
  measured by the probe's P19 behind `--cost` on a generated one-hour pips pair (written under the
  gitignored `tools/proof/work/audio-sync/cost/` and removed after). The designer's scratch
  measurement (host load 36–76): `plan` 2.177 s, of which drift 1.803 s over 64 PHAT windows; one
  30 s refine 27.3 ms of which `vDSP_create_fftsetup` (log2n 19) was 24.0 ms; each file's `.bin` and
  `.pcm` load 0.035 s. **The reuse:** `plan` makes ONE `AudioSyncPHAT.FFT` (a vDSP setup of log2n 19,
  524,288 ≥ 2 × 240,000 − 1) before its movers and lends it to every drift window's refinement and
  the final one; each correlation still transforms at its OWN least power of two, so its bins, r, z
  and SY-20's `clearZ` are unchanged; with it the scratch `plan` was 0.891 s. `summedCorrelation`
  keeps its own setups. **The background run:** `read` stays on the main thread (it reads the
  document; its loads are cheap) and `plan`, pure, runs on a background queue. **The menu** puts up
  a Synchronizing Audio sheet ("Matching the sound of N clips…", an indeterminate bar, "Nothing
  moves until the match is found; Cancel leaves everything as it is.", Cancel) while `plan` runs,
  so the window never beach-balls and every editor action, Synchronize Audio included, is disabled
  while it is up; Cancel drops the late answer and changes nothing. When the answer comes, the
  sheet goes, and it is applied only when the document's project and scope are still the ones
  `read` took (the weak sheet's test, SY-19); otherwise it beeps and puts "the project changed
  while Synchronize Audio was matching, so nothing moved. Choose Synchronize Audio again." at the
  inspector's foot. A weak answer then asks as SY-19 says. **`sync_audio`** joins the server's
  off-main tools: the read and the stale test run on the main thread, `plan` on the server's thread,
  and a project changed meanwhile is the error "the project changed while Synchronize Audio was
  matching, so nothing moved. Call sync_audio again."; the call still blocks until it answers.
  The lane admits one call at a time, so no script can edit during one: the MCP stale test is
  proven by no row. **The dev hold:** a Debug or Release build's dev-only launch default
  `-RCDevSyncHold <seconds>` holds the menu's background run that long before `plan`, so a proof
  can reach the sheet (S25 edits under it, S26 cancels it); Distribution has no such default.
