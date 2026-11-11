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
