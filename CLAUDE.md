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
| `designs/reelcut-remaining.md` | What is left: §3 the size-debt ledger a phase consults before paying a toll, §4 what only a person at the machine can check, §5 where the next road map starts, §6 the Rust build settings, measured, and the two `Cargo.toml` lines that landed from it. |
| `designs/reelcut-roadmap.md` | M1–M3: how each was proved, the known limits. |
| `designs/reelcut-roadmap-2.md` | Ten phases, all built. §0 is the rules every phase inherits; §2 holds each phase's record. |
| `designs/reelcut-roadmap-3.md` | Screen recording (R1) and pause/resume (R2), built. Start here for the recorder. |
| `designs/reelcut-roadmap-4.md` | Remove Silences judged by voice — Silero VAD through Core ML (S1), built and proved by `tools/proof/silence2_proof.py` and `silence2_probe.py`. Start here for `detect_silence`. |
| `designs/reelcut-roadmap-5.md` | Transitions second pass (E1) and motion presets (E2), built and proved. Start here for transitions or `video.motion`. |
| `designs/reelcut-roadmap-6.md` | Captions from the cloud (AssemblyAI): C1 built — §5 its specification, §10 its record per pipeline, §3 the spike C0 (instruments in `tools/proof/cloud_spike/`); C2, the relay, is designed in §6 and not built. Start here for transcription. |
| `designs/reelcut-roadmap-7.md` | The deepening series, FOUR candidates, all closed: §0 the rules it inherits (deep module, seam, the deletion test, the interface is the test surface); §1–§3 D1, the core as the one validator of a caller's patch (tickets #2–#7) — start here for how a patch is checked; §4–§6 D2, an op's three answers and the eleven rules that say why they refused (tickets #9–#13) — start here for what an op ANSWERS; §7–§9 D3, one op table published (tickets #15–#20) — start here for where an op's arguments are written down, and §9 for where a next candidate starts; §10 the SOURCE WINDOW candidate, split in three and CLOSED — §10.1–§10.5 the measured inventory of the `× speed` arithmetic, the three head/tail clamp forms and the two road-map-2 defects that are evidence for it, §10.6 what was decided and what each phase owns, §10.7 the record of phase A, the module `core/src/source_window.rs` as a pure move, §10.8 the record of phase B, the window invariant made true at every writer through that module's one bound (spec §11's D4-2 to D4-5), and §10.9 the record of phase C, the app's reversed mirror in one file and the Speed sheet's readout asked of the core (spec §11's D4-6) — start at §10.6, and at §10's closing paragraphs for what a next candidate would be; §11 the HANDLER-FORWARD candidate §9 recommends, MEASURED and retired — why forwarding a caller's whole op unread would cost 21 named refusals, 6 app-state defaults and one correctness guard, what the core's decoder actually says when asked, and the smaller shape the measurement points at, the argument GATE, which §11.8 records LANDED (kpgalligan/reelcut#21). **Read §11 before acting on §9's closing sentence.** |
| `designs/reelcut-roadmap-8.md` | Word captions — the social-video style (one row, pages filled to the MEASURED width, the spoken word highlighted, popped or pilled), from either engine: BUILT 2026-09-23, W0–W4b. §0 why a page is one text clip with its words timed inside it, §4 the decisions W-1..W-10 (W-8 moves the minimum to macOS 26 and the on-device engine to `SpeechTranscriber`), §5 the design (§5e the sheet's Style row, §5h the styles), §7 what is not built and why — where next work starts, §10 the record per phase (W0 §10.1 to W4b §10.10). Start here for word captions. |
| `designs/reelcut-roadmap-9.md` | The clip inspector redesign, from `designs/design_handoff_clip_inspector/`: five phases (1, 2, 3a, 3b, 4, 5), all BUILT 2026-09-23/24. §0 the phases, §1–§2 phase 1 (the selected action, the action lane, the timeline's bands; spec §11 CI-1..CI-4), §3–§4 phase 2 (the Clip tab's sub-tabs and the block pinned above the scroll view, the block knob; CI-5, CI-6), §5–§6 phase 3a (the row marks, the keyed segment and the playhead tick, auto-open; CI-7, CI-8), §7–§8 phase 3b (Reset/Clear, the row menus, the refusal strip; CI-9, CI-10), §9–§10 phase 4 (band drags in the lane and on the timeline, the lane's decor; CI-11, CI-12), §11–§12 phase 5 (canvas gestures following the mode, off, mixed, Reduce Motion; CI-13..CI-15). Each even section is that phase's record, deviations and owed items. Start here for the Clip tab, the action lane, a band drag or the canvas's edit target. |
| `designs/reelcut-roadmap-10.md` | Graphics — motion graphics drawn by code: a clip whose JavaScript module in the package's `graphics/` returns SVG per frame, run by QuickJS and rasterized by resvg in a separate `graphic/` crate. EXPERIMENTAL on the branch `svg-motion`: G0 spiked 2026-09-24; G1–G4 BUILT 2026-09-24/25 (the engine, the model, the picture, the agent's six tools; §10.4–§10.7 their records) — an agent can make a graphic end to end over MCP; merging into `main` is the user's decision; G5 BUILT 2026-09-25 (§10.9: the Clip tab's Graphic sub-tab, Insert ▸ Graphic with templates, File ▸ Add Font/Image to Graphics…, Help ▸ Graphics Reference) — a person can now make a graphic too; G6 only if the playback check stutters; §10.8 the graphics-only playback defect, owed. §1 reviews `designs/svg-motion-components-plan.md`, §3 the spike G0, §4 decisions G-1..G-13 (G-14..G-16 in spec §11) (G-1 and G-2 amend spec §1's plugin non-goal and §7's pixel rule), §5 the design, §9 the phases. Start here for graphics. |
| `designs/reelcut-effects-survey.md` | The survey road map 5 came from. E3–E9 (tone, filters, looks, adjustment clips, LUT import, voice effects, background removal) are DEFERRED by the user. Concat is AGPL-3.0: its behaviour was studied, and none of its code, shaders, chains or colour tables may be carried over. |
| `designs/reelcut-milestones.md` | The per-phase record this file carried until 2026-09-17, moved out verbatim. Not maintained. |
| `designs/design_handoff_reelcut/` | The shipped chrome cleanup and identity; its README is normative for the redesign's metrics. |
| `designs/design_handoff_reelcut_sharp/` | The sharp pass (2026-09-23): square chrome, 2 pt clips, the zoom slider's block knob. Its README is normative for radii and the knob, with spec §11 SH-1 and SH-2 as the deviations. |
| `tools/proof/README.md` | The proof scripts, the MCP client and the offscreen harness. |
| `README.md` | User-facing. |

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release, then cd graphic && cargo test --release  (black-box tests)
make lint       # cargo clippy --all-targets -- -D warnings, in core/ then graphic/
make typecheck  # swiftc -typecheck of app/Sources/*.swift — the ONLY authoritative Swift check
make project    # xcodegen generate (Reelcut.xcodeproj is generated; project.yml is the source of truth)
make run        # make app, then launch
```

- Single Rust test: `cd core && cargo test --release --test edge slip`
  (test-file name, then a name filter). Finish Rust work with `cargo fmt` in
  `core/` (and `graphic/`) and a clean `make lint`.
- There are no Swift unit tests. App-side verification is `make typecheck`
  plus driving the built app over MCP and the probes in `tools/proof/`.
- `make typecheck` is fast; run it before `make app` (~90 s). Its baseline is
  **0 errors and 7 warnings**, all AVFoundation deprecations: 4 (3 in
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
app/
  Sources/             AppKit app, programmatic UI (app/CLAUDE.md has the map)
  Resources/Shaders/   Compositor.metal — the per-layer compositing pass
  Resources/Models/    silero_vad.mlmodelc, vendored compiled (PROVENANCE.md)
  Bridging/            the bridging header importing core/include/reelcut_core.h
designs/             the spec, the road maps, the handoff — the table above
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
  stranger by name, for all eighty-five tools, before any handler runs;
  and the throwing helpers in `AgentServer+Arguments.swift` refuse a value a
  handler cannot read by name rather than dropping it.
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
`undo`, `redo`, `render_frame`, `export`, `record_screen`, `write_graphic`,
`get_graphic`, `graphic_reference`, `render_graphic`, `import_graphic_font`
and `import_graphic_asset`. `rc_op_names`
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

### Triage labels

The five default role strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md`, with spec §11 as the decision record in place of `docs/adr/`. See `docs/agents/domain.md`.
