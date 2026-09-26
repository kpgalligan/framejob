# The silence spike — road map 4, S0 (2026-09-13)

Three programs, run from a shell (so under the terminal's TCC attribution,
as every proof is), whose output `archive/reelcut-roadmap-4.md` §2 quotes.
None is a proof; each is an instrument, tracked so the numbers in that
document can be reproduced rather than believed.

| Program | Answers | Build |
|---|---|---|
| `level_apple.swift` | q1 the shipped rule on a real file, q2 an adaptive threshold, q3 `SpeechDetector` (file mode), q4 the transcriber's word ranges, q5 SoundAnalysis at 0.5 s | `xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 level_apple.swift -o level_apple` |
| `separation_streaming.swift` | q5 SoundAnalysis at 0.5 s and 1.0 s (gaps and separation), q3 `SpeechDetector` (streaming) | same line, its own name |
| `silero_coreml.swift` | q6 Silero v6.2.1 through Core ML, q7 the real mixed recording | `xcrun swiftc -O -target arm64-apple-macos26.0 silero_coreml.swift -o silero_coreml` |

## Fixtures

The clean fixture, and its ground truth (the −40 dBFS level run on digital
silence: 2.72–4.29 and 6.68–7.81 s):

```sh
say -o speech.aiff "The quick brown fox jumps over the lazy dog. [[slnc 1200]] Pack my box with five dozen liquor jugs. [[slnc 800]] How vexingly quick daft zebras jump."
```

The five mixes. This ffmpeg's `sine` sits at −21 dBFS (`tools/proof/README.md`),
so `volume=-14dB` on it is a −35 dBFS hum; the document names each by its
MEASURED floor (p10 of the 10 ms peak buckets), which the programs print.

```sh
ffmpeg -y -v error -i speech.aiff -af "volume=-30dB" -ar 48000 quiet.wav
ffmpeg -y -v error -i speech.aiff -f lavfi -i "anoisesrc=color=pink:sample_rate=48000:duration=11:amplitude=0.0008" \
  -filter_complex "[0]volume=-35dB[s];[s][1]amix=inputs=2:duration=first:normalize=0[o]" -map "[o]" -ar 48000 quiet2.wav
ffmpeg -y -v error -i speech.aiff -f lavfi -i "sine=frequency=120:sample_rate=22050:duration=11" \
  -filter_complex "[1]volume=-45dB[h];[0][h]amix=inputs=2:duration=first:normalize=0[o]" -map "[o]" -ar 48000 hum.wav
ffmpeg -y -v error -i speech.aiff -f lavfi -i "sine=frequency=120:sample_rate=22050:duration=11" \
  -filter_complex "[1]volume=-30dB[h];[0]volume=-20dB[s];[s][h]amix=inputs=2:duration=first:normalize=0[o]" -map "[o]" -ar 48000 hum2.wav
ffmpeg -y -v error -i speech.aiff -f lavfi -i "sine=frequency=120:sample_rate=22050:duration=11" \
  -filter_complex "[1]volume=-14dB[h];[0]volume=-20dB[s];[s][h]amix=inputs=2:duration=first:normalize=0[o]" -map "[o]" -ar 48000 hum3.wav
```

The two real inputs are the recorder's own files from road map 3's smoke
runs, host state named by path and not tracked:
`~/Movies/Reelcut Recordings/Screen Recording 2026-09-11 at 20.11.44 (Microphone).m4a`
(21.1 s, the microphone alone) and
`… 2026-09-11 at 20.13.59.mov` (26.2 s, an R1-era file with the microphone
folded into the system track).

## The model

`silero_coreml.swift` needs the compiled Core ML bundle beside it (or in
`SILERO_MLMODELC`). It is 640 KB and not in the tree at this stage; S1
vendors it under `app/Resources/Models/` with its notice and provenance.

```sh
B="https://huggingface.co/aufklarer/Silero-VAD-v6.2.1-CoreML/resolve/main"
mkdir -p silero_vad.mlmodelc/analytics silero_vad.mlmodelc/weights
for p in silero_vad.mlmodelc/analytics/coremldata.bin silero_vad.mlmodelc/coremldata.bin \
         silero_vad.mlmodelc/metadata.json silero_vad.mlmodelc/model.mil silero_vad.mlmodelc/weights/weight.bin; do
  curl -sL "$B/$p" -o "$p"
done
```

Fetched 2026-09-13 at revision `523876545a57961474fee9df913e833e130560b8`
(`config.json` ETag `160b584b…`, `README.md` ETag `80f95880…`); the
repository's `config.json` says upstream `snakers4/silero-vad` tag
`v6.2.1`, compute precision float16, chunk 512, context 64. License: MIT
(the conversion's card and the upstream). `metadata.json` inside the bundle
names the inputs `audio [1,1,576]`, `h`, `c` `[1,1,128]` and the outputs
`probability [1]`, `h_out`, `c_out`.
