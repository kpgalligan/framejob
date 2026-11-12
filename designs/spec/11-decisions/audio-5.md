# Spec §11 — decisions: Audio, the step meter onward

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the AU- series of [`audio.md`](audio.md), so a citation never has to say which
file; that file names the condensed record and the original. This file holds AU-160 on.
It is new because [`audio-4.md`](audio-4.md) had reached the spec's ~500-line split rule
(2026-11-11).

- **AU-160 — A step's energy is summed once per step (#567, #557, 2026-11-11; amends AU-64
  (i)).** R5 failed under load with three equal loudnesses to three decimals. Made to say what
  differed, it failed on run 12 of a soak under other builds: render 2 against 1 and 3 (which
  were equal), 360 of 6,950 steps from 14.00 s, each by one unit in the last place of the
  energy, no step peak different, the isolated render's bytes unchanged. The cause was the
  meter, not the render: `StepLoudnessMeter` added a step's squares one `vDSP_svesqD` per `feed`
  chunk, so the last bit followed where the reader cut its buffers, which moves under load
  (R7 on the old sources: 13 of 300 steps differ fed in 4,096-frame buffers, 49 fed unevenly).
  Now a step's K-weighted samples are kept and summed once, in sample order, when it closes;
  every step's last bits moved once, and the export's pass-one steps (AU-28) are the same
  meter. "Byte-identical" stays AU-64 (f)'s and (i)'s claim, with no tolerance: R5 as it was
  (its detail now naming each differing pair, the count, the first step, both values and the
  largest dB, and whether the re-made isolation file is the same bytes), R6 the comparison, R7
  the meter fed four ways, mutant M19; the soak (`--soak-r5`) then passed 25 minutes under load.
- **AU-161 — The player's filler is a mark, and a stop is resumed from the stream (#405,
  2026-11-11; amends AU-70's skip rule, AU-72, AU-67 (e) and AU-78).** Measured on a Debug
  build with every tap callback logged (1,044 buffers, two tracks, a first play, seeks, pauses
  of 0, 6 and 12 s): the player hands a tap two kinds of buffer. AUDIO has a numeric time range
  with a duration. A FILLER is silent (peak 0.0 in every one) with a duration of zero or not
  numeric, and no audio buffer had either. There are three fillers: one with no time at all
  before a stream's first audio (the first play, and a play after about 5 s paused), which
  AU-70 already skips; one at the frame the track's stream stands at, about twelve a second
  while paused, for about 5.3 s (62 or 63 a track) and then none; and one or two at a seek's
  frame T, each track's after its own stale fillers of the old position, not in step across
  tracks. After any restart a track's audio begins past the frame its filler named: 3,072
  frames after a seek and after a pause on one track, 2,560 to 7,167 on the other.
  The meter placed a timed filler as 4,096 frames of the media: after a seek it summed silence
  over [T, T+4096) and dropped the audio that overlapped it (L2's new comparison read 0.0654 LU
  low). And pause and continue did not reset only by accident: the audio came back 6,144 to
  7,168 frames past the frame the sum had reached, outside `aheadTolerance`, and was not a
  jump only when the pause's fillers reached the sum first and bridged it; after a 6 s pause
  they did not, and the meter reset (`jump`), against AU-72.
  (a) **A filler is a mark.** The tap tells a filler by its time range having no duration
  (`sourced` false). One with a numeric time is written to the ring as a MARK: its first frame
  and its length in frames, a header and no samples, so a pause's fillers claim no ring frames
  and cannot overrun it. One with no time is skipped, as before. The chain and the per-track
  bars see a filler as they did.
  (b) **A mark is asked AU-72's questions as the silence it was, and is summed nowhere.** It
  moves or continues its track by its frame, and what follows continues it over its length
  (the tolerances as they were, from the mark's end), so a seek's mark is the track's move and
  the jump; a track awaiting its move counts a stale mark's length. A mark says the track has
  delivered TO its frame and nothing past it: the measurement after a seek begins at the first
  frame of audio (`from_frame` is that frame, not the seek's), and a track whose audio begins
  later is silence until it does, AU-70's rule for what a track delivers. With the sum not yet
  begun after a reset, a track that has already moved (its mark in an earlier tick) is not put
  back to awaiting by another track's move, and what it hands over in that tick is kept.
  (c) **A stop is resumed from the stream.** A stop that ends a measured play (AU-72) leaves
  each track RESUMING until it next delivers audio. While resuming, a chunk that continues the track's own stream (what it
  delivered last, a mark's length included, within the same tolerances) is not a move, however
  far the stop left the sum behind it: pause and continue does not reset after any pause. The
  frames between the frame the sum reached and the first audio after the pause read as
  silence, as they did when the fillers bridged them (what the stop dropped, and the player's
  restart). Audio more than `aheadTolerance` past the stream is still a jump, and a track that
  played at another rate since or before the stop is not resuming (its stream ran on
  unmeasured), so a play at ×1 after it is the jump it was. AU-72's tolerances do not change.
  What a stop drops (its own drain, and what a tick at rate 0 took from the rings before it)
  moves a track's stream only where it continues it: a chunk that does not, such as the marks
  of a seek made while paused or just before the stop, is another position and is not taken as
  the stream, so the audio after it is a move and is asked AU-72's rule against the sum, as it
  was before this decision (the diff read's finding: a second stop had taken a seek's marks as
  the stream, and the play after it was resumed, the gap summed as silence in one step).
  (d) **The proofs.** `audio_ap7_proof.py`: T17 (the tap: a filler is a mark with none of its
  samples, audio is audio, no time is nothing, 63 fillers overrun nothing), T18 (the measured
  deliveries in the sum: the seek, pause and continue, the long pause, the tolerance kept, a
  seek drained by a stop, a tick at rate 0, the other rate), ten mutants (twenty-one in all), L2 also holds the seek's play within
  0.01 LU of L1's export, and L3 plays a third time after 6 s paused, and a fourth after a seek made while paused. `audio_ap6b_proof.py` P3's seek row is absolute again, within
  0.01 LU, its control gone (AU-67 (e)). SE-30 stays the person's check.
- **AU-162 — A live retimed segment can pass its clip limiter's ceiling (#399, 2026-11-11;
  amends AU-20 and AU-22).** #399 read +0.73 dBTP on a clip at ×1.5 with Keep pitch on whose
  limiter was at −1, and guessed the time-pitch runs after the tap. Measured before anything
  was written (`audio_ap6_proof.py` V17, the owner's recording, a gate and the limiter at −1
  dBTP, Loudness Normalize to −18, the deciding run on Debug): the guess holds. AU-55's two
  kinds of retimed segment differ.
  - **RENDERED** (a Speed action, or a constant speed with Keep pitch off): the tap is handed a
    ×1 file that is already retimed, so the limiter holds it. ×1, ×1.5 and ×0.75 with Keep
    pitch off and a Speed Dip to ×0.7 with Keep pitch on each read −1.0000 dBTP in the solve's
    verify render and at most −0.9998 dBTP in the pre-master stem.
  - **LIVE** (a constant speed with Keep pitch on): AVFoundation scales the segment inside the
    composition, after the tap. In every live leg the tap's own output held the ceiling (the
    live meter's true peak over a preview play around the stem's largest sample, AU-70:
    −1.0000 dBTP), and what came out of the composition did not: +0.4325 dB over the ceiling at
    ×1.5, +1.1493 dB at ×0.5, and +1.7293 dB at ×1.5 on #399's own chain (noise reduction 0.5,
    Enhance's gate and compressor, target −16), which is #399's +0.73 dBTP to the digit. ×1.02
    (`time_domain`, SY-26) read 0.0000 dB over. The stretch re-shapes the peaks the limiter
    held, and it can lower them as readily: the same ×1.5 leg at a −20 target read 1.6573 dB
    UNDER the ceiling, and the solve gives the volume back. Two renders of one clip can also
    differ (#337's two outcomes), so a figure is its run's.
  - **Accepted, and why.** No tap can run after the scaled edit, and SY-41 rules out Frame Job's
    own time-stretch; rendering a live segment offline so the tap sees it would move every Keep
    pitch clip onto SR-13's unit, with its lead and SR-15's lateness, which is not this fix. The
    export's master limiter holds the file (AU-27, AU-28: every leg's export ≤ −1 dBTP by both
    meters); the preview has no master (AU-73) and a stem does not go through it (AU-108
    (e)), so both can pass the ceiling. Loudness Normalize and Enhance Voice report the figure as
    `result_true_peak_dbtp` and do not correct for it.
  - **The proof.** V17: every leg scores that its reading is a verify render's (renders ≥ 2,
    `limited_by` null), that the limiter has 3 dB or more to take off, that the export holds
    −1 dBTP and that the tap's output holds the ceiling in the preview; the rendered legs also
    score the verify render and the stem at the ceiling; the live legs' margins are printed
    and never scored, as V12's is. Two mutants: the limiter dropped from the clip's chain
    (`AudioTapSchedule.swift`) fails the tap row of every leg and the ceiling row of every
    rendered leg; the gate dropped from leg (a)'s chain fails its `renders` clause (the model's
    capped figure would otherwise pass).
- **AU-163 — A sub-block's energy is summed once per sub-block (#569, 2026-11-11; extends AU-160
  to `LoudnessMeter`, amends nothing).** `LoudnessMeter` had AU-160's shape: one `vDSP_svesqD`
  per `process` chunk added to the 100 ms sub-block's sum, the channels added chunk by chunk.
  `feed` already cuts at sub-block boundaries, so only a reader buffer ending inside a sub-block
  changed the arithmetic. R8 on the old sources, 3 s of noise against the same sound fed whole,
  sub-blocks differing by a unit or a few in the last place (largest 4.3e-15 dB): stereo 28 of 30
  in 4,096-frame buffers, 25 of 30 in 1,024-frame ones, 24 of 30 fed unevenly; mono 27, 29 and
  28 of 30. The integrated, momentary and short-term figures of that programme were the same
  bits (the difference rounded away in the mean and the logarithm), and so were both peaks.
  - **The rule.** A sub-block's K-weighted samples are kept per channel and their squares added
    in sample order, each channel and then the channels, when the sub-block closes: one sum per
    sub-block, whatever chunks filled it. A scalar loop, as AU-160's, so the sum is defined by
    the source and not by a routine's blocking.
  - **What moved.** Every sub-block's last bits, once, for every feeding (a whole sub-block was
    one vector sum before): the export's `integrated_lufs`, the unmodelled export gain's input
    before its rounding, the live meter's M, S and I. True peak and sample peak not at all: they
    were never per-chunk sums.
  - **What is the same.** A trailing partial sub-block is still discarded; no format, no cache,
    no persisted value (the loudness cache is `LoudnessBlocks`, not this meter).
  - **The proof.** `audio_ap6b_probe.py` R8 (the sums through `shortTermSubBlockSums`, and the
    three loudness figures, bit for bit across five feedings, stereo and mono; the peaks
    compared and printed, not scored) and mutant M20, the per-chunk sum restored.
- **AU-164 — The loudness cache's records do not follow the reader's buffers, so its block sums
  stay per cut (#595, 2026-11-11; amends nothing).** `LoudnessBlocks` (AU-10, AU-63) adds a
  block's sums once per cut of a reader buffer: one `vDSP_svesqD` or `vDSP_dotprD` into Σ y²,
  Σ yL·yR and the high band's three, AU-160's and AU-163's shape, so a block a buffer ends inside
  is the sum of two vector sums. What the cache keeps is `Float(sum / n)`, and its contract is
  those Float32 records. C14 fed 3 s of noise whole, a block at a time, in 4,096 and 1,024 frames
  and unevenly: the Double sums differed in their last bits (stereo at 48 kHz 135, 522 and 428 of
  1,800; mono at 48 kHz 44, 169 and 138 of 600; mono at 44.1 kHz 34, 161 and 126 of 600) and not
  one Float32 value moved (0 of 2,400 or of 900 in every feeding, true peaks included); fed a
  block at a time, the sums were the whole's bits. The product's own pass over C1's 30 s stereo
  fixture (178 reader buffers, 166 of them ending inside a block) left 575 of 18,216 Double sums
  different from the same PCM fed in one buffer, and its 24,288 Float values the same bytes.
  - **The rule.** The per-cut sums stay and `loudnessVersion` stays 2: no record a cache writes
    was seen to move. By argument, a difference of k units in a Double's last place moves the
    rounded Float only when the value lies within k units of a Float rounding boundary, about
    k·2⁻²⁹ of the time, which is why no feeding moved one.
  - **What would reopen it.** A C14 failure, any feeding's bytes differing from the whole's;
    then AU-163's rule is applied here (a block's weighted and high-band samples kept per
    channel and summed once in sample order when it closes) and the version moves to 3.
  - **The proof.** `loudness_cache_probe.py` C14, through `LoudnessBlocks.blockSums`: the bytes
    scored for every feeding of three programmes and for the product's pass, the block-at-a-time
    feeding's Double sums scored bit for bit, the other Double counts printed; mutant
    `weighting-state-per-buffer` (the K-weighting state started afresh at each buffer) fails it.
- **AU-165 — An action's end that sets a limiter is measured by render (#402, 2026-11-12; amends
  AU-64 (a), (e), (g) and AU-159 (a), (b), (g)).** The owner's decision on #402: one more
  render whenever an action's end sets a limiter, so Normalize is measured as it will play. An
  action end's limiter takes its threshold from the base volume (AU-22), so R0 at volume 1 does
  not say how it bites at the solved one. On the tree before this entry (`audio_ap6_proof.py`
  V16 on Debug, the owner's recording): (g) an end gate and limiter at −24 dBTP, no limiter on
  the clip, target −30, answered after R0 alone (`renders` 1, `result_lufs` −30.00) and
  exported at −32.57 LUFS, At volume showing −30.0 with no "≈"; (h) an end limiter at −12 dBTP
  alone planned off the cache (`processed_lufs` null, `renders` 0); (i) the target that puts
  R0's true peak at −1.3 dBTP at the plan's volume (−24.417) answered −24.42 and exported at
  −28.47; (j) the clip's limiter at −1 dBTP keyed off at an action's end planned off the cache,
  the model's limiter running over the whole clip.
  (a) **Which clips render.** `needsRender` is also true when an action of the clip with a
  duration above 0 has the `limiter` key at its end (`ProcessedLoudness.endSetsLimiter`): a
  limiter, or a null keying the clip's own off. The cache's model runs only the clip's own
  limiter, over the whole clip (AU-24, AU-26), so it sees neither; AU-159 (a)'s rule, a render
  rather than a miss, covers both. The memo's key already names the same ends (AU-159 (g)).
  (b) **The verify.** The solve verifies by render when the plan sets a limiter OR the clip has
  such an end (`LoudnessMeasureRun.verifiesByRender`). With no limiter the verify trial is the
  chain with `{volume: v, limiter: null}`, the same loop, tolerance and bound as AU-64 (e).
  Each volume the loop steps to is first asked AU-24's question on R0's reading: when R0's true
  peak × that volume passes −1 dBTP (`LoudnessMeasureRun.limiterGoesOn`), the limiter goes on —
  AU-24's choice, the default at −1 dBTP — and the loop starts again where AU-24's plan starts
  it under that limiter (its model's volume on R0's steps), with three verify renders of its
  own. The challenger's reason: an end limiter bites harder as the volume rises, so the loop
  steps up, and the sound before the action is unlimited and rises with it; answering
  `limiter: null` there would break AU-24's ceiling. Starting again is a second press's own
  path (R0 is the same and the plan reads the clip's limiter), so a second press is still an
  identity (AU-64 (f)). A volume the plan chose was asked by the plan, so a `limiter: null`
  answer never stands at a volume where R0's peak passes the ceiling. The answer is the last
  render's volume, limiter, loudness and true peak; `renders` counts R0 and every verify.
  (c) **At volume.** On a clip with such an end, the last verify render that answered a press
  (`ProcessedLoudness.Verified`, beside the R0 it began from in the memo, dropped by the next
  R0 for its key) when the clip's base limiter equals the one it rendered and its base volume
  is within 0.05 dB of it (AU-64 (f)'s figure, so a kept volume still reads it); otherwise "≈"
  before R0's figure at the base volume through AU-26's model, its tooltip "≈ an action's
  limiter has not been measured at this volume; Normalize or Enhance Voice measures through
  it.", or before the cache figure with AU-64 (g)'s tooltip when there is no R0. No model of an
  action's limiter is added and nothing measures in the background (AU-64 (g)). A clip with no
  such end reads as AU-159 (g) says.
  (d) **Where it shows.** `normalize_clip`'s description and the site's Normalize and Clip
  volume pages. Loudness Normalize, `normalize_clip`, Match Loudness and Enhance Voice share
  the run; Enhance always sets a limiter and so already verified.
  Proof: `audio_ap6_probe.py` E10 (a limiter and a null limiter at an end render), E15
  (`endSetsLimiter`, `verifiesByRender`), E16 (`Verified.holds` and the memo), E17
  (`limiterGoesOn`) and mutants M21–M26; `audio_ap6_proof.py` V16 (g)–(j), and by hand the
  restart mutated to carry on at the stepped volume, which made (i)'s second call change the
  volume. After it, on Release (the whole proof, 81 of 81): (g) four renders, `result_lufs` and
  the export −30.25 (three verifies, short of the loop's 0.1 LU; the bound is AU-64 (e)'s),
  At volume −30.2 with no "≈" and "≈" at the volume ×1.2; (h) two renders, −32.00 both; (i)
  the limiter on at −1 dBTP, five renders, −28.60 both at a true peak of −3.48 dBTP, a second
  call "made no change"; (j) two renders, −19.96 both.
- **AU-166 — An overwrite can end a locked partner's link (#589, 2026-11-12; beside AU-92,
  amends AU-91's "stays linked").** `overwrite_clip` onto a linked sound whose picture is on a
  locked track cuts the sound twice and leaves the picture whole. Each cut applies AU-92 to the
  uncut picture: it is linked to the half sharing more of its time, the first on a tie. When
  the piece it names after both cuts is the one the overwrite removes, `settle_links` clears
  the link and nothing moves it to a surviving piece. The owner's decision (2026-11-12, the
  recommended option): leave it, the pair is over, as for an unlocked partner, whose piece
  beside the new file stays and is no longer linked; re-linking was declined because it needs
  a locked track to arise and would pick one of two leftovers by a tie rule nobody would
  predict. Because the rule runs per cut, the answer is not "the longest surviving piece": with
  pieces L, M (under the new file) and R sharing the picture's time, the first cut keeps L when
  L ≥ M + R, else the second keeps M when M ≥ R, else R. So L 2, M 2, R 2 s ends unlinked, and
  so does L 2.5, M 2, R 1.5 s, though L is the longest; L 1, M 2, R 3 s keeps R; and a file
  ending where the sound ends (L 4, M 2 s, one cut) keeps L. Locks still win: the picture is
  not cut, moved or deleted. Pinned by `core/tests/link_edges.rs`'s
  `an_overwrite_leaves_a_linked_picture_on_a_locked_track_whole` (2, 2, 2 s) and
  `an_overwrite_keeps_a_locked_pictures_link_only_where_its_cuts_leave_it` (the other three);
  the site's Overwrite section says so.
- **AU-167 — `limited_by` names a solve the verify renders left away from its target (#607,
  2026-11-13; amends AU-64 (e)).** AU-64 (e) ends the verify loop after three verify renders and
  named only the ×32 stop, so a solve the bound stopped more than 0.1 LU from T answered its last
  render's honest `result_lufs` with `limited_by` null and no note: on Release (AU-165's record)
  V16 (i), an action-end limiter at −24 dBTP holding most of the clip, answered −28.60 against
  −24.417, and (g) −30.25 against −30. The owner's decision (2026-11-13, the issue's option 1):
  the answer names the miss and its likely cause, in Normalize, Enhance Voice and Match Audio
  alike.
  (a) **The rule.** After the verify loop, `limited_by` is `max_gain` when the volume is at ×32
  and the last R is under T − 0.1 (AU-64 (e)'s, unchanged and tested first); else
  `verify_renders` when the last R is more than 0.1 LU from T; else null
  (`AudioNormalize.verifiedLimit`). These are AU-64 (e)'s own tolerance and bound, so the value
  is set exactly when the loop stopped on its third verify render. The loop's step is not
  one-sided, so a last R can be over T as well as under it; the rule says "from", and at ×32 a
  last R more than 0.1 LU over T is `verify_renders` too. The issue's "below ×32" is read as
  "not the ceiling's stop": that miss is not the ceiling's, and null would be the defect again.
  (b) **The other paths are unchanged.** A clip with no limiter and no action-end limiter takes
  R0 + 20·log10 v (no verify render, exact), and a clip planned off the cache takes AU-24's
  arithmetic or `AudioLimiterModel.gain`, which is short of T only at ×32; both keep `max_gain`
  or null.
  (c) **Where it shows.** `limited_by` in `normalize_clip`, `enhance_voice` and `match_audio`
  (one run, AU-123). Their `note`, built once (`AudioNormalize.limitNote`), keeps the ceiling's
  sentence byte for byte for its clips, names the verify bound's clips in a second sentence with
  `verify_renders` and the usual cause (a limiter holding the sound down harder as the volume
  rises), then "result_lufs says where each landed." once. Enhance's loudness reason keeps the
  ceiling's clause for `max_gain`, and for `verify_renders` ends ", short of T" (or ", over T")
  with the same cause. The three tools' descriptions and the site's MCP audio page and its
  Normalize, Enhance Voice and Match Audio pages say it. The button, the menu and the Match sheet
  say nothing, as they say nothing of a skip.
  (d) **Declined.** More verify renders (the issue's option 3): in (i) the limiter holds the
  sound and more renders would not reach T, and each one renders the whole clip.
  (e) **Left as decided.** At ×32 the answer stays `max_gain`, with the ceiling's note, even when
  an action's limiter is what held the last render under T and no volume would reach it: the
  owner's option bounds the new value to the loop's own stop below the ceiling.
  Proof: `audio_ap6_probe.py` E18 (the rule's arms on both sides of 0.1 LU and at ×32, the note
  by case with the ceiling's sentence byte for byte, Enhance's reason by case) and mutants
  M27–M31 (the threshold at 1 LU, the bound answering nil, the bound before the ceiling, the
  note and the reason giving every limit the ceiling's words), all killed; `audio_ap6_proof.py`
  V16 (g), (i), (k) (`match_audio` on (i)'s clip) and (l) (`enhance_voice` −24 on (g)'s clip),
  and `limit_of`, the rule from a row's own figures, where V2, V13 (c), V16 (f) and V17 asserted
  null. On a Debug build of the tree before this entry, five rows failed: (f) −20.11 against −20
  after four renders, (g) −30.249, (i) and (k) −28.595 at volume 28.37 after five, (l) −29.551 at
  20.84 after four, each with `limited_by` null and no note, and (l)'s reason ending at its
  renders. With it, `AP6_ONLY=actions` 21 of 21 on Debug, each of them `verify_renders` with the
  note. Enhance at −16 and −20 on (g)'s clip climbed to ×32 at −29.12 and answered `max_gain`
  ((e)).
