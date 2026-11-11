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
