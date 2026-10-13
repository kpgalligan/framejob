# The assistant spike — road map 12, A0 (2026-09-27)

The questions A1 cannot be designed without, and the instrument that
measures them. **The answers are not here**: they are in
`archive/roadmap-12.md` §7 ("A0 record"; condensed in
`designs/adr/roadmap-12-assistant.md`), which also says what they changed in
§5. What is here is how to run it again.

- **B** — Rasterize's `agent/` copied and renamed, a hook and the build step
  in a COPY of the tree; the copy's `make app`, its Distribution build, and
  the drag probe's build;
- **H** — does the Bun helper, signed as Rasterize signs it, launch from a
  Release and a Distribution bundle under the hardened runtime, and does it
  need its one entitlement;
- **C** — how big is the catalog: `catalogJSON()`, the first request the
  helper sends, its tokens, and the tool-search choice that follows;
- **F** — the stand-in's credential rule (R6-9(e));
- **T** — can a stand-in Messages server script a turn: a `tool_use`, the
  tool's result, then text;
- **E** — does `export` replace an existing file;
- **D** — what an agent edit does to a timeline drag in progress;
- **L** — `ANTHROPIC_API_KEY` written nowhere.

```sh
python3 tools/proof/assistant_spike/assistant_spike.py                      # every group
python3 tools/proof/assistant_spike/assistant_spike.py --only D,F           # a subset; other rows carry forward
python3 tools/proof/assistant_spike/assistant_spike.py --rasterize ~/devel/rasterize
```

Needs `bun`, `xcodegen`, Xcode, `swiftc`, `core/target/release/libframejob_core.a`
(`cd core && cargo build --release`) and a clean read of `~/devel/rasterize`
(read-only: files are copied from it, and bun never runs there). No ffmpeg.
It launches the copy's two apps, each on a free port of its own, and the
stand-in; nothing else. A run takes about 5 min, most of it the two builds and the probe's.

## The instruments

| File | What it is |
|---|---|
| `assistant_spike.py` | the runner: the copy, the builds, the signatures, the two runs, the stand-in's own F instance, the probe, scoring, `answers.json`, the digest, the exit code |
| `AssistantSpikeHook.swift` | compiled ONLY into the copy: inert unless `-RCAssistantSpikeLog <file>`; logs the catalog, waits for a `ProjectDocument` with a file (a main-run-loop `Timer`), launches `Contents/Helpers/framejob-agent` the way Rasterize's `AssistantHelperSession.open` does, sends `configure` (the dummy key `proof-key`, `api_base` = `RC_ASSISTANT_BASE_URL`) and one `send`, and runs each `tool_request` through `AgentServer.shared.execute`; one JSON line per step |
| `drag_probe.swift` | the D probe, compiled as `main.swift` over `app/Sources` minus `main.swift` on `harness/build.sh`'s swiftc line; prints one `ANSWER {"rows":[…],"measure":{…}}` line |
| `../anthropic_fake.py` | the stand-in Messages API (top level, beside `assemblyai_fake.py`, because A1 reuses it); its docstring is its contract |

**The copy** is `work/assistant_spike/tree/`, made by
`tree_copy.make_copy(TREE, agent=False)`: `app/` (without `Info.plist` or
`*.entitlements`), `project.yml` and `Makefile` copied; every other build
input `project.yml` names but `agent` symlinked; `agent/` holding Rasterize's `package.json`, `bun.lock`,
`tsconfig.json`, `entitlements.plist` and `src/{main,protocol}.ts` with
`rasterize-agent` renamed `framejob-agent` (package name, outfile, the lock's
root workspace). The hook goes in `app/Sources/`, one call to it after
`AppDelegate`'s `enabledDefaultsKey` block, and Rasterize's `Build Agent
Helper` step (its `project.yml:173-190`, renamed) goes before `schemes:` as
the last `postBuildScripts` item, once the copy's own `Build Agent Helper`
item (its comment through its `script:` line) is removed, so the copy's
`project.yml` holds exactly one. Every anchor must occur exactly once (B3).
The copy, `build/` included, is made fresh every run: a kept `build/` fails
the next build, because xcodegen rewrites `app/FrameJob.entitlements` and Xcode
refuses an entitlements file "modified during the build".

**A run** (r: the copy's Release, d: its Distribution) goes: the stand-in
started and the T scenario posted; the app launched with `screens.py`'s argv,
a fresh `-RCSecretFolder` and `-RCAssistantSpikeLog`; its port read from its
log; `new_project {path}` over MCP; the hook's `done` or `timeout` awaited;
`get_project`; in run r only, E's two exports; the stand-in's log read; the
app's own helpers named (its direct children on the copy's helper path) while
it still runs; the app's and the stand-in's groups killed; and any of THOSE
helpers still running killed and recorded. A helper-path process that is not
the app's child is recorded as `helpers_foreign` and never signalled.

## Rows

I instrument, C control, A answer. An answer row's `fail` is a measured
"no"; an instrument's or a control's is the spike failing. The suffix `r`/`d`
is the copy's Release or Distribution build.

| Rows | What |
|---|---|
| B1 I, B2 A, B3 I, B4 I, B5 I, B6 I | Rasterize's HEAD, `agent/` dirty, `src/*.ts` sha256, SDK and bun versions; `bun install --frozen-lockfile` after the rename (else a plain install and the lock diff); the anchors; the two builds; the probe's build |
| H1r/d A, H2r/d A | the helper's bytes, `runtime` flag, entitlements exactly `allow-jit`; the app's strict deep verify, `runtime`, entitlements exactly `audio-input` |
| H2t A | the tree's OWN `build/Build/Products/{Release,Distribution}/Frame Job.app` (read, never built) carry the same entitlements as the copy's, with each binary's mtime; a skip when either is absent |
| H3 C | the tree's `dist_check.py` on the copy's two builds: full marks |
| H4r/d A | the copy binds its port, no `Frame Job: ` line, and the hook logs `ready` from its helper |
| H5 C, H6 A | the Release helper launched by the runner (three-variable environment) reaches `ready` in 20 s; a copy re-signed `--options runtime` with NO entitlements does not, with its exit status and first stderr line |
| C1r/d A, C2 A, C3 A | `catalogJSON()` bytes and tools; run d's first POST (body, tool count, tools array bytes); the assistant catalog (C2's tools minus tool search and `record_screen`, `defer_loading` stripped) counted through `count_tokens` with the key, else ESTIMATED as `[bytes/4, bytes/2.5]`, and the choice: ≤ 10000 all up front, > 10000 tool search, a straddle "undecided" |
| F1 C | a stand-in of its own answers `x-api-key: a0-not-a-dummy` 401, adds a failure, and logs the marker, never the value |
| T1r/d A, T2r/d A, T3r/d A | the stand-in's log (one models GET, two messages POSTs, the dummy only, no failures); the hook's order (`tool_request add_marker`, `tool_result` not an error, the scripted text, `turn_finished`) and the second POST's `tool_result` for `toolu_a0_1`; the marker in `get_project` |
| E1 C, E2 A | `export {preset:"h264"}` to a fresh path writes `ftyp` at byte 4; onto a file holding `A0-SENTINEL\n`, the result text and whether the file became a movie with nobody asked |
| D1 C, D2 A | `add_marker` with no gesture; `add_marker` between two ticks of a clip-body drag: present after tick 2 and after mouse-up, the clip's start, each Undo's name and the state after it |
| L1 C | with `ANTHROPIC_API_KEY` present, its bytes in no file under `tree/build/`, `tree/FrameJob.xcodeproj/`, `work/assistant_spike/` or road map 12 (only paths printed); absent, `skip — host: no key` |

## Output and exit

One line per row, `<ID> <pass|fail|skip> <I|C|A> — <reason with the
numbers>` (a row `--only` did not measure is marked `[carried from <date>]`),
then `scores: …` and `digest: <sha256 of the sorted "ID=state\n" lines>`.
Exit `0`: every row has a state and no I or C row failed; `1`: one did; `2`:
a row has no state (`SPIKE INCOMPLETE: <ids>`).

`work/assistant_spike/` is untracked: `tree/`, `probe/`, `runs/{r,d}/` (the
app log, `hook.jsonl` and its `.stderr`, the stand-in's `requests.jsonl`, the
package, the exports), `runs.json`, `f1/`, `h6/` and `answers.json` (host,
rows with their measurements and dates, the digest).

## What it never does

It never writes the tree's `app/`, `core/`, `graphic/`, `docs/`,
`project.yml` or `Makefile`, never writes `~/devel/rasterize`, and never
kills a process it did not start. Every child gets the runner's own
`child_env()` — `bounded.child_env` with `ANTHROPIC_API_KEY` popped too —
passed explicitly; the helper only ever gets `proof-key`. The key is read in
one function, `anthropic_key()`, sent only as a header to `count_tokens`,
and only `present`/`absent` is printed. Walls: build 1500 s, bun install
300 s, launch 60 s, turn 90 s, export 300 s, probe build 900 s, probe run
180 s.
