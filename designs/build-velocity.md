# Build velocity (issue batch B88)

**Goal.** Make every Swift compile a proof pays parallel and paid once per
input state; give the loop a Debug app, "Reelcut Debug", with its own bundle
id and defaults domain, that cannot be driven stale; put one skipping gate and
a Verification rule over it. Nothing in the shipped product changes: `make
app` stays Release, Release and Distribution keep identical build settings
and Info.plist bytes, and `make dist` and `.github/workflows/publish.yml` are
untouched.

## Phases

Each phase is committed alone, in this order.

| Phase | What | Needs |
|---|---|---|
| 1a | `make typecheck` in batch mode; `tools/proof/swift_build.py` (one cached probe build); harness `build.sh`, `make test`'s two probes and `graphics_inspector_proof.py` go through it | — |
| 1b | The other 68 scripts go through the helper; add the one-swiftc-line guard. Permitted cut: two runs (alphabetical halves), with the guard in the second | 1a |
| 2 | Fix the Debug configuration and give it its own identity (spec §11 V-5); the Rust step always runs; `make app-debug`; `tools/proof/proof_app.py` (app choice, stale refusal); the defaults guard follows the app under test; launch points and tree-copy builds go through it. The default stays Release | — |
| 3 | Debug-vs-Release equivalence proof; qualification; the default flips to Debug; Release-only pins; spec §11 V-4 (amends V-1) | 2 |
| 4 | `make gate`; the Verification rule; the road map closes into an ADR | 1a, 2, 3 |

## Decisions

- **One probe build line.** A probe, a proof or the harness compiles app
  sources only through `tools/proof/swift_build.py`; its argv is spelled in
  one place (`_argv`).
- **Parallel by `-j <cores>`, not batch mode, for a linked build.** The
  serial line's machine code is what every earlier proof measured; `-j`
  keeps it byte-for-byte (phase 1a's `__text` check), while batch mode with
  an output file map does not (E1, below). `make typecheck` and
  `swift_build.py typecheck` link nothing and use batch mode.
- **Content, never mtime.** A build is reused only when a sha256 over every
  input — the helper, the toolchain and SDK, the argv less `-o`/`-j`, every
  source, the bridging header and its quoted includes, the staticlib, each
  link input, four toolchain variables and the tree's path — matches a cached
  entry whose binary still hashes to its manifest.
- **Delivered to the caller's own path and name**, because a bare binary's
  defaults domain and `proof_defaults.py --ran` are that name.
- **The harness's Fonts and Models** are recopied only when their digest
  differs, through a sibling folder renamed into place, so a reuse never
  pulls a folder out from under a launching harness.
- Owner rulings that bind every phase: one mutant per new decision (usually
  3–8; more than 10 only with a written reason); Debug while working, Release
  built and checked once at each phase's end; no override variable for the
  stale refusal; the gate runs its steps serially.

## Record

### Phase 1a — the probe builder (2026-10-07)

**Landed.** `Makefile`'s `typecheck` line gains `-enable-batch-mode -j
"$$(sysctl -n hw.logicalcpu)"`, and `test` runs `python3
tools/proof/swift_build.py --selftest` before `proof_defaults.py`.
`tools/proof/swift_build.py` (new): `build`, `typecheck`, `app_sources`,
`cache_key`, the cache under `tools/proof/work/swift-build/`, the CLI and the
selftest (K0, K1, B1–B5). `tools/proof/harness/build.sh` builds through it
(same CLI, output path and docs copies; Fonts/Models by digest). The
`build_probe` of `assistant_lane_proof.py`, `assistant_prompt_proof.py` and
`graphics_inspector_proof.py` calls `swift_build.build`, with their mtime and
`sources.txt` staleness checks removed. `tools/proof/README.md` has the
section "The probe builder (swift_build.py)".

**Timings** (one session, 12 logical cores; the 1-minute load average at
start → end; another session shared the machine throughout):

| command | before (HEAD fe22fac) | after | load |
|---|---|---|---|
| `make typecheck`, clean | 81 s (tsc ≈ 1 s of it) | 3.4 s, the same four warnings | 3.7 → 3.1; 2.1 → 2.6 |
| typecheck line over a scratch copy with one type error | 17 s, exit 1, the error named | 3.2 s, exit 1, the error named | 3.3 → 3.0; 2.7 |
| harness cold, serial (`build.sh --force` at HEAD) | 124 s; again 112 s (the control) | — | 3.0 → 8.0; 3.2 → 4.6 |
| harness cold, helper (`build.sh --force`) | — | 15.1 s; 16.0 s; 24.0 s | 2.8 → 4.1; 4.0 → 6.1; 16.8 |
| harness reused (`build.sh`) | 0.02 s (mtime skip) | 0.37 s, 0.34 s (digest checked) | 17.0 |
| lane proof, cold | 130 s whole (probe 110 s) | 37.5 s whole (probe 17.2 s) | 6.5 → 4.1; 8.9 → 12.1 |
| lane proof, reused | 19.6 s | 21.1 s | 3.9; 12.1 |
| prompt probe (`--probe`), cold / reused | probe 108 s (inside `make test`) | 18.4 s (probe 15.2 s) / 2.3 s | 8.5; 9.7 |
| `make test` after a one-line Swift comment | 307 s (each probe 108 s) | 109 s (probes 18.3 s and 27.2 s) | 3.0 → 6.2; 9.9 → 31.4 |
| `graphics_inspector_proof.py`, whole | 17.2 s (probe and harness current by mtime) | 33.4 s with its probe cold (15.9 s); 17.2 s reused | 4.1 → 3.7; 8.6; 9.8 |
| `graphics_inspector_proof.py --mutant popup-fixed-width` | 112.5 s (probe 110 s) | 19.7 s (probe 16.9 s) | 3.6 → 1.7; 7.9 → 12.1 |

The "before" `make test` row made both probes stale by removing their
binaries; the "after" row by a one-line comment appended to
`app/Sources/ReelOpSchema.swift`, restored byte-for-byte straight after. Both
are one full compile of each probe.

**Machine code.** `segedit <bin> -extract __TEXT __text <out>` and `cmp`:
the serial line's and the helper's `__text` are byte-equal for the harness
(15 767 764 bytes) and for the lane probe (15 781 920 bytes). CONTROL: two
serial harness builds are equal. Sensitivity: two helper builds over a copy of
`app/Sources`, the second with `AppSupport.swift`'s `0o700` changed to
`0o755`, differ. `-j` is adopted.

**E1, measured once.** The helper's non-WMO line as `-enable-batch-mode -j 12
-output-file-map <a map naming every object in the tmp dir>`: it links the
harness, in 10.2 s against the `-j` build's 15.5 s in the same session
(0.66×, under the 0.7× bar), but its `__text` differs from the `-j` build's
(15 767 756 bytes against 15 767 764). One of the four conditions fails, so
E1 is not adopted and the line keeps `-j`.

**Verified.** `swift_build.py --selftest` 6/6 and `PASS` (its first run
failed B3: a rebuild after a failed digest landed beside the tampered entry
and the tampered binary was still delivered; the build now sets the old
entry aside first). `make typecheck` 0 errors, the four baseline warnings.
`assistant_lane_proof.py` 18/18 cold and reused; `assistant_prompt_proof.py
--probe` 14/14 cold and reused; `harness/build.sh --force` then
`phase2_chrome.py` 26/26; `build.sh` twice more reused with the Fonts and
Models inodes unchanged (and a stray file put in the harness's Fonts made one
recopy, a new inode, the stray gone); `graphics_inspector_proof.py` 91/91,
and `--mutant popup-fixed-width` `MUTANT PASS` (exactly its three rows,
through the cache). The Full gate's numbers are in this phase's checks file.

**Owed to phase 1b.** The other 68 scripts, the G0/G1 guard rows, and room
for them in `swift_build.py` (399 of its 400 lines are used).
