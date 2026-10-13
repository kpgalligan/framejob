# The graphics spike — road map 10, G0 (2026-09-24)

Nine questions `archive/roadmap-10.md` §3 asks before any graphics
code is written, and the instruments that answered them. **The answers are
not here**: they are in that document's §10.1, with §3a listing every design
section a row changed. What is here is how to run it again.

Nothing in this directory is a pass or a fail. Every row is a MEASUREMENT.
The ways a run can be wrong are a row that did not run (the runner prints
`SPIKE INCOMPLETE` and names it, exit 1), an instrument that failed (the
spike crate or a probe that would not build — exit 1), and a tree left
different from `c874069` in `core/` or `app/` (`GIT CHECK NOT CLEAN`, exit 1).

```sh
python3 tools/proof/graphics_spike/graphics_spike.py                    # all nine
python3 tools/proof/graphics_spike/graphics_spike.py --only q4,q5       # a subset; the rest carry forward
python3 tools/proof/graphics_spike/graphics_spike.py --only q5 --mutant # the on-purpose failure: exit 0 only if caught
python3 tools/proof/graphics_spike/graphics_spike.py --only q7          # its own git check, make app, the app on port 4843
python3 tools/proof/graphics_spike/graphics_spike.py --skip-build ...   # reuse the crate's target/
```

The rows run in the order q2, q8, q3, q4, q5, q6, q1, q9, q7. q1 and q9
PATCH the core — `graphics_spike` as a path dependency in `core/Cargo.toml`,
`pub mod ffi_graphic;` in `core/src/lib.rs`, a throwaway
`core/src/ffi_graphic.rs` — and `rows_build.revert()` always runs after them
(`git checkout c874069 -- core/Cargo.toml core/Cargo.lock core/src/lib.rs`,
the new file removed, the core and the app rebuilt), so q7 launches the app
built from the reverted tree and records its SHA-256. **q1 deletes
`core/target`** twice (the cold builds); a full run takes about half an
hour on an M2 Max.

## The instruments

| File | What it is |
|---|---|
| `graphics_spike.py` | the runner: `--only`, `--mutant`, `--skip-build`, the host facts, `answers.json`, the summary and the exit code |
| `bounded.py` | Rule H: `run(argv, seconds, cwd, env)` in its own process group, stdout drained while it waits, `killpg(SIGKILL)` on expiry, answered `expired: True`; `Background` for the q7 watcher |
| `rows_local.py` | q2, q3, q4, q5, q6, q8 — builds the crate (release and debug) and calls its binary once per row, once per case for q6 (30 s each) |
| `rows_build.py` | q1 and q9 — the baseline and patched measurements, q1c's `raster-images` flip, the two Swift probe links, the revert and its git check |
| `rows_app.py` | q7 — the git check, `make app`, the binary's SHA-256, one owned app on port 4843 by PID, the package sub-rows and the watcher sub-row |
| `Cargo.toml`, `Cargo.lock` | the scratch crate: `rquickjs` 0.14.0 (`loader`), `resvg` 0.48.1 (`default-features = false, features = ["text"]`), `serde_json`, `sha2`; its own `[workspace]` |
| `src/runtime.rs` | `Engine`: one QuickJS runtime and context, the limits and the interrupt deadline, the stdlib and the sandbox evaluated in, the ES-module load, `svg()`, `math_hash()` |
| `src/diagnostic.rs` | `Diagnostic` and how an exception becomes one (line and column parsed from `stack`) |
| `src/stdlib.js` | the standard library the six graphics use, written from scratch |
| `src/raster.rs` | `Library` (fontdb from bytes, never the system's), `measure_text`, `rasterize` (parse, render, RGBA→BGRA) |
| `src/rows.rs`, `rows_text.rs`, `rows_stress.rs` | the row bodies: q2, q3, q8 and `render_frame`; q4; q5 and q6 |
| `src/main.rs` | the CLI; every subcommand prints ONE JSON object |
| `tests/q8.rs` | the "test binary" of q8 |
| `graphics/*.js` | the six §5k graphics in §5c's module shape |
| `q9_probe.swift`, `q9_probe.h` | Swift calling the throwaway export; `-D CONTROL` calls only `rc_op_names` |
| `q7_watch.swift` | a `DispatchSource` on a directory fd, one JSON line per event |

The crate's own subcommands, for a single row by hand:

```sh
cd tools/proof/graphics_spike && cargo build --release
B=target/release/graphics_spike; F=../../../app/Resources/Fonts
$B q2 --fonts $F
$B q3 --graphics graphics --fonts $F --frames 300 --csv /tmp/q3.csv
$B q4 --fonts $F
$B q5 --graphics graphics --fonts $F [--mutant]
$B q6 --graphics graphics --fonts $F --case while_true
$B q8
$B render --graphics graphics --fonts $F --name lower-third --frame 30 --width 1920 --height 1080 --png /tmp/f.png
```

Before handing the crate on: `cargo fmt --check && cargo clippy --release
-- -D warnings` in this directory, and each `src/` file under 400 lines.

## `work/graphics_spike/`

Untracked (`tools/proof/.gitignore` ignores `work/`): `answers.json` (the
rows, the host, the resolved crate versions, the revert and the git check;
`mutants.q5` holds the last `--mutant` run), `q3.csv` (one line per frame),
`frames/` (each graphic at frames 0, 30 and 150, looked at once),
`q9/` (the two probe binaries), `q9_fonts/` (the one font both q9 renders
use), `q7/` (the three packages and the watched folder) and
`reelcut-4843.log`, which `grep "Reelcut: "` must leave empty. `full-run.log` is the
2026-09-24 full run's printed transcript, copied there by hand, because a
later `--only q7` replaced that run's q7 entry in `answers.json`. After the review's sandbox fix, `answers.json` is that record with its
q6 entry replaced by an `--only q6` re-run (eighteen cases, what §10.1 q6
quotes); the fix pass's full verification re-run is kept beside it as
`answers-fix1-verify-fullrun.json` and, after its `--only q5 --mutant` and
`--only q7`, `answers-fix1-verify.json`, and it overwrote `q3.csv`, `frames/`,
`q7/` and `q9/`, so those no longer match the numbers the record quotes.
