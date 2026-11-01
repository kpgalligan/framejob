# Samples

Real recordings the owner made for working on Frame Job's handling of real material, as
opposed to the synthetic media `tools/proof/` generates with ffmpeg. A proof, a manual
check or a decision may name one; each row says what the file is and what it measures, so
a change that claims to improve it has a before to compare with.

| File | What it is | Measured |
|---|---|---|
| `Rode-usb-mic.m4a` | Speech recorded on a RØDE USB desktop microphone, 2026-10-30: clean but quiet (spec §11 AU-1). | 30.4 s, AAC-LC mono, 48 kHz; peak −18.6 dBFS (true peak −18.5 dBTP), integrated −44.7 LUFS, LRA 21.1 LU (ffmpeg `volumedetect`, `ebur128=peak=true`) |
