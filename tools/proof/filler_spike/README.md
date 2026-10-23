# The filler spike — road map "cut-by-transcript", CT-0 (2026-10-22)

One question the road map asks before any filler code is written: **does the on-device engine
(`SpeechEngine`, `SpeechTranscriber` with `transcriptionOptions: []`) report fillers at all?**
**The answers are not here**: they are in `archive/cut-by-transcript.md`'s CT-0 record, and the
decision they made once o2 ran on the owner's sample is spec §11 TR-7
(`designs/spec/11-decisions/cut-by-transcript.md`). What is here is how to run it again.

Nothing in this directory is a pass or a fail. Every row is a MEASUREMENT, and the two ways a
run can be wrong are a row that did not run (the runner says `SPIKE INCOMPLETE` and names it)
and an instrument that failed (exit 1). Nothing here costs money or touches the network.

```sh
python3 tools/proof/filler_spike/filler_spike.py                    # f1, f2, f3, o1 and o2
python3 tools/proof/filler_spike/filler_spike.py --no-owner         # o1 and o2 skipped by name
python3 tools/proof/filler_spike/filler_spike.py --remake           # remake the three say fixtures
python3 tools/proof/filler_spike/filler_spike.py --selftest         # the classifier's controls; no engine, no build
python3 tools/proof/filler_spike/filler_spike.py --selftest --mutant keep-punctuation   # must exit 1, K failing
python3 tools/proof/filler_spike/filler_spike.py --selftest --mutant replaced-as-kept   # must exit 1, R failing
python3 tools/proof/filler_spike/filler_spike.py --selftest --mutant o2-ignored         # must exit 1, V1 and V2 failing
```

The probe links the core's staticlib, so `cd core && cargo build --release` comes first.

## The instruments

| File | What it is |
|---|---|
| `filler_spike.py` | the runner: the fixtures, the build, the rows, the classifier, the verdict, `answers.json`, the selftest and the exit code |
| `filler_spike_probe.swift` | compiled AS `main.swift` over every file in `app/Sources` but the app's own, through `swift_build.build` (macOS 26.0); `filler-spike-probe <work-dir> <media-path>…` |

**The probe** prints `{"locale":"en-US","installed":…}` from `SpeechEngine.isInstalled` first
and exits 3 there unless it is `true`. Then, per media, it extracts the whole audio track with
`Transcriber.extractAudio` (`Transcriber.wholeAsset`) to `<work-dir>/<n>.wav`, transcribes it
with `SpeechEngine.transcribe` on a thread of its own while main's run loop turns
(`speech_engine_probe.swift`'s `offMain`, copied), deletes the WAV and prints
`{"file","ok","error","seconds","runs":[{"text","start","end"}]}`, `seconds` being frames ÷
16 000. It never calls `SpeechEngine.download`, never asks for Speech authorization and never
touches the network.

**The runner** works in `tools/proof/work/filler_spike/` (untracked): `fixtures/`, `build/`,
`bin/`, `wav/` and `answers.json`. A token is matched after lowercasing and stripping its
leading and trailing punctuation, against `FILLERS` (`um umm uh uhh er erm ah hmm hm mm mhm
uh-huh`). For f1 and f2 each scripted filler is aligned script → recognised by
`difflib.SequenceMatcher` and marked `kept`, `dropped` or `replaced:<word>`; f2 is aligned
against F1's words, since its `[[slnc]]` markup is not spoken, and o2 against `O2_SCRIPT`. The
probe answers one line per media in the order given, and the runner reads them in that order. A
file with no answer within 900 s makes the probe exit 4 after deleting its WAV, and the runner
bounds the whole run at 900 s a file plus 60.

## The fixtures and the rows

`say -o <row>.aiff <text>`, the default voice, made once and remade by `--remake`:

| Row | Audio | What it answers |
|---|---|---|
| f1 | `F1_TEXT`, eight scripted fillers | whether a filler in running speech is kept, dropped or replaced |
| f2 | F1 with `[[slnc 300]]` before and after each filler | the same with each filler set apart by silence |
| f3 | F1 with the fillers and their commas removed | the control: `filler_count` must be 0 and at least 80 % of the script recognised, else exit 1 |
| o1 | `tools/proof/media/owner-sync/record.aifc` | the owner's one real recording: `seconds`, `word_count`, `filler_count`, `filler_tokens` only; unscripted, so its 0 is weak evidence |
| o2 | the one file in `tools/proof/media/filler-sample/` | the owner reading `O2_SCRIPT` (eight fillers): each scripted filler `kept`, `dropped` or `replaced:<word>`, the counts, and `script_recognised`, the share of the script's other words recognised; under 80 % it is not a reading of the script, and the run exits 1 |

**The owner's media.** `tools/proof/media/owner-sync*` and `tools/proof/media/filler-sample/`
are the owner's, gitignored (`tools/proof/.gitignore`'s `media/`), read in place and never
committed or copied out. o1's and o2's raw words stay in the runner's memory: only counts,
filler tokens and o2's per-filler dispositions are printed or written, and each WAV is deleted
as soon as it is transcribed. `owner-sync-2/record.aifc` is byte-identical to
`owner-sync/record.aifc` (the same MD5), so it is not a row. o1 is skipped by name when the file
is absent, o2 when the folder holds no file or more than one, and both when `--no-owner` is
given.

## Recording the owner's sample

o2 needs about 30 seconds of the owner reading this script aloud. It holds eight fillers (um 3,
uh 3, er 2), so the spike can count how many the engine keeps:

> Okay, so, um, this is a short test recording for the filler spike. I'm going to, uh, read a few sentences out loud. The weather today is, um, pretty nice, I think. Er, I had coffee this morning and, uh, then I went for a walk. Um, after that I sat down to, uh, work on the editor for a while. And, er, that's about it.

1. Read it naturally, in your own voice, fillers and all, as if you were talking rather than
   reading. Say each "um", "uh" and "er" where it is written; do not add or skip any on
   purpose (a stray one is fine, it is counted, not scripted).
2. Record with anything: QuickTime Player (File ▸ New Audio Recording), Voice Memos, the
   iPhone, a camera. Any file AVFoundation reads will do (`.m4a`, `.wav`, `.aiff`, `.mov`,
   `.mp4`…); the probe extracts its first audio track.
3. Save it as the ONLY file in `tools/proof/media/filler-sample/` (make the folder; the name
   of the file does not matter). It is gitignored and never leaves the machine.
4. Run `python3 tools/proof/filler_spike/filler_spike.py`. It is free and on-device.

## The verdict

`answers.json` is `{"date","tree","macos","rows","reported_in","verdict"}`, `reported_in` the
rows with `filler_count` > 0. The first match wins:

- `unmeasured` — f1 or f2 did not run;
- when o2 ran, it decides, as the real-speech row: `reports-real` if its `filler_count` > 0
  (every scripted filler it kept counts), `does-not-report` if 0;
- else, o2 absent: `unmeasured` if f1 or f2 reported and o1 did not run; `reports-real` if o1
  ran with `filler_count` > 0; `tts-only` if f1 or f2 reported and o1 ran with 0;
  `does-not-report` if f1 and f2 ran with 0.

TR-7 is written only from a verdict f1 and f2 both produced, and only once o2 has run on the
owner's sample (the road map's CT-0 record).

## Exit codes

- **0** — every row ran; `answers.json` written.
- **2** — `SPIKE INCOMPLETE`, naming each row that did not run (en-US not installed, the owner's
  media absent, `--no-owner`); `answers.json` written with the verdict above.
- **1** — an instrument failed: the probe would not build, crashed or ran out of time, the f3
  control did not hold, o2 is not a reading of its script, or a selftest row failed. Nothing is
  written.

## The selftest

No engine and no build: the classifier over hand-written runs. K — "um," recognised, so `kept`
(and counted); D — the filler absent, so `dropped`; R — "a" in the filler's place, so
`replaced:a`; Z — a script with no fillers counts 0; O — o2's alignment over a hand-written
reading of `O2_SCRIPT` (one filler dropped, one heard as "or", one more dropped, an unscripted
"um" added: 6 counted); V1–V4 — the verdict (o2 with fillers is `reports-real` and with none
`does-not-report` whatever o1 says, o2 absent falls back to o1's `tts-only`, f1 absent is
`unmeasured`); and four rows over the fixture texts (F1's eight fillers, F2's sixteen silences,
F3's none, `O2_SCRIPT`'s eight). `--mutant keep-punctuation` leaves the punctuation on and must
fail K; `--mutant replaced-as-kept` marks a replacement `kept` and must fail R;
`--mutant o2-ignored` leaves o2 out of the verdict and must fail V1 and V2.
