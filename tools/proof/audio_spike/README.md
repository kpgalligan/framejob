# Road map "audio" AP0 — the spike's records and instruments

Each folder holds one spike's `record.md` (its rule, written before its runs, then what was measured
and its verdict), the logs it printed, and the scripts it wrote. They ran in a scratch folder against
the tree at `9e47f56`; copies of product code they compiled are not kept here
(`git show 9e47f56:<path>` gives them back), nor are their audio files and binaries. The verdicts are
folded into `designs/audio.md`'s AP0 record, which is what a phase reads.

| Folder | Question |
|---|---|
| `S1/` | Frame Job's own DSP or Apple's units (EQ, limiter, dynamics) inside the live `MTAudioProcessingTap` |
| `S2/` | `AUSoundIsolation` on the owner's recording: driving it, latency, determinism, quality, de-reverb |
| `S3/` | Track and master processing in the preview, a true-mix meter, multitrack stems |
| `S4/` | A per-media loudness cache: block size, format, accuracy against the export's meter |

These are historical instruments, not proofs: nothing in `make test` runs them.
