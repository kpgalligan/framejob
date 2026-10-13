# The word-captions spike — road map 8, W0 (2026-09-22)

Seven questions `archive/roadmap-8.md` §3 asks before any word-caption
code is written, and the instruments that answered them. **The answers are not
here**: they are in that document's §10.1, with §3a listing every design
section a row overturned. What is here is how to run it again.

Nothing in this directory is a pass or a fail. Every row is a MEASUREMENT, and
the three ways a run can be wrong are a row that did not run (the runner says
`SPIKE INCOMPLETE` and names it), an instrument that failed (a probe that would
not build, a control that did not hold, a face that resolved to the system
fallback — exit 1), and a reservation left open in the ledger (the same).

```sh
python3 tools/proof/words_spike/words_spike.py                  # all seven rows
python3 tools/proof/words_spike/words_spike.py --only q4,q5     # a subset; the rest carry forward
python3 tools/proof/words_spike/words_spike.py --remake         # rebuild fixtures, binaries, the scratch tree
python3 tools/proof/words_spike/words_spike.py --leakcheck tools/proof/words_spike \
    tools/proof/work/words_spike archive/roadmap-8.md tools/proof/README.md
```

## The instruments

| File | What it is |
|---|---|
| `words_spike.py` | the runner: `--only`, `--remake`, `--leakcheck`, the host facts, `answers.json`, the summary and the exit code |
| `fixtures.py` | the four fixtures and the truth each carries; `onset(path)`; `TALK_TEXT` |
| `speech_rows.py` | q1, q2, q3 — the two speech engines, and the only row that spends money |
| `text_rows.py` | q4, q5 and q6's fetch-and-registry half |
| `scratch_rows.py` | q7 — the scratch tree, its builds — and q6's picture half |
| `speech_probe.swift` | `words` / `sf` / `assets` / `cancel`, built at macOS 26.0, taking NOTHING from `app/Sources` |
| `text_probe.swift` | `tokens` / `raster` / `stress` / `fonts`, compiled AS `main.swift` over `app/Sources` at macOS 15.0 |
| `tokens.rs` | `str::split_whitespace` over the q4 corpus, offsets in UTF-16, no dependencies |
| `fonts/` | the four OFL display faces and their three licence files, fetched by q6 |

`speech_probe.swift` is built with

```sh
xcrun swiftc -O -parse-as-library -target arm64-apple-macos26.0 speech_probe.swift -o speech_probe
```

— the line `tools/proof/silence_spike/level_apple.swift:7` already proved on
this host. `text_probe.swift` is COPIED to `main.swift` and built with
`tools/proof/peaks_probe.py:101-117`'s line, at `-target arm64-apple-macos26.0`
since road map 8's W2 (the app's `SpeechEngine.swift` needs 26.0 to compile),
because it reaches internal members of the app's own module. `tokens.rs` is
`rustc -O`. Every probe prints ONE JSON object on stdout; times are seconds
unless a key says `_ms`.

`work/words_spike/` is untracked (`.gitignore` ignores `work/`) and holds
`fixtures/`, `bin/`, `bundles/`, `q4/`…`q7/`, `scratch/`, `answers.json` and
`ledger.json`. `RC_WORDS_SPIKE_WORK` names a different work directory;
`RC_WORDS_SPIKE_SCRATCH` names where q7's tree copy goes (the default is
`work/words_spike/scratch`, which `make app` inside the copy fills to a couple
of gigabytes).

## Fixtures — synthetic, and nothing else is ever uploaded

| File | What it is |
|---|---|
| `pangram.wav` | `say`'s rendering of `SPEECH_TEXT`, IMPORTED from `tools/proof/silence2_proof.py`, with its two `[[slnc]]` pauses |
| `talk.wav` | `TALK_TEXT`, about 120 synthetic words with numbers, contractions, a hyphenated compound, `,;:?!…` and one quoted phrase |
| `ten.wav` | `talk.wav` repeated with 0.8 s of digital silence between copies until it passes 600 s |
| `isolated.wav` | every word of `SPEECH_TEXT` rendered ALONE and concatenated with 300 ms of silence |

All four go through the cloud spike's own `extract wav`, at
`Transcriber.extractSettings` — 16 kHz mono 16-bit, the settings the shipped
app hands both engines. The TRUTH pauses in `pangram.wav` are measured from
the WAV this host just wrote, through `cloud_spike.fixtures.truth_pauses`, and
printed beside road map 4's 2.72–4.29 / 6.68–7.81; a difference over 0.05 s is
a host-state note, not a failure.

**`say` has no word timing.** `isolated.wav` is the nearest thing to a known
per-word start the spike can build, and it is an APPROXIMATION of speech: words
said one at a time are not a sentence. Each lone rendering also carries the
synthesizer's own leading silence — C0 measured 330–370 ms of it per `[[slnc]]`
boundary — so a word's known start is `offset + onset(word.wav)`, not the
concatenation offset. `fixtures.json` records both per word with the median
leading silence beside them, and q2 prints the raw-offset delta next to the
corrected one so the bias stays visible.

## Money

Only q2 spends anything, and only on `pangram.wav`, `talk.wav` and
`isolated.wav` — about 75 seconds of audio, roughly half a cent at
`aai.RATE_PER_HOUR`. `ten.wav` is NEVER uploaded: C0's q8 already measured the
cloud at 147× real time, and ten minutes of audio answers nothing this spike
asks.

- `RC_ASSEMBLYAI_KEY` is read by `aai.client_from_env` and by nothing else; it
  is never printed, logged, written or passed as an argument, and every child
  process has it REMOVED from its environment (`local_rows.child_env`).
- `Ledger.reserve` runs before every upload and refuses at
  `aai.BUDGET_DOLLARS` ($2.00). Every transcript created is DELETEd and the
  DELETE's status recorded; `settle` runs at the start and the end of every
  run that has a key. A run with a key also reserves every paid call in the
  proofs' ledger against the month's AssemblyAI budget (spec §11 P-6, #163),
  through `cloud_live_ledger.spike_ledger`; a keyless run writes no spend file.
- Upload URLs live in `work/words_spike/ledger.json` and nowhere else.
- `--leakcheck` carries its OWN secret list — the key plus every `upload_url`
  this spike's ledger recorded — and exempts that ledger alone. It is NOT
  `cloud_spike.leakcheck`, which is pinned to `work/cloud_spike/ledger.json`
  (`cloud_spike.py:43-47, 290-300`); nothing under `cloud_spike/` is edited by
  this spike. It prints `leakcheck: N secrets, M roots` and then `clean`, or
  one `LEAK <path>` per hit, and never a secret or a line.

## What the rows do not do

- `requestAuthorization` is never called: it is an unanswerable prompt for an
  agent, and a bare Mach-O with no `NSSpeechRecognitionUsageDescription`
  crashes on it (`Transcriber.swift:284-289`). `authorizationStatus()` is a
  read and is the only authorization call in the spike.
- `downloadAndInstall` is never called. q3 reads `AssetInventory` and the
  progress a request reports BEFORE any download, and the no-network case is
  recorded as not run: it would change host network state.
- Nothing is installed to `~/Library/Fonts`. Every registration is `.process`
  scope, the harness's own loop.
- q7 never writes to the tree. It rsyncs a copy, moves the target pins in THAT
  COPY, and builds it; `git status --short -- app core project.yml Makefile
  tools/proof/harness` prints nothing after a full run.
- One owned app instance, on port 4831, killed by PID. `grep "Frame Job: "
  /tmp/framejob-4831.log` must print nothing before any claim is read off a
  pixel.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | every requested row ran and no reservation is open or `unresolved` |
| 1 | an instrument failed — a probe would not build, a control did not hold, a face fell back to Helvetica |
| 2 | `SPIKE INCOMPLETE`: a row did not run, or a reservation is open |
