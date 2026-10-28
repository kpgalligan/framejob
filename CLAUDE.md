# CLAUDE.md

Frame Job — a video editor for macOS: a Swift/AppKit UI over a
Rust staticlib core, the same shape as `~/devel/rasterize`, whose three
`CLAUDE.md` files are the parent text for anything not settled here. It
builds and runs.

Per-side rules live next to the code they govern and are loaded on demand —
read them before writing code on that side:

- `core/CLAUDE.md` — Rust rules: module map, size, purity, errors, times, FFI
  exports, format versioning, tests.
- `app/CLAUDE.md` — Swift rules: file map (which files are frozen), undo and
  dirty tracking, agent parity, state flow, hygiene.
- `mcp-proxy/CLAUDE.md` — `framejob-mcp`'s rules: module map, stdout as
  protocol only, what never launches Frame Job, the launch lock, tests.

**These files are the rulebook, and they hold no status and no
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
| `designs/adr/` | One condensed decision record per closed road map, survey or file history: why the code is the shape it is. Start with the one for the area: `roadmap-03` the recorder · `roadmap-04` `detect_silence` · `roadmap-05` transitions and `video.motion` · `roadmap-06` transcription (C2, the relay, designed and deferred) · `roadmap-07` how a patch is checked, what an op answers, where its arguments are written down, the source window, the argument gate · `roadmap-08` word captions · `roadmap-09` the Clip tab, the action lane, band drags · `roadmap-10` graphics · `roadmap-11` the dev tools (snapshot_ui, perform_menu_item, the screen catalog) and `make dist` · `roadmap-12` the assistant (the bundled helper, the agent lane, withheld and ask-first tools, the Assistant tab and its prompt) · `roadmap-13` pricing and spend (LiteLLM's table, the price function in the helper and the proofs, the spend ledger, the proofs' budgets, the tab's and Settings' spend figures) · `roadmap-14` the agent socket (the Unix socket, `framejob-mcp` and its catalog snapshot, a tool call never asking, Copy MCP Command) · `mattes` the matte track (MT-1..MT-7): a track that cuts the one behind it, the recipe's matte roles, the compositor's matte pass, the chrome · `precision` the 16-bit-float compositor, deep decode and the 10-bit exports (PR-1..PR-5) · `precision-2` the paths PR-5 left 8-bit (PR-6..PR-8, #257): a deep still drawn at 16-bit float, the 10-bit reverse (HEVC Main 10, ProRes 422 at an odd size) keeping the source's colour labels, 10-bit `hevc_alpha` and recording not wanted · `grading` the grading road map (GR-1..GR-9): tone at step 4c, adjustment clips, looks and `.cube` LUTs at 4d, Show Ungraded and the waveform, the owner's trial and verdict, and format 15's renumbering of the branch's 1015 · `grading-2` grading tier 2 (GR-10..GR-14): the scopes and their counting rule, the wheels at 4c.1, the curves' strip at 4c.2, qualifiers and Show Selection on adjustment clips, formats 16–18 · `grading-3` grading tier 3 (GR-15..GR-20): honest sources and Frame Job's own HDR→SDR at step 0 (`ConvertingCompositor`, chosen per composition), camera log on the media (`media.color`, `set_media_color`, Apple Log and Apple Log 2 detected, format 19), linear light and the HDR timeline deferred (since built by `hdr`), wide gamut for SDR projects not wanted · `grading-4` grading tier 4 (GR-24..GR-35): the vectorscope zoom counted at the zoom and its same-bin add, Hue vs Hue and Hue vs Sat curves with the curve editor's hover readout and ⇧ axis lock, Color's Hue as the exact HSV shift, curves of different point counts blended in an action, the qualifier's cleanup blur, formats 20–21, and an Offset wheel, picture-clip qualifiers, 1,024-level scopes and a histogram behind the curves not wanted · `rename` the product's name, Frame Job (NM-1..NM-11): the spelling table, what history keeps, the residue check `name_residue.py` and its pins, no migration code, the owner's hand steps, the Rasterize side's three lines · `rename-2` the old name out of what is not history (NM-12..NM-14): the archive's and the handoffs' new names and the link rule, the issue rule, the prose rule and its kept classes, `TEXT_HISTORY`, the sweep, the safety nets, dropped by #288 except where an old tree needs them (NM-15) · `build-velocity` the probe builder (`swift_build.py`), the Debug app and its identity, the stale refusals (`proof_app.py`), Debug against Release, the gate · `app-file-history` / `core-file-history` why a file or module is cut where it is, and its named next cut · `rust-build-settings` why release builds are incremental with no LTO · `effects-survey` E3–E9 (deferred by the user) and **the Concat rule: it is AGPL-3.0; none of its code, shaders, chains or colour tables may be carried over** · `audio-sync` Synchronize Audio (SY-1..SY-22): round 1 the anchor rule (a clip with video stays), frame-snapped `move_clip`, drift corrected by `set_speed` at varispeed under a significance test; round 2 (the owner's real project) standardised MFCC features matched on speech frames, played windows first, confident and weak tiers (the Weak match sheet, `accept_weak`), the head trim, GCC-PHAT refinement, a robust drift line, and the analysis off the main thread behind the Synchronizing Audio sheet · `hdr` the HDR road map (H-0..H-7, HD-1..HD-17): the PQ peak read at import (#281), the HLG working space and SDR lifted to 203 cd/m², the deliverables (HLG, HDR10, the SDR version) and Show SDR Version, HDR scopes, opt-in linear-light blending (`canvas.blending`), Canon Log 2 and 3 with Cinema Gamut, formats 22–25 · `cut-by-transcript` Remove Filler Words and `get_transcript` (TR-1..TR-14): fillers from AssemblyAI's `disfluencies`, kept out of captions, cut on the 32 ms grid by `detect_fillers` and one `ripple_delete_ranges` (an agent's step named "Ripple Delete"), filler removal cloud-only, false starts through the assistant, `get_transcript`'s `from`/`to` window and its per-media on-device cache · `speed-ramps` speed ramps (SR-1..SR-22, #111): a ramp as a Speed action on the action lane, the clip keeping its slot and an edit past the media's end refused naming the rate that fits; `end.speed`, the source map S in closed form (`speed_map.rs`), per-frame video segments, format 27; ramp audio rendered offline into `cache/ramp-audio/` as one ×1 segment (a Kaiser-windowed-sinc tape glide with Keep pitch off, Apple's time-pitch in rate mode with a 56 ms lead with it on), the five spikes that chose it and the ≈ 22 ms lateness after a deep slow-down the owner accepted; edits, scaling and carries through S; `rc_project_source_map` and Swift's readers; the Speed section's Rate inside an action, the ×12 question for an end rate, and `set_action` refusing only a further overrun · `camera-recording` camera recording (CAM-1..CAM-11): a camera alone or beside a screen recording through the one recorder panel and `record_screen`; `AVAssetWriter` and the warm-up hold; the landscape best format and the Format popup; the preview on the prepared capture and one shared session queue (#373); hot-plug; E2 and the frame watch off the stream for a resume; the front Camera track in the bottom-right corner; the "Record the camera too" box · `camera-recording` camera recording (CAM-1..CAM-11): a camera alone or beside a screen recording through the one recorder panel and `record_screen`; `AVAssetWriter` and the warm-up hold; the landscape best format and the Format popup; the preview on the prepared capture and one shared session queue (#373); hot-plug; E2 and the frame watch off the stream for a resume; the front Camera track in the bottom-right corner; the "Record the camera too" box · `remaining-closed` the debts already paid. |
| `designs/design_handoff_chrome/` | The shipped chrome cleanup and the old identity; its README is normative for the redesign's metrics. |
| `designs/frame-job/` | The owner's Frame Job icon and mark (spec §11 NM-11): `frame-job-icon.svg` is `BrandMark`'s geometry, `AppIcon.appiconset` the app's icon set. |
| `designs/design_handoff_sharp/` | The sharp pass (2026-09-23): square chrome, 2 pt clips, the zoom slider's block knob. Its README is normative for radii and the knob, with spec §11 SH-2 as the deviation (SH-4 squared `StickerButton`, superseding SH-1). |
| `designs/design_handoff_clip_inspector/` | The clip inspector handoff road map 9 built from; `designs/adr/roadmap-09-clip-inspector.md` records the deviations. |
| `designs/screens/` | The screen catalog (road map 11's V3). One file per screen: a JSON front block (the fixture, the MCP steps that reach it, the captures) and prose for a designer. `tools/proof/screens.py` captures them light and dark into `tools/proof/work/screens/<date>/screens.md`; its `README.md` has the format and how to add a screen. |
| `agent/prices/` | The price table (spec §11 P-1, P-2, P-5): `anthropic.json` is LiteLLM's Anthropic rows in $/MTok with the LiteLLM commit it came from, written only by `make prices` and bundled into the helper, which refreshes its own daily copy into the spend folder (`agent/src/priceTable.ts`); `cases.json` the hand-checked cases `agent/src/pricing.ts` and `tools/proof/prices.py` both answer; `reduce_cases.json` the LiteLLM document both reducers (`update.py`, `priceTable.ts`) answer. `designs/adr/roadmap-13-pricing.md` holds the record. |
| `tools/proof/README.md` | The proof scripts, the MCP client and the offscreen harness. |
| `README.md` | User-facing front page: the feature highlights, each linking its page in `docs/guide/`. |
| `docs/guide/` | **The user guide**, one page per feature area (index: its `README.md`), every claim written from the code; `menus-and-shortcuts.md` is the full menu and key reference. A user-visible change edits its page. |
| `docs/developing.md` | Building, the make targets, the layout, publishing a release, driving a build over MCP — for a contributor. |

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → "build/Build/Products/Release/Frame Job.app"
make app-debug  # make rust + make project + xcodebuild Debug → "build/Build/Products/Debug/Frame Job Debug.app", "Frame Job Debug" (com.kgalligan.FrameJob.debug; seconds after a one-file edit)
make test       # make rust, make codecs, tools/codecs/build_codecs.py --selftest (its key, reuse and digest rules over scratch folders), cd core && cargo test --release, cd graphic && cargo test --release, cd mcp-proxy && cargo test --release (black-box tests), then tools/proof/assistant_lane_proof.py (the agent lane's probe, with the assistant's credential rows and the support folder's `0700` rows), tools/proof/assistant_prompt_proof.py --probe (the prompt texts' drift checks), tools/proof/prices_proof.py (the price function: prices.py and agent/'s `bun test` against agent/prices/cases.json, and update.py's reducer against reduce_cases.json, no network) and tools/proof/budget_proof.py (the proofs' ledger and the monthly budgets, over scratch ledgers, no network) and tools/proof/capture_spike/inventory.py --check (the menu inventory's sites, found by token and enclosing function, and its other citations, found by anchor, against app/Sources; no app) and tools/proof/spec_index_proof.py (the spec indexes' Lines cells against `wc -l`, and a row for every spec file; no app) and tools/proof/swift_build.py --selftest (the probe builder's key, reuse and digest check, and that no proof carries its own app swiftc line; one tiny build, no app) and tools/proof/proof_app.py --selftest (the stale-app refusal, the app choice and the Debug bundle id against project.yml, over scratch trees; no app) and tools/proof/gate.py --selftest (the gate's input classes, its stamp rule and its warning baseline, over synthetic digests; no tree, no app) and tools/proof/proof_defaults.py --ran assistant_lane_probe --ran assistant_prompt_probe (the defaults removal recipe on a throwaway domain, its refusals over scratch folders, then the sweep of the proofs' own idle domains, and of the two probes this target ran, out of `~/Library/Preferences`; no app) and tools/proof/appcast.py --selftest (the appcast writer and its signature parse, no network) and tools/proof/name_residue.py --selftest then tools/proof/name_residue.py (no line or path spells the old name outside its allow-list: HISTORY, TEXT_HISTORY, KEPT_PATTERNS and the exact COUNTED pins, spec §11 NM-8; no app)
make lint       # cargo clippy --all-targets -- -D warnings, in core/, graphic/ then mcp-proxy/
make typecheck  # make codecs, then swiftc -typecheck -D FRAMEJOB_DEV_TOOLS -Xcc -Ibuild/codecs/include of app/Sources/*.swift in batch mode on every core (seconds) — the ONLY authoritative Swift check, then agent/'s `tsc --noEmit` (through bun)
make gate       # the one Full verification command: names (tools/proof/name_residue.py, spec §11 NM-8; every file, `*.md` included, is its input), typecheck (builds or reuses the codecs first; exactly its four baseline warnings), cargo fmt --check, lint, test, app (and the Release app's entitlements and seal, dist_check D25/D26); serial, stops at the first failure, skips a step whose inputs and tools are byte-identical to its last pass (build/gate/; `cmake --version` is in the tools' fingerprint)
make codecs     # tools/codecs/build_codecs.py: SVT-AV1 and libvpx as arm64 static archives (pinned tarballs, SHA-256-checked, built with cmake) into build/codecs/, reused while its stamp's key and output digests match (spec §11 CX-8); app, app-debug, typecheck and test depend on it, so they need cmake (`brew install cmake`), the system perl and, for the first fetch, network
make project    # xcodegen generate with VERSION injected — never run a bare xcodegen, it leaves the version blank (FrameJob.xcodeproj is generated; project.yml is the source of truth)
make run        # make app, then launch
make dist       # make app, then the Distribution build (no dev tools, spec §11 V-1), tools/proof/dist_check.py and tools/proof/published_check.py (the check the publish workflow runs over the app it packs, spec §11 PUB-4), both run even when the first fails; D28–D35 and P17–P21 are Sparkle's (PUB-6..PUB-9: embedded, signed, the feed and key in Distribution only, D35 no Sparkle load command in Release); until the owner's EdDSA public key is in project.yml, D31 and P20 fail and nothing else
make prices     # NETWORK: regenerate agent/prices/anthropic.json from LiteLLM (spec §11 P-1); its only writer, never run by another target
```

- Single Rust test: `cd core && cargo test --release --test edge slip`
  (test-file name, then a name filter). Finish Rust work with `cargo fmt` in
  `core/` (and `graphic/`, and `mcp-proxy/`) and a clean `make lint`.
- There are no Swift unit tests. App-side verification is `make typecheck`
  plus driving the built app over MCP and the probes in `tools/proof/`.
- `make typecheck` takes seconds; run it before `make app` (~90 s). Its baseline is
  **0 errors and 4 warnings**, and tsc prints no error; the warnings are all
  AVFoundation deprecations (2 in `CompositionBuilder.swift`, 1 in
  `CompositionBuilder+Orientation.swift`, 1 in `Exporter.swift`), deliberate because their replacements are `async`-only
  and `async` is confined to `MediaImporter.swift` and `SpeechEngine.swift`
  (spec §11 W-8). Any fifth warning is new and yours; `make gate` holds the
  check to exactly those four (`TYPECHECK_BASELINE` in `tools/proof/gate.py`),
  and a change that fixes one deletes its row there. It stops before
  SILGen, so a clean typecheck does not prove the app builds; only `make app`
  does.
- A probe or the harness compiles ONLY through `tools/proof/swift_build.py`
  (`build()`; `python3 tools/proof/swift_build.py typecheck <probe.swift>…`
  checks a probe's types in seconds): one swiftc line on every core, a build
  reused only when every input is byte-identical.
- `make app`/`make dist` build the assistant helper (`agent/`) in their
  last Xcode step, `make typecheck` ends with its tsc, and `make test` runs
  its `bun test` (through `prices_proof.py`). All need bun, and
  without it they fail with an `error: bun is not installed` line rather
  than skipping.
- `FrameJob.xcodeproj` is generated; never commit it. xcodegen and
  `make typecheck` both glob `app/Sources/`, so a new Swift file needs no
  registration anywhere.
- **A build for another Mac comes only from a push to the `publish` branch**
  (`.github/workflows/publish.yml`, spec §11 PUB-1..PUB-5): Distribution,
  Developer ID-signed, checked by `published_check.py`, notarized, a DMG on a
  GitHub Release. Pushing there publishes, so it is the owner's to ask for.
  The base version is the `VERSION` file (MAJOR.MINOR), as in Rasterize;
  the workflow file's NAME owns the run counter and is never changed. Every
  local build stays ad-hoc signed.

## File map

```
core/                Rust staticlib — the model, the ops, the plan, the recipe,
  include/…_core.h     export settings, the generic MCP server, the index of a
                       WebM/Matroska file being imported. THE FFI CONTRACT
  src/                 core/CLAUDE.md has the module map
  tests/               black-box, through the FFI
graphic/             Rust crate — the graphics engine (road map 10): a Module run in
  src/                 sandboxed QuickJS returns SVG per frame; rasterize (usvg →
  tests/               resvg → BGRA), measure_text. graphic/CLAUDE.md has its rules
  vendor/              tiny-skia 0.12.0 with the gradient-dither patch (spec §11 PR-13)
mcp-proxy/           Rust crate — `framejob-mcp` (road map 14 MC3, spec §11 MC-3): the stdio
  src/                 MCP server bundled in Contents/Helpers; answers initialize, ping and
  tests/               tools/list itself (the build's catalog snapshot when no Frame Job runs),
                       forwards the rest over the agent socket and launches its own bundle
                       for a tools/call. std + serde_json; mcp-proxy/CLAUDE.md has its rules
agent/               the assistant helper (AI-1): Bun, the Anthropic SDK's Tool Runner
  src/                 byte-identical to ~/devel/rasterize/agent/src/ (`diff -r` exited 0
                       on 2026-10-13), one diff applied to both; but for NM-10's three
                       lines (main.ts's comment, priceTable.test.ts's scratch prefix,
                       priceTable.ts's user-agent `framejob-agent`), recorded in
                       designs/adr/rename.md for Rasterize to apply (rasterize#654).
                       What the apps differ in arrives in `configure`
  prices/              anthropic.json (LiteLLM's Anthropic rows, $/MTok; written only by
                       `make prices` → update.py; bundled into the helper), cases.json
                       (the fixture both price readers run), reduce_cases.json (the
                       fixture update.py's and priceTable.ts's LiteLLM reducers run)
  build.sh             used by the Xcode step (`helper`), `make typecheck` (`typecheck`)
                       and `make test`'s prices_proof.py (`test`)
app/
  Sources/             AppKit app, programmatic UI (app/CLAUDE.md has the map)
  Resources/Shaders/   Compositor.metal — the per-layer compositing pass; ExportI010.metal —
                       the AV1 export's 64RGBAHalf → planar 10-bit I010 conversion
  Resources/Models/    silero_vad.mlmodelc, vendored compiled (PROVENANCE.md)
  Bridging/            the bridging header importing core/include/framejob_core.h
designs/             the spec, adr/ (condensed records), the handoffs — the table above
archive/             closed road maps and histories, verbatim; INDEX.md — read only when asked
docs/agents/         what the engineering skills read: tracker, labels, domain docs
docs/graphics-api.md the graphics reference an agent reads; graphic/tests/reference.rs runs every js block
tools/proof/         mcp.py, the per-phase proof scripts, harness/ (offscreen chrome),
                     swift_build.py (the one probe build line and its cache),
                     proof_app.py (which app a proof drives, and the stale refusal),
                     gate.py (make gate: the Full tier, skipping what already passed)
tools/codecs/        build_codecs.py (the encoders' pins, fetch, build and stamp; `make codecs`)
                     and PROVENANCE.md; the archives and headers land in build/codecs/
.github/             workflows/publish.yml (the publish branch's signed, notarized DMG, spec §11
                     PUB-1..PUB-5) and ExportOptions.plist (its developer-id export)
project.yml          xcodegen definition; Makefile; README.md (user-facing, linking docs/guide/)
VERSION              the base version, MAJOR.MINOR; `make project` feeds it to xcodegen and
                     the publish workflow appends its run number (spec §11 PUB-2)
```

## Architecture

**Rust decides, AVFoundation and Metal do** (spec §7). The core holds the
project (JSON, spec §5.2), every edit, the composition plan, the per-frame
recipe and the index of a WebM/Matroska file being imported. Swift owns windows, gestures, undo, AVFoundation playback and export,
the Metal compositor, media import and its caches, and agent dispatch. No
pixel or sample work in Rust; no ffmpeg dependency in the product. The AV1 and
VP9 encoders (SVT-AV1, libvpx; road map `designs/codec-export.md`) are
platform-side like AVFoundation: Swift calls them through the bridging header,
no `rc_*` export wraps them (spec §11 CX-4).

### FFI contract

- `core/include/framejob_core.h` is a **hand-maintained** C header, the single
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
   entry in the per-side `CLAUDE.md` if a file's role changed; the feature's
   page in `docs/guide/` (and its README highlight and
   `menus-and-shortcuts.md` row when it adds one); the phase's record in its
   road map.
6. **Verify:** as "Verification" below says; then read the change back
   adversarially before committing.

## Rules

- Conventions are Rasterize's — `~/devel/rasterize`'s three `CLAUDE.md`
  files are the parent text for anything not settled here.
- **Every user-visible edit gets an MCP mirror** (spec §7.9): a handler, a
  catalog entry, and a comment naming the UI path. The startup parity check
  in `AgentServer.prepareCatalog()` has FIVE parts: catalog names against handler
  names, every op in the core's table against the tools (through
  `rc_op_names`, with an explicit allow-list for ops that deliberately have
  none), each tool's schema shape, that every op tool declares `scope`, and
  that every op tool declares the CORE's own arguments for its op — each one
  described, and no description for an argument no op has
  (`AgentServer+Parity.swift`). What it cannot see is a CALL, which two
  things guard at dispatch: the argument GATE in `AgentServer+Gate.swift`
  compares the caller's keys to the schema the tool published and refuses a
  stranger by name, for all ninety-eight product tools (and the dev tools, road
  map 11), before any handler runs;
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
- **Size rules are per FILE, never per feature.** A brief, design, road map,
  spec or proof never sets a budget on how many lines a feature may add,
  never measures a feature's total against one, and never names code size as
  a reason to cut, trim or drop a feature: a feature takes as much code as it
  needs. Keeping files small is the cap above and its pure moves, nothing
  else (owner, 2026-10-10).
- **A decision in spec §11 is not re-litigated** (`designs/spec/11-decisions/`). A phase that needs a new
  one records it there before the code, not after.
- **`.secrets/` (gitignored) holds the owner's own keys for proofs**, e.g.
  `.secrets/anthropic-key`, read ONLY by `anthropic_key()` in
  `tools/proof/assistant_prompt_eval.py`. Never open, print, grep, copy or
  list its contents; never move a key from it into an argument, the
  environment of a build, a log or a file. A run that spends money still
  needs its explicit flags (`--live --cap <dollars>`); the file's presence
  spends nothing. Every paid proof request is also held to the month's
  budget (spec §11 P-3, P-6) in
  `~/Library/Application Support/Frame Job Proofs/spend.jsonl`; an agent
  never edits it, raises a budget, or points a verification at it.
- **A check only a person at the machine can make is a row in
  `docs/manual-checks.md`**, added in the change that creates it — never a
  `ready-for-human` issue, and never an instrument built to stand in for the
  person (how a pane looks, whether audio plays, a real key's conversation).
  Automate what a script can truly measure; list only the residue.
- Commit only when asked. A commit message says what was verified and what
  is owed, and the road map's record says the same.

## Verifying a build

A local Distribution build is only ever checked, never launched: it loads
Sparkle, which library validation refuses in an ad-hoc signed hardened app
(spec §11 PUB-7). Debug and Release link with `-dead_strip_dylibs`, so they
never load it.

The app is verified by driving the built binary over MCP and comparing what
it renders — not by reading code. Launch your own instance on your own socket
and only ever kill that one (`pgrep -f "MacOS/Frame Job"` lists them, Debug
and Release alike; the products folder tells them apart; another session may
have one running):

```sh
make app-debug
python3 tools/proof/proof_app.py launch   # prints folder, socket, log, pid
```

Each later command names the printed folder literally
(`mcp.MCP("<dir>/agent.sock")`, `python3 tools/proof/phaseN_proof.py
<dir>/agent.sock`, `grep "Frame Job: " <dir>/framejob.log`), because a shell
variable does not survive from one agent command to the next; stop it by the
pid the launcher prints.

The log line `Frame Job agent socket listening at <dir>/agent.sock` says it is
up (`not bound: <reason>` says why not). Drive it with `tools/proof/mcp.py`'s
`mcp.MCP("<dir>/agent.sock")` (streamable HTTP over the Unix socket), or with
the bundled stdio helper `framejob-mcp` with `RC_AGENT_SOCKET` set to the same
path: one tool per §6 op, each taking the `scope`
envelope key, plus the app-state tools — `open_project`, `new_project`,
`save_project`, `close_project`, `get_project`, `import_media`,
`import_captions`, `export_captions`, `transcribe`, `consolidate_media`, `detect_silence`,
`detect_fillers`, `transcribe_for_fillers`, `get_transcript`, `normalize_clip`, `set_playhead`, `set_range`, `set_selection`, `set_scope`,
`undo`, `redo`, `render_frame`, `export`, `export_status`, `cancel_export`,
`record_screen`, `write_graphic`,
`get_graphic`, `graphic_reference`, `render_graphic`, `import_graphic_font`,
`import_graphic_asset`, `delete_graphic`, `rename_graphic` and
`restore_graphic`. A Debug or Release build also has the dev tools
(`snapshot_ui`, `perform_menu_item`, `cancel_sheet`, `select_inspector_tab`;
"Seeing the chrome" below; `play_preview`, which plays a window's preview
for a while and answers the frames composed (#127, spec §11 G-36);
`graphic_memory`, which answers the graphic rasters' memory budget, what is
held and kept, and simulates memory pressure (G-37); and
`assistant_send` / `assistant_answer`, which
drive a window's assistant turn against a stand-in server, with the dev-only
launch default `-RCDevAssistantSend <text> -RCDevAssistantReport <path>` for
a turn in a launch without the server; and `-RCDevSyncHold <s>`, which holds
Synchronize Audio's background analysis so a proof can act during it; and
`-RCDevRampRenderHold <s>`, which holds each speed-ramp audio render so a
proof can act while it is pending), which
Distribution does not. `rc_op_names`
and the catalog are the authority for the counts; the parity check compares
them at startup. `render_frame` writes a PNG and returns its path; `export`
puts the job on the Export Queue and answers an `export_id` at once, and
`export_status` answers it until `done` (`mcp.py`'s `export_with` waits; spec
§11 #326).

A proof picks its app through `tools/proof/proof_app.py`: `RC_PROOF_APP` is
`debug` (the default), `release` or a `.app` path. `mcp.launch`, `mcp.MCP` and
`python3 tools/proof/proof_app.py launch` refuse a tree's built app when any
input is newer than its last complete build (its
`_CodeSignature/CodeResources`), or an instance started before an input
changed, naming the file, its time and the `make` target.

Release-only proofs pass `release_only=` (`git grep release_only= tools/proof`);
recording_proof's socket instance is started with
`python3 tools/proof/proof_app.py launch --app release`.

**Before trusting any MCP proof, `grep "Frame Job: " <dir>/framejob.log`
must print nothing** — that prefix is the startup parity check complaining.
On a Debug build the same complaint is an `assertionFailure` that traps first
(`AgentServer.prepareCatalog`), so `make app-debug` fails at Write Agent
Catalog with `Fatal error: …` instead of logging the line.

A proof's instance shares its bundle's defaults domain (the owner's
`com.kgalligan.FrameJob` for a Release build, `com.kgalligan.FrameJob.debug`
for a Debug build, spec §11 V-5): no
environment moves `UserDefaults` (#238). Never perform a persisting menu item
(View ▸ Snapping, Safe Areas, Hide Inspector, Timeline Track Height, Preview
Quality) on either build: `mcp.py` ends the script with status 3 and
`DEFAULTS MOVED` last on stderr when its session moved a key and no other
Frame Job shares the domain, and only prints the line when one does;
`defaults_proof.py` is its proof. The guard reads the domain with
`CFFIXED_USER_HOME` taken out of `defaults`' environment
(`proof_defaults.read_env`), so a proof run under a scratch home that does
not exist yet, or is removed before the script ends, is compared with
itself: `defaults export` answers no key under a variable naming an absent
folder.

**`tools/proof/` holds the scripts that do this** — an MCP script per phase
over a dependency-free client (`mcp.py`), and beside most of them an
offscreen-chrome script or a probe. Every claim in them is a placement read
back through `get_project`, a BYTE comparison of two PNGs, or a
sample-for-sample comparison of two exports decoded to PCM (which needs
`ffmpeg` at proof time). Its README says how to make the test media, run
one, and which scores are known host-state skips (a locked console, a
Bluetooth output). Add the next phase's proof there rather than writing a
throwaway. An instance DEADLOCKS somewhere past forty documents open at once:
a proof that closes what it opens (`close_project`) can share an instance, and
one that does not relaunches between proof sessions.

Spec §10's per-step verifications are the acceptance tests. What no script
can answer — step 4's "the clip plays with audio", step 5's 60 fps, and the
rest — is a row in `docs/manual-checks.md`, which the owner runs.

## Verification

- **In the loop:** a targeted test (`cd core && cargo test --release --test
  <file> <filter>`), `make lint` after Rust edits, `make typecheck` after Swift
  edits, `make app-debug` before driving the app, and the phase's own rows
  (`--only` where the proof has it) against Debug.
- **Once, when the code is complete:** `make gate`, in the foreground, under
  the 600 s tool cap (`make gate GATE_ARGS=--force` only when a stamp itself is
  in doubt). It stops at the first failure and skips a step whose inputs and
  tools are byte-identical to its last pass, so after a fix it re-runs only
  what the fix can change. Never run one of its steps by hand to stand in for
  it, never re-run an unchanged step, and never run anything twice with no
  edit between.
- **The proof a phase records** runs whole once, on the final instrument,
  against Release (`RC_PROOF_APP=release` after the gate's `make app`), with
  any `release_only` proof the change touches. This is a rule: nothing checks
  which build a recorded run drove.
- **A proof that fails only on Debug** is pinned `release_only="<reason>"` in
  the change that finds it (spec §11 V-4); an assert trap on Debug is a defect
  to fix, never a pin.
- **Mutants** target the decisions the phase adds: about one per new branch,
  threshold, refusal or ordering, usually 3–8; more than 10 only with a reason
  written in the spec. The full set runs once, at the end, on the final
  instrument.
- **A fix pass** re-runs only the rows whose instrument code it changed and
  the mutants whose anchor lines it touched, then `make gate`.
- **Background** only for a command that cannot fit 600 s, waited on once with
  a bound; never a poll loop.

## Seeing the chrome

`screencapture` needs a Screen Recording grant the agent's terminal may or
may not have (it varies by host and session), and without it `screencapture`
silently writes a black PNG. Assume neither: a proof that needs the grant
probes for it and skips its granted tier by name, and a capture is never
trusted until it is checked non-black. The way to LOOK at the chrome is
**`tools/proof/harness/`**: it compiles every file in `app/Sources` except
`main.swift` with a `main.swift` of its own, links the staticlib, opens a
`.framejob` package, puts an `EditorViewController` in an `NSWindow` and
`cacheDisplay`s it into a PNG at the display's backing scale — the same paint
path the window uses, no TCC grant, either appearance, captured on SETTLE.
The preview well comes out as the canvas background (an `AVPlayerLayer` or
Metal layer does not draw into `cacheDisplay`), so nothing about the PICTURE
is ever claimed offscreen; pixel claims go over MCP. `tools/proof/README.md`'s
"offscreen harness" section has the build line, the argument list and the
pinned `UserDefaults`.

To look at the LIVE app, a Debug or Release build (`make app-debug`,
`make app`; never Distribution) has dev tools over MCP (road map 11, spec §11 V-1).
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
panel: shown from the background it no longer takes key (#137), but an
instance that is active when it runs still gets a key panel with Record on
Return, so the script stops each instance straight after capturing it.

Two rules from it worth carrying into any proof: **identical, stable,
DIFFERENT output across processes is an Auto Layout ambiguity to find, not a
race to out-wait** — reach for constraint priorities, not for more run-loop
turns (on an `NSStackView` that is `setHuggingPriority(_:for:)`;
`setContentHuggingPriority` is inert on a stack); and **when the thing to
check is app ARITHMETIC or app STRUCTURE with
no caller a script can reach** (a menu, a validator, a cue builder, a queue),
the answer is a probe compiled from `app/Sources` through
`tools/proof/swift_build.py`, not a photograph. A probe that will not build is a scored
FAILURE, never an exit, so a rotted instrument cannot take a score down with
it. **That rule applies to historical instruments too.** The meter and welcome
comparisons build old `app/Sources` with the matching old core and header in
isolated output directories, using the current guarded `harness/main.swift`
for both paints; `cloud_captions_probe.py`'s W and SP baselines build the
same way through `reference_build.py`, each in its own folder. A failed current or reference build is a scored failure,
including an FFI diagnostic; it is never a historical skip or a reason to
fall back to the old harness. Only the recording proof's granted tier can
skip rows for a named host condition such as a locked console.

## Agent skills

### Issue tracker

GitHub Issues on `kpgalligan/framejob`, through the `gh` CLI. See `docs/agents/issue-tracker.md`.
**Every issue an agent creates carries the `ai-drafted` label**, beside any
triage label: `gh issue create --label ai-drafted …`. **It also carries
`low-priority` unless it is urgent** — data loss or a corrupt project reachable
in ordinary use, a crash or hang reachable in ordinary use, a secret leak, or
something blocking other work now.

### Triage labels

The five default role strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one root `CONTEXT.md`, with spec §11 as the decision record in place of `docs/adr/`. See `docs/agents/domain.md`.
