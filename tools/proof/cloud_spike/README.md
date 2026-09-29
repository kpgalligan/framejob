# The cloud spike — road map 6, C0 (2026-09-20)

Eight questions `archive/reelcut-roadmap-6.md` §3 asks about AssemblyAI, and
the instruments that answered them. **The answers are not here**: they are in
that document's §3, which this run rewrote into the record, with the verdict
on every design section a row overturned. What is here is how to run it again.

Nothing in this directory is a pass or a fail. Every row is a MEASUREMENT,
and the two ways a run can be wrong are a row that did not run (the runner
says `SPIKE INCOMPLETE` and names it) and a reservation left open in the
ledger (the same).

```sh
python3 tools/proof/cloud_spike/cloud_spike.py --selftest      # free, no key, loopback only
python3 tools/proof/cloud_spike/cloud_spike.py                 # all eight rows
python3 tools/proof/cloud_spike/cloud_spike.py --only q3,q4    # a subset; the rest carry forward
python3 tools/proof/cloud_spike/cloud_spike.py --leakcheck tools/proof/cloud_spike tools/proof/work/cloud_spike archive/reelcut-roadmap-6.md
```

## The instruments

| File | What it is |
|---|---|
| `cloud_spike.py` | the runner: `--only`, `--remake`, `--allow-q8-rerun`, `--selftest`, `--leakcheck`, the host facts, `answers.json`, the summary and the exit code |
| `aai.py` | the AssemblyAI client (stdlib `urllib`, no redirects), `Scrubber`, `Ledger` |
| `fake.py` | the in-process stand-in the selftest drives — upload, submit, get, delete, list, plus `redirect_next` and `drop_submit_reply` |
| `selftest.py` | the seven checks of `--selftest` |
| `fixtures.py` | `say`'s three pangrams, the extracted WAV, the measured truth pauses, the looped hour, q4's two late files |
| `cloud_rows.py` | q1, q2, q5, q6, q8 — the paid rows — and the recovery of a lost submit |
| `local_rows.py` | q3, q4, q7, probe and bundle building, `run_bounded` |
| `extract.swift` | `wav` / `m4a` / `flac` / `tracks` / `lag` — a standalone AVFoundation probe taking NOTHING from `app/Sources`, at `Transcriber.extractSettings` |
| `ats_probe.swift` | q3: one plain-HTTP GET, as a bare Mach-O and inside two signed bundles |
| `keychain_probe.swift` | q7: `add` / `read` / `read-noui` / `attrs` / `delete`, one step per process |

Each Swift file is built by the runner with
`xcrun swiftc -O -target arm64-apple-macos26.0 <file> -o work/cloud_spike/bin/<name>`
and prints ONE JSON object on stdout. `keychain_probe.swift` is copied to
`main.swift` first, because it is compiled with a generated `nonce.swift` and
top-level code needs that name once a second file joins it — the nonce is what
gives builds A and B two cdhashes.

`work/cloud_spike/` is untracked (`.gitignore` ignores `work/`) and holds
`fixtures/`, `bin/`, `bundles/`, `answers.json` and `ledger.json`.

## Fixtures — synthetic, and nothing else is ever uploaded

`SPEECH_TEXT` is IMPORTED from `tools/proof/silence2_proof.py`, so road map
4's fixture and this one are one spelling:

```sh
say -o speech.aiff "The quick brown fox jumps over the lazy dog. [[slnc 1200]] Pack my box with five dozen liquor jugs. [[slnc 800]] How vexingly quick daft zebras jump."
```

`speech.wav` is that file through `extract wav` (16 kHz mono 16-bit, the
shipped settings). The TRUTH pauses are measured from that WAV on this host —
the −40 dBFS rule over 10 ms peak buckets, spans of half a second or more —
and printed beside road map 4's 2.72–4.29 / 6.68–7.81; a difference over
0.05 s is printed as a host-state note, not a failure. `hour.wav` is
`speech.wav` looped by Python's `wave` to exactly 3600 s (115 200 044 bytes).
q4's `late.mov` and `late.mp4` are a black picture with the same speech
starting 1.5 s in (`ffmpeg -itsoffset 1.5`). `--remake` deletes and rebuilds
`fixtures/`, `bin/` and `bundles/` — **and nothing else**.

## The key, and what costs money

`RC_ASSEMBLYAI_KEY` is read in exactly one place, `aai.client_from_env`, and
the only thing anyone is ever told about it is the word `present`. It is never
printed, written, logged or passed as an argument (`ps` shows arguments to
every user), and every child process — `say`, `ffmpeg`, `swiftc`, `codesign`,
`security`, every probe — gets an environment with it REMOVED. Every string
the spike prints or writes goes through `Scrubber.clean`, and `answers.json`
and `ledger.json` are `assert_clean`ed before the write.

There is **no base-URL environment variable**. `Client.__init__` accepts
exactly two pairs — the live base with a real key, or a loopback base with
`selftest-dummy` — and raises otherwise, with neither key in the message. No
redirect is followed, and no URL taken out of a response body is ever
requested; an `upload_url` travels only as the `audio_url` of a submit.

Rows q1, q2, q5, q6 and q8 make real calls at $0.21 an hour of audio. The rows
that need the key and do not find it are SKIPPED BY NAME, with the reason, and
the run exits 2: a skip is not a pass.

`Ledger.reserve` runs BEFORE every upload and refuses the call that would pass
$2.00. Its events are `reserve → uploaded → created → billed → closed`, each
written as a temp file in the same directory and an `os.replace`; **nothing in
these instruments deletes, truncates or moves `ledger.json`** — not
`--remake`, not `--selftest`, not a row. A reservation closes as one of

* `deleted` — the transcript was created and DELETEd by us;
* `no_transcript` — the submit was refused, or the look proved none exists;
* `upload_only` — the reservation never reached a submit: the upload itself
  was refused, or a run was killed between the upload and the submit (C0's
  run has neither). An upload that was made is left to AssemblyAI's own
  ≤ 48 h retention. q5's refused language code is NOT this: its submit was
  answered, so it closes `no_transcript`;
* `unresolved` — a submit whose reply was lost and whose look could not
  prove either way. That is the one outcome that owes a line in a
  person-check issue (#53), because only a person can look at the
  dashboard.

Every run with a key STARTS by settling the ledger and ENDS by settling it
again, printing the count per outcome: DELETE everything `created` and not
`closed`; for an upload whose submit was lost, `find_own` — one page of the
list, matched ONLY against an upload URL this ledger recorded, the body parsed
and dropped inside the method — and a DELETE of what it returns. The spike
never deletes, reads, counts, prints or records anything about a transcript it
did not create. A run with a key also reserves every paid call in the proofs'
ledger against the month's AssemblyAI budget (spec §11 P-6, #163), through
`cloud_live_ledger.spike_ledger`, beside its own $2.00 `ledger.json`; a keyless
run writes no spend file.

## `--selftest`: seven checks, each broken on purpose once

It works in a `tempfile.mkdtemp()` root of its own, never opens the real
ledger, and talks only to `fake.Fake` over loopback with `selftest-dummy`.
Twenty-five checks in seven groups. Each group was broken on purpose and seen
to fail before it was trusted (2026-09-20, in a copy of this directory under
the scratch root, the tree never edited):

| Check | The mutant | What it scored |
|---|---|---|
| 1a the paid path end to end — the header, the models, one DELETE per transcript, `list_match`, and no key in stdout or `answers.json` | `aai.py`'s `authorization` header sent empty | 24/25, taking "the fake saw the dummy key on every request" |
| 1b the pair guard, and that its message holds neither key | `Client.__init__`'s guard made `if False` | 24/25 |
| 1c a 3xx is a `Reply` and a second fake sees NOTHING | `build_opener(NoRedirect)` → `build_opener()` | 23/25, taking both rows — the stock opener followed the redirect and the second port saw the request |
| 1d a lost submit reply recovered by the ledger's own upload URL, and another account's transcript untouched and unrecorded | `recover`'s `find_own` replaced by `200, []` | 24/25 |
| 1e `--remake` leaves `ledger.json` byte for byte | `remake()` given an `os.remove` of the ledger | 23/25 |
| 1f `run_bounded` bounds a hang, and a q7 whose cleanup hangs still leaves `measured` with `cleanup_blocked: true` | the `child.kill()` in `run_bounded` deleted | 24/25 |
| 1g the pause-crossing detector, the budget, and a keyless run that skips the five paid rows BY NAME and exits 2 | the crossing threshold moved from 33 ms to 33 000 ms | 24/25 |

Two of those mutants first scored 25/25 and the CHECK was strengthened rather
than the mutant excused, which is the part worth remembering: 1e watched a
file called `remake-ledger.json`, so a `remake()` that ate the real
`ledger.json` would have gone through; and 1f looked for its own hung child
with `pgrep -f "import time; time.sleep(60)"`, whose parentheses `pgrep` reads
as a regular-expression group, so it matched nothing and passed against a
`run_bounded` with the kill taken out. The check now uses the real file name
and a literal marker.

## `--leakcheck`

```sh
python3 tools/proof/cloud_spike/cloud_spike.py --leakcheck tools/proof/cloud_spike \
    tools/proof/work/cloud_spike archive/reelcut-roadmap-6.md tools/proof/README.md CLAUDE.md
```

It compares IN PROCESS and prints file NAMES only — never the secret, never a
URL, never a line. It looks for the key and for every upload URL in
`ledger.json`, in every path given except `ledger.json` itself, which is the
one place an upload URL is allowed to be. `clean` is the only good answer.

## Exit codes

* **0** — every requested row ran and no reservation is open or `unresolved`.
* **2** — a row was SKIPPED, NOT RUN or FAILED, or a reservation is open or
  `unresolved`. The runner prints `SPIKE INCOMPLETE` and names each with its
  reason, and road map 6's header says the same.
* **1** — an instrument failure (a probe that would not build is the ROW's
  failure, recorded, not an exit).

## Where the answers land

`work/cloud_spike/answers.json` holds every number, and
`archive/reelcut-roadmap-6.md` §3 holds the record read out of it: the host
paragraph, each row's question, **Measured** and **Verdict**, §3a what the
spike changed in that document, and §3b the spend and the deletion, call by
call. A subset run carries the other rows forward under `carriedForward` with
the dates they were measured, so `--only q8` cannot erase the record run.
