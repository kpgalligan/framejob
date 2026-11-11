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
