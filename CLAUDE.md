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
history.** A road map in progress lives in `designs/`, and its own document
holds each phase's record — what landed, what was measured, what its review
found, what is owed — including the past of any file the phase changed. When
a road map closes: condense it into `designs/adr/<name>.md` (any existing ADR
is the template), file each unfinished item as a GitHub issue (reviewed
against the tree first), `git mv` the original into `archive/`, and add its
row to `archive/INDEX.md`. Update a map entry or a rule when a phase
changes a file's role or adds a rule. Never append a status paragraph here.

**`archive/` is historical.** Don't consult it unless asked, or unless you
need to know why an earlier phase made a particular decision — and even then
read the condensed record in `designs/adr/` first; its "Where to look in the
original" section says which archived section holds the detail. The index is
`archive/INDEX.md`. Update `archive/INDEX.md` with each added file. A code
comment citing "road map N §x" refers to the archived original.

## Where to look

| Document | What it is |
|---|---|
| `designs/spec/` | **The normative spec, one file per section — never read it whole.** Start at its `README.md` (the index: each file, its size, what it answers), then read only the file you need; "spec §7.3" is `07.3-frame-recipe.md`. §5 schemas, §6 op table, §7 architecture, §9 keys and menus, §10 acceptance steps, §11 decisions already made — not to be re-litigated, indexed by ID in `11-decisions/README.md`. An ADR cites §11's IDs; it never replaces them. |
| GitHub issues | **What is left**, and the one place it is kept: open defects, proof residue, candidates, accepted limits, work the user deferred (`gh issue list`), and one-off asks of the owner — a spend, a choice, a permission an agent was refused (`--label ready-for-human`). Nothing open is tracked in a document. |
| `docs/manual-checks.md` | **What only a person at the machine can confirm**, as a standing list the owner runs periodically and before every release — not open work, so not an issue. A change that creates such a check adds or edits its row in the same change. |
| `designs/adr/` | One condensed decision record per closed road map, survey or file history: why the code is the shape it is. Start with the one for the area: `roadmap-03` the recorder · `roadmap-04` `detect_silence` · `roadmap-05` transitions and `video.motion` · `roadmap-06` transcription (C2, the relay, designed and deferred) · `roadmap-07` how a patch is checked, what an op answers, where its arguments are written down, the source window, the argument gate · `roadmap-08` word captions · `roadmap-09` the Clip tab, the action lane, band drags · `roadmap-10` graphics · `roadmap-11` the dev tools (snapshot_ui, perform_menu_item, the screen catalog) and `make dist` · `roadmap-12` the assistant (the bundled helper, the agent lane, withheld and ask-first tools, the Assistant tab and its prompt) · `app-file-history` / `core-file-history` why a file or module is cut where it is, and its named next cut · `rust-build-settings` why release builds are incremental with no LTO · `effects-survey` E3–E9 (deferred by the user) and **the Concat rule: it is AGPL-3.0; none of its code, shaders, chains or colour tables may be carried over** · `remaining-closed` the debts already paid. |
| `designs/design_handoff_reelcut/` | The shipped chrome cleanup and identity; its README is normative for the redesign's metrics. |
| `designs/design_handoff_reelcut_sharp/` | The sharp pass (2026-09-23): square chrome, 2 pt clips, the zoom slider's block knob. Its README is normative for radii and the knob, with spec §11 SH-1 and SH-2 as the deviations. |
| `designs/design_handoff_clip_inspector/` | The clip inspector handoff road map 9 built from; `designs/adr/roadmap-09-clip-inspector.md` records the deviations. |
| `designs/screens/` | The screen catalog (road map 11's V3). One file per screen: a JSON front block (the fixture, the MCP steps that reach it, the captures) and prose for a designer. `tools/proof/screens.py` captures them light and dark into `tools/proof/work/screens/<date>/screens.md`; its `README.md` has the format and how to add a screen. |
| `tools/proof/README.md` | The proof scripts, the MCP client and the offscreen harness. |
| `README.md` | User-facing. |

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # make rust, cd core && cargo test --release, cd graphic && cargo test --release (black-box tests), then tools/proof/assistant_lane_proof.py (the agent lane's probe) and tools/proof/assistant_prompt_proof.py --probe (the prompt texts' drift checks)
make lint       # cargo clippy --all-targets -- -D warnings, in core/ then graphic/
make typecheck  # swiftc -typecheck -D REELCUT_DEV_TOOLS of app/Sources/*.swift — the ONLY authoritative Swift check, then agent/'s `tsc --noEmit` (through bun)
make project    # xcodegen generate (Reelcut.xcodeproj is generated; project.yml is the source of truth)
make run        # make app, then launch
make dist       # make app, then the Distribution build (no dev tools, spec §11 V-1) and tools/proof/dist_check.py
```

- Single Rust test: `cd core && cargo test --release --test edge slip`
  (test-file name, then a name filter). Finish Rust work with `cargo fmt` in
  `core/` (and `graphic/`) and a clean `make lint`.
- There are no Swift unit tests. App-side verification is `make typecheck`
  plus driving the built app over MCP and the probes in `tools/proof/`.
- `make typecheck` is fast; run it before `make app` (~90 s). Its baseline is
  **0 errors and 7 warnings**, and tsc prints no error; the warnings are
  all AVFoundation deprecations: 4 (3 in
  `CompositionBuilder.swift`, 1 in `Exporter.swift`) deliberate because
  their replacements are `async`-only and `async` is confined to
  `MediaImporter.swift` and `SpeechEngine.swift` (spec §11 W-8), and 3
  `AVMutableVideoComposition` deprecations
  that came with the macOS 26 minimum (`Playback.swift`,
  `ExporterWriter.swift`, `CompositionBuilder.swift`; road map 8 §10.4),
  whose replacement `AVVideoComposition.Configuration` was not taken with
  the bump. Any eighth warning is new and yours. It stops before
  SILGen, so a clean typecheck does not prove the app builds; only `make app`
  does.
- `make app`/`make dist` build the assistant helper (`agent/`) in their
  last Xcode step, and `make typecheck` ends with its tsc. All need bun, and
  without it they fail with an `error: bun is not installed` line rather
  than skipping.
- `Reelcut.xcodeproj` is generated; never commit it. xcodegen and
  `make typecheck` both glob `app/Sources/`, so a new Swift file needs no
  registration anywhere.

## File map

```
core/                Rust staticlib — the model, the ops, the plan, the recipe,
  include/…_core.h     export settings, the generic MCP server. THE FFI CONTRACT
  src/                 core/CLAUDE.md has the module map
  tests/               black-box, through the FFI
graphic/             Rust crate — the graphics engine (road map 10): a Module run in
  src/                 sandboxed QuickJS returns SVG per frame; rasterize (usvg →
  tests/               resvg → BGRA), measure_text. graphic/CLAUDE.md has its rules
agent/               the assistant helper (AI-1): Bun, the Anthropic SDK's Tool Runner
  src/                 meant to be byte-identical to ~/devel/rasterize/agent/src/, one
                       diff applied to both; NOT YET: Rasterize lacks road map 12 §2's
                       change until #147 lands. What the apps differ in arrives in
                       `configure`
  build.sh             used by the Xcode step and `make typecheck`
app/
  Sources/             AppKit app, programmatic UI (app/CLAUDE.md has the map)
  Resources/Shaders/   Compositor.metal — the per-layer compositing pass
  Resources/Models/    silero_vad.mlmodelc, vendored compiled (PROVENANCE.md)
  Bridging/            the bridging header importing core/include/reelcut_core.h
designs/             the spec, adr/ (condensed records), the handoffs — the table above
archive/             closed road maps and histories, verbatim; INDEX.md — read only when asked
docs/agents/         what the engineering skills read: tracker, labels, domain docs
docs/graphics-api.md the graphics reference an agent reads; graphic/tests/reference.rs runs every js block
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
- A handle is an immutable project. **Every edit is pure and answers one of
  three arms** (`core/src/outcome.rs`, spec §5.5): applied with the new
  project, an identity, or refused in the rule's own sentence. Only the first
  is an undo step. `ProjectDocument` is the single mutation point and undo is
  its stack of handles.
- Edits are JSON ops through `rc_project_apply`. **The op table is two
  halves**: what an op MEANS is the module doc of `core/src/edit.rs`, and
  what it TAKES — every argument's name, kind and required-ness — is
  `core/src/op_table.rs`, as data, published as JSON Schema by
  `rc_op_schemas`. `ReelOps.swift`'s typed builders,
  `AgentCatalog*.swift`'s tools and spec §6 mirror them — change one, change
  all four — **except that every op TOOL prints the arguments half instead of
  restating it** (`AgentCatalog.opTool`), so an argument added to an op costs
  a sentence of prose there and no schema. A tool that takes more or less
  than its op does says so in `AgentCatalog+Declarations.swift`, one row and
  one reason each. The envelope's `scope` key addresses an edit inside a
  nest.
- Persisted-state changes bump `RC_FORMAT_VERSION` in `core/src/format.rs`
  **and** the header.
- Errors: `rc_project_apply` returns NULL three distinguishable ways, and the
  two message channels are never both written. NULL with NEITHER written is
  an identity; NULL with `reason_out` set is a refusal and that string is the
  rule's own sentence; NULL with `err_out` set is invalid input. The first two
  make no undo step and only the third is an error. `"internal error: …"` is a
  caught panic.

### Where a feature lands — the standard recipe

Every shipped feature follows the same shape; putting a step's code anywhere
else is what bloats files:

1. **Core:** the op's semantics in an `impl Project` block in the module of
   its own concern (a new concern is a new module); the row in `edit.rs`'s
   enum and module-doc table, and its arguments in `op_table.rs` (which is
   where `OP_NAMES` comes from); a persisted field with a serde default and a
   `schema_vN.rs`; a new `core/tests/*.rs`. A field lands in the same phase as
   the thing that renders it.
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
  in `AgentServer.start()` has FIVE parts: catalog names against handler
  names, every op in the core's table against the tools (through
  `rc_op_names`, with an explicit allow-list for ops that deliberately have
  none), each tool's schema shape, that every op tool declares `scope`, and
  that every op tool declares the CORE's own arguments for its op — each one
  described, and no description for an argument no op has
  (`AgentServer+Parity.swift`). What it cannot see is a CALL, which two
  things guard at dispatch: the argument GATE in `AgentServer+Gate.swift`
  compares the caller's keys to the schema the tool published and refuses a
  stranger by name, for all eighty-five product tools (and the dev tools, road map 11),
  before any handler runs;
  and the throwing helpers in `AgentServer+Arguments.swift` refuse a value a
  handler cannot read by name rather than dropping it.
- **A file at the ~600-line cap gives something up before it takes anything
  on**, as a pure move landed and gated alone; new files are capped at 400
  lines. Frozen files take wiring only. `core/src/edit.rs` and
  `app/Sources/ReelOps.swift` are exempt (tables, one row per op), and proof
  instruments in `tools/proof/` are held to neither cap. The ledger is
  `wc -l app/Sources/*.swift core/src/*.rs graphic/src/*.rs | sort -rn`; the
  seam a record already named for a file is under "Named next cuts" in
  `designs/adr/app-file-history.md` / `core-file-history.md`.
- **A decision in spec §11 is not re-litigated** (`designs/spec/11-decisions/`). A phase that needs a new
  one records it there before the code, not after.
- **`.secrets/` (gitignored) holds the owner's own keys for proofs**, e.g.
  `.secrets/anthropic-key`, read ONLY by `anthropic_key()` in
  `tools/proof/assistant_prompt_eval.py`. Never open, print, grep, copy or
  list its contents; never move a key from it into an argument, the
  environment of a build, a log or a file. A run that spends money still
  needs its explicit flags (`--live --cap <dollars>`); the file's presence
  spends nothing.
- **A check only a person at the machine can make is a row in
  `docs/manual-checks.md`**, added in the change that creates it — never a
  `ready-for-human` issue, and never an instrument built to stand in for the
  person (how a pane looks, whether audio plays, a real key's conversation).
  Automate what a script can truly measure; list only the residue.
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
`undo`, `redo`, `render_frame`, `export`, `record_screen`, `write_graphic`,
`get_graphic`, `graphic_reference`, `render_graphic`, `import_graphic_font`
and `import_graphic_asset`. A Release build also has the dev tools
(`snapshot_ui`, `perform_menu_item`, `cancel_sheet`, `select_inspector_tab`;
"Seeing the chrome" below; and `assistant_send` / `assistant_answer`, which
drive a window's assistant turn against a stand-in server, with the dev-only
launch default `-RCDevAssistantSend <text> -RCDevAssistantReport <path>` for
a turn in a launch without the server), which Distribution does not. `rc_op_names`
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

Spec §10's per-step verifications are the acceptance tests. What no script
can answer — step 4's "the clip plays with audio", step 5's 60 fps, and the
rest — is a row in `docs/manual-checks.md`, which the owner runs.

## Seeing the chrome

`screencapture` needs a Screen Recording grant the agent's terminal does not
have, and it silently writes a black PNG. The way to LOOK at the chrome is
**`tools/proof/harness/`**: it compiles every file in `app/Sources` except
`main.swift` with a `main.swift` of its own, links the staticlib, opens a
`.reelcut` package, puts an `EditorViewController` in an `NSWindow` and
`cacheDisplay`s it into a PNG at the display's backing scale — the same paint
path the window uses, no TCC grant, either appearance, captured on SETTLE.
The preview well comes out as the canvas background (an `AVPlayerLayer` or
Metal layer does not draw into `cacheDisplay`), so nothing about the PICTURE
is ever claimed offscreen; pixel claims go over MCP. `tools/proof/README.md`'s
"offscreen harness" section has the build line, the argument list and the
pinned `UserDefaults`.

To look at the LIVE app, a Release build (the one `make app` builds, never
Distribution) has dev tools over MCP (road map 11, spec §11 V-1).
`snapshot_ui` captures the editor, a sheet, Settings, Welcome or the recorder panel, with a
layout dump. `perform_menu_item` runs a menu item by path to put a sheet or
Settings up, `cancel_sheet` closes the sheet, and `select_inspector_tab`
picks an inspector tab and sub-tab. All four work with the
app inactive and its window covered. A capture's look is set at launch with
the dev-only `-RCDevAppearance light|dark`, never switched live. To see every
catalogued screen at once, `python3 tools/proof/screens.py` walks
`designs/screens/`, once per look, each time on its own pinned instance. It
writes each screen's PNGs and layout dumps and one `screens.md` with the
prose and each capture's layout problems. The last screen is the recorder
panel, which brings Reelcut to the front with Record on Return, so the
script stops each instance straight after capturing it.

Two rules from it worth carrying into any proof: **identical, stable,
DIFFERENT output across processes is an Auto Layout ambiguity to find, not a
race to out-wait** — reach for constraint priorities, not for more run-loop
turns; and **when the thing to check is app ARITHMETIC or app STRUCTURE with
no caller a script can reach** (a menu, a validator, a cue builder, a queue),
the answer is a probe compiled from `app/Sources` over `harness/build.sh`'s
own `swiftc` line, not a photograph. A probe that will not build is a scored
FAILURE, never an exit, so a rotted instrument cannot take a score down with
it. **That rule applies to historical instruments too.** The meter and welcome
comparisons build old `app/Sources` with the matching old core and header in
isolated output directories, using the current guarded `harness/main.swift`
for both paints. A failed current or reference build is a scored failure,
including an FFI diagnostic; it is never a historical skip or a reason to
fall back to the old harness. Only the recording proof's granted tier can
skip rows for a named host condition such as a locked console.

## Agent skills

### Issue tracker

GitHub Issues on `kpgalligan/reelcut`, through the `gh` CLI. See `docs/agents/issue-tracker.md`.
**Every issue an agent creates carries the `ai-drafted` label**, beside any
triage label: `gh issue create --label ai-drafted …`. **It also carries
`low-priority` unless it is urgent** — data loss or a corrupt project reachable
in ordinary use, a crash or hang reachable in ordinary use, a secret leak, or
something blocking other work now.

### Triage labels

The five default role strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md`, with spec §11 as the decision record in place of `docs/adr/`. See `docs/agents/domain.md`.
