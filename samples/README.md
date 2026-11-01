# Samples

Real recordings the owner made for working on Frame Job's handling of real material, as
opposed to the synthetic media `tools/proof/` generates with ffmpeg. A proof, a manual
check or a decision may name one; each row says what the file is and what it measures, so
a change that claims to improve it has a before to compare with.

| File | What it is | Measured |
|---|---|---|
| `Rode-usb-mic.m4a` | Speech recorded on a RØDE USB desktop microphone, 2026-10-30: clean but quiet (spec §11 AU-1). | 30.4 s, AAC-LC mono, 48 kHz; peak −18.6 dBFS (true peak −18.5 dBTP), integrated −44.7 LUFS, LRA 21.1 LU (ffmpeg `volumedetect`, `ebur128=peak=true`) |

## Kept outside git

The owner's recordings for road map "creator-jobs" live in `tools/proof/media/creator/<ID>/`,
gitignored by `tools/proof/.gitignore`'s `media/`, and are never committed (they carry the owner's
face and voice); the road map's "Samples the owner supplies" says what each measures.

| Sample | Lives in | What it is | Recorded |
|---|---|---|---|
| S-TH1 | `tools/proof/media/creator/S-TH1/` | A talking head, one person, GH5 in Rec. 709, 4K 30, about 6 min, with retakes, false starts, fillers and leaving the frame, the RØDE as its own file | not yet |
| S-TH2 | `tools/proof/media/creator/S-TH2/` | The same set-up on the GH5 in V-Log L, 4K 25 10-bit, about 2 min | not yet |
| S-TH3 | `tools/proof/media/creator/S-TH3/` | 1 min on the iPhone 18 Pro in Apple Log | not yet |
| S-TH4 | `tools/proof/media/creator/S-TH4/` | The iPhone 18 Pro at its defaults (HDR, HLG, variable frame rate), 1 min landscape and 20 s portrait | not yet |
| S-TH5 | `tools/proof/media/creator/S-TH5/` | 1 min of hard cases for person segmentation: backlit, busy background, turned away, small in frame | not yet |
| S-KEY1 | `tools/proof/media/creator/S-KEY1/` | The owner before an evenly lit plain green or blue cloth, 1080p30, still, gesturing, turning and leaning out | not yet |
| S-RT1 | `tools/proof/media/creator/S-RT1/` | The retake script in `tools/proof/retake_spike/SCRIPT.md`, read on the RØDE, 3–5 min | not yet |
| S-ST1 | `tools/proof/media/creator/S-ST1/` | A screen tutorial with the camera beside it, made with today's recorder, 5–8 min | not yet |
| S-ST2 | `tools/proof/media/creator/S-ST2/` | After CU1b: a narrated screen tutorial, 10–20 min, Cursor In the picture | not yet |
| S-ST3 | `tools/proof/media/creator/S-ST3/` | After CU6: the same kind of recording with Record shortcuts on | not yet |
| S-ST4 | `tools/proof/media/creator/S-ST4/` | A window recording whose window is dragged and resized while recording | not yet |
| S-ST5 | `tools/proof/media/creator/S-ST5/` | With a second display: a recording of one display while the pointer visits the other | not yet |
| CU12's recording | `tools/proof/media/creator/CU12/` | A real narrated tutorial, 10–20 min, Record shortcuts on, a camera beside | not yet |
| S-PC1 | `tools/proof/media/creator/S-PC1/` | Two people, two cameras and a microphone each, 15–20 min with crosstalk and laughter, with `turns.json` | not yet |
| S-PC2 | `tools/proof/media/creator/S-PC2/` | Two people sharing one microphone, a camera on each, 5–10 min, with `turns.json` | not yet |
| S-PC3 | `tools/proof/media/creator/S-PC3/` | Two people in one wide shot, a microphone each, 3–5 min | not yet |
| S-MT1 | `tools/proof/media/creator/S-MT1/` | An OBS screen recording with three audio tracks, as `.mkv` and as Hybrid MP4 | not yet |
| S-MT2 | `tools/proof/media/creator/S-MT2/` | A recorder's or mixer's multichannel file, or a wireless kit's two people in one stereo track | not yet |
| S-IP1 | `tools/proof/media/creator/S-IP1/` | A short iPhone 18 Pro clip with Spatial Audio on | not yet |
| S-EV | `tools/proof/media/creator/S-EV/` | About 8 min of the owner talking while someone off-mic laughs, claps and cheers, with a list of each event's start | not yet |
| S-MU | `tools/proof/media/creator/S-MU/` | 2 min of the owner talking over a music bed | not yet |
| S-LONG1 | `tools/proof/media/creator/S-LONG1/` | A recording of an hour or more | not yet |
| T1's and T2's exports | `tools/proof/media/creator/T1-T2-exports/` | Each trial project's 16:9 export, re-imported as one flattened clip | not yet |
