# CLAUDE.md

Reelcut — a screencast-style video editor for macOS: a Swift/AppKit UI over a
Rust staticlib core, the same shape as `~/devel/rasterize`, whose three
`CLAUDE.md` files are the parent text for anything not settled here. It
builds and runs.

Per-side rules live next to the code they govern and are loaded on demand —
read them before writing code on that side:

- `core/CLAUDE.md` — Rust rules: module map, size, purity, errors, times, FFI
  exports, format versioning, tests.
- `app/CLAUDE.md` — Swift rules: file map (which files are frozen), undo and
  dirty tracking, agent parity, state flow, hygiene.

**These three files are the rulebook, and they hold no status and no
history.** A phase's record — what landed, what was measured, what its review
found, what is owed — goes in that road map's own document under `designs/`;
a file's past goes in `designs/reelcut-app-notes.md` or
`designs/reelcut-core-notes.md`. Update a map entry or a rule when a phase
changes a file's role or adds a rule. Never append a status paragraph here.

## Where to look

| Document | What it is |
|---|---|
| `designs/reelcut-design.md` | **The normative spec.** §5 schemas, §6 op table, §7 architecture, §9 keys and menus, §10 acceptance steps, §11 decisions already made — not to be re-litigated. |
| `designs/reelcut-remaining.md` | What is left: §3 the size-debt ledger a phase consults before paying a toll, §4 what only a person at the machine can check, §5 where the next road map starts. |
| `designs/reelcut-roadmap.md` | M1–M3: how each was proved, the known limits. |
| `designs/reelcut-roadmap-2.md` | Ten phases, all built. §0 is the rules every phase inherits; §2 holds each phase's record. |
| `designs/reelcut-roadmap-3.md` | Screen recording (R1) and pause/resume (R2), built. Start here for the recorder. |
| `designs/reelcut-roadmap-4.md` | Remove Silences judged by voice — Silero VAD through Core ML (S1), built; its own proof scripts are still owed. Start here for `detect_silence`. |
| `designs/reelcut-roadmap-5.md` | Transitions second pass (E1) and motion presets (E2), built; their proof scripts are still owed. Start here for transitions or `video.motion`. |
| `designs/reelcut-roadmap-6.md` | Captions from the cloud (AssemblyAI), DESIGNED and not built; its spike C0 has not run. Start here for transcription. |
| `designs/reelcut-roadmap-7.md` | The deepening series: §0 the rules it inherits (deep module, seam, the deletion test, the interface is the test surface), §1 D1's plan — the core as the one validator of a caller's patch, tickets #2–#7 — §2 each ticket's record, and §3 what D1 added up to, CLOSED. Start here for how a patch is checked or refused. |
| `designs/reelcut-effects-survey.md` | The survey road map 5 came from. E3–E9 (tone, filters, looks, adjustment clips, LUT import, voice effects, background removal) are DEFERRED by the user. Concat is AGPL-3.0: its behaviour was studied, and none of its code, shaders, chains or colour tables may be carried over. |
| `designs/reelcut-milestones.md` | The per-phase record this file carried until 2026-09-17, moved out verbatim. Not maintained. |
| `designs/design_handoff_reelcut/` | The shipped chrome cleanup and identity; its README is normative for the redesign's metrics. |
| `tools/proof/README.md` | The proof scripts, the MCP client and the offscreen harness. |
| `README.md` | User-facing. |

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release  (black-box tests through the FFI)
make lint       # cargo clippy --all-targets -- -D warnings
make typecheck  # swiftc -typecheck of app/Sources/*.swift — the ONLY authoritative Swift check
make project    # xcodegen generate (Reelcut.xcodeproj is generated; project.yml is the source of truth)
make run        # make app, then launch
```

- Single Rust test: `cd core && cargo test --release --test edge slip`
  (test-file name, then a name filter). Finish Rust work with `cargo fmt` in
  `core/` and a clean `make lint`.
- There are no Swift unit tests. App-side verification is `make typecheck`
  plus driving the built app over MCP and the probes in `tools/proof/`.
- `make typecheck` is fast; run it before `make app` (~90 s). Its baseline is
  **0 errors and 4 warnings**, all AVFoundation deprecations (3 in
  `CompositionBuilder.swift`, 1 in `Exporter.swift`), deliberate because
  their replacements are `async`-only and `async` is confined to
  `MediaImporter.swift`. Any fifth warning is new and yours. It stops before
  SILGen, so a clean typecheck does not prove the app builds; only `make app`
  does.
- `Reelcut.xcodeproj` is generated; never commit it. xcodegen and
  `make typecheck` both glob `app/Sources/`, so a new Swift file needs no
  registration anywhere.

## File map

```
core/                Rust staticlib — the model, the ops, the plan, the recipe,
  include/…_core.h     export settings, the generic MCP server. THE FFI CONTRACT
  src/                 core/CLAUDE.md has the module map
  tests/               black-box, through the FFI
app/
  Sources/             AppKit app, programmatic UI (app/CLAUDE.md has the map)
  Resources/Shaders/   Compositor.metal — the per-layer compositing pass
  Resources/Models/    silero_vad.mlmodelc, vendored compiled (PROVENANCE.md)
  Bridging/            the bridging header importing core/include/reelcut_core.h
designs/             the spec, the road maps, the handoff — the table above
docs/agents/         what the engineering skills read: tracker, labels, domain docs
tools/proof/         mcp.py, the per-phase proof scripts, harness/ (offscreen chrome)
project.yml          xcodegen definition; Makefile; README.md (user-facing)
```

## Architecture

**Rust decides, AVFoundation and Metal do** (spec §7). The core holds the
project (JSON, spec §5.2), every edit, the composition plan and the per-frame
recipe. Swift owns windows, gestures, undo, AVFoundation playback and export,
the Metal compositor, media import and its caches, and agent dispatch. No
pixel or sample work in Rust; no ffmpeg dependency in the product.

### FFI contract

- `core/include/reelcut_core.h` is a **hand-maintained** C header, the single
  contract between the worlds. **The FFI is three files in lockstep**: a Rust
  `#[no_mangle]` export, its entry in the header, and its wrapper in
  `app/Sources/ReelCore.swift` — **the only file that calls `rc_*`**.
- A handle is an immutable project. **Every edit is pure and returns
  `Option`** (identity or a documented refusal = `None`, no undo step).
  `ProjectDocument` is the single mutation point and undo is its stack of
  handles.
- Edits are JSON ops through `rc_project_apply`. **The op table is the module
  doc of `core/src/edit.rs`**; `ReelOps.swift`'s typed builders,
  `AgentCatalog*.swift`'s tools and spec §6 mirror it — change one, change
  all four. The envelope's `scope` key addresses an edit inside a nest.
- Persisted-state changes bump `RC_FORMAT_VERSION` in `core/src/format.rs`
  **and** the header.
- Errors: NULL with `err_out` untouched is a refusal or an identity; `err_out`
  set is invalid input; `"internal error: …"` is a caught panic.

### Where a feature lands — the standard recipe

Every shipped feature follows the same shape; putting a step's code anywhere
else is what bloats files:

1. **Core:** the op's semantics in an `impl Project` block in the module of
   its own concern (a new concern is a new module); the row in `edit.rs`'s
   enum, `OP_NAMES` and module-doc table; a persisted field with a serde
   default and a `schema_vN.rs`; a new `core/tests/*.rs`. A field lands in the
   same phase as the thing that renders it.
2. **FFI**, only when a new `rc_*` export is needed: Rust → header →
   `ReelCore.swift`.
3. **Swift:** the typed builder in `ReelOps.swift`; a small value or model
   file; an `EditorViewController+<Feature>.swift` with its validator arm; an
   inspector section REGISTERED in `ClipPane.makeSections()`; a menu item in
   `AppDelegate+Menus.swift`; a gesture as a session struct.
4. **MCP mirror:** a handler in `AgentServer+<Feature>.swift`, a catalog entry
   declaring `scope`, and a comment naming the UI path it mirrors.
5. **Documents:** spec §5.2 / §6 / §7.10 for anything they mirror; the map
   entry in the per-side `CLAUDE.md` if a file's role changed; the README's
   feature bullets; the phase's record in its road map.
6. **Verify:** `make test`, `make lint`, `make typecheck`, `make app`; then a
   proof script in `tools/proof/` that has been made to fail on purpose; then
   read the change back adversarially before committing.

## Rules

- Conventions are Rasterize's — `~/devel/rasterize`'s three `CLAUDE.md`
  files are the parent text for anything not settled here.
- **Every user-visible edit gets an MCP mirror** (spec §7.9): a handler, a
  catalog entry, and a comment naming the UI path. The startup parity check
  in `AgentServer.start()` has FOUR parts: catalog names against handler
  names, every op in the core's table against the tools (through
  `rc_op_names`, with an explicit allow-list for ops that deliberately have
  none), each tool's schema shape, and that every op tool declares `scope`.
  It cannot see argument TYPES — the throwing helpers in
  `AgentServer+Arguments.swift` are the guard for those: a value a handler
  cannot read is refused by name, never dropped.
- **A file at the ~600-line cap gives something up before it takes anything
  on**, as a pure move landed and gated alone. `designs/reelcut-remaining.md`
  §3 is the ledger; new files are capped at 400 lines.
- **A decision in spec §11 is not re-litigated.** A phase that needs a new
  one records it there before the code, not after.
- Commit only when asked. A commit message says what was verified and what
  is owed, and the road map's record says the same.

## Verifying a build

The app is verified by driving the built binary over MCP and comparing what
it renders — not by reading code. Launch your own instance on your own port
and only ever kill that one (`pgrep -f "MacOS/Reelcut"` lists them; another
session may have one running):

```sh
make app
(RC_AGENT_PORT=4817 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4817.log 2>&1 &)
```

The log line names the port it actually bound (a taken port falls back to an
ephemeral one). Drive it with any MCP client over streamable HTTP at
`http://127.0.0.1:<port>/mcp`: one tool per §6 op, each taking the `scope`
envelope key, plus the app-state tools — `open_project`, `new_project`,
`save_project`, `get_project`, `import_media`, `import_captions`,
`export_captions`, `transcribe`, `consolidate_media`, `detect_silence`,
`normalize_clip`, `set_playhead`, `set_range`, `set_selection`, `set_scope`,
`undo`, `redo`, `render_frame`, `export` and `record_screen`. `rc_op_names`
and the catalog are the authority for the counts; the parity check compares
them at startup. `render_frame` writes a PNG and returns its path; `export`
waits for the file.

**Before trusting any MCP proof, `grep "Reelcut: " /tmp/reelcut-<port>.log`
must print nothing** — that prefix is the startup parity check complaining.

**`tools/proof/` holds the scripts that do this** — an MCP script per phase
over a dependency-free client (`mcp.py`), and beside most of them an
offscreen-chrome script or a probe. Every claim in them is a placement read
back through `get_project`, a BYTE comparison of two PNGs, or a
sample-for-sample comparison of two exports decoded to PCM (which needs
`ffmpeg` at proof time). Its README says how to make the test media, run
one, and which scores are known host-state skips (a locked console, a
Bluetooth output). Add the next phase's proof there rather than writing a
throwaway. An instance DEADLOCKS somewhere past forty open documents,
because nothing closes one: relaunch between proof sessions.

Spec §10's per-step verifications are the acceptance tests. Still unchecked
by a human: step 4's "the clip plays with audio" and step 5's 60 fps, which
no still frame can answer; `designs/reelcut-remaining.md` §4 lists the rest.

## Seeing the chrome

`screencapture` needs a Screen Recording grant the agent's terminal does not
have, and it silently writes a black PNG. The way to LOOK at the chrome is
**`tools/proof/harness/`**: it compiles every file in `app/Sources` except
`main.swift` with a `main.swift` of its own, links the staticlib, opens a
`.reelcut` package, puts an `EditorViewController` in an `NSWindow` and
`cacheDisplay`s it into a PNG at the display's backing scale — the same paint
path the window uses, no TCC grant, either appearance, captured on SETTLE.
The preview well comes out black (a Metal layer has no drawable offscreen),
so nothing about the PICTURE is ever claimed offscreen; pixel claims go over
MCP. `tools/proof/README.md`'s "offscreen harness" section has the build
line, the argument list and the pinned `UserDefaults`.

Two rules from it worth carrying into any proof: **identical, stable,
DIFFERENT output across processes is an Auto Layout ambiguity to find, not a
race to out-wait** — reach for constraint priorities, not for more run-loop
turns; and **when the thing to check is app ARITHMETIC or app STRUCTURE with
no caller a script can reach** (a menu, a validator, a cue builder, a queue),
the answer is a probe compiled from `app/Sources` over `harness/build.sh`'s
own `swiftc` line, not a photograph. A probe that will not build is a scored
FAILURE, never an exit, so a rotted instrument cannot take a score down with
it.

## Agent skills

### Issue tracker

GitHub Issues on `kpgalligan/reelcut`, through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default role strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md`, with spec §11 as the decision record in place of `docs/adr/`. See `docs/agents/domain.md`.
