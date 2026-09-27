# Road map 12 — the Assistant tab

**Status: PROPOSED 2026-09-27; the user answered §6 the same day. §4's decisions are recorded in
spec §11 (`11-decisions/assistant.md`, AI-1..AI-11) and A0 ran the same day (§7). No product
code is built.** This is the design the user asked for:
an AI agent in the editor, "designed in the same way that the agent for
`~/devel/rasterize` is". §1 is what Rasterize built. §2 is what carries over unchanged.
§3 is what Reelcut needs that Rasterize did not. §4 is the decisions §11 must record
before any code is written. §5 is the phases. §6 is the user's answers. §7 is A0's record.

## 1. What Rasterize built

These are Rasterize commits `400f516`, `b12954a`, `6dd36c2` and `584b7e3` (2026-09-25/26).
The last one removed the older in-core Rust loop, so the helper is the only path.

- **`agent/`** is a Bun project with one dependency, `@anthropic-ai/sdk`. It has two
  source files: `main.ts` (~400 lines) and `protocol.ts` (~75).
  - `bun build --compile --target=bun-darwin-arm64` builds a single executable.
  - A `postBuildScripts` step in `project.yml` builds it on every build (~0.2 s).
  - That step copies it into `Contents/Helpers/` and codesigns it with the hardened
    runtime and exactly one entitlement, `com.apple.security.cs.allow-jit`, which Bun's
    JavaScriptCore needs. The app's own signature does not cover a nested executable,
    so the helper is signed before Xcode signs the app around it.
- **The helper runs the conversation and owns no tools.** It is the SDK's Tool Runner
  (`client.beta.messages.toolRunner`). The rest of its behaviour:
  - It streams, and has the SDK retry up to 3 times.
  - It sets automatic prompt caching (`cache_control` at the top level).
  - Thinking is adaptive with `display: "updates"`, so notes between tool calls reach the
    panel as short progress lines.
  - It sets `fallbacks: "default"` for refusals, `effort: "medium"`, and
    `claude-opus-5-5` as the default model.
  - It uses BM25 tool search: all but 4 of 249 tools are `defer_loading`.
  - Every tool's `run` sends a `tool_request` to the app and waits for its `tool_result`.
- **The protocol is JSON lines over stdio.**
  - App → helper: `configure` (key, model, system prompt, the MCP-format catalog,
    settings), `send`, `cancel`, `reset`, `settings`, `tool_result`.
  - Helper → app: `ready`, `turn_started`, `text_delta`, `progress_delta`,
    `message_done`, `context_usage`, `tool_call`, `tool_request`, `tool_result`, `error`,
    `compaction_started`, `compacted`, `compaction_failed`, `tool_results_cleared`,
    `turn_finished`.
- **`AssistantHelperSession.swift`** (~220 lines) starts the process and handles its
  pipes and lifecycle.
  - It launches the helper with an EMPTY environment (only `HOME`, `TMPDIR` and a bare
    `PATH`), so no `ANTHROPIC_*` variable can reach it. The key arrives over stdin.
  - It sets `F_SETNOSIGPIPE` on the write end, so a dead helper cannot take the app down.
  - It writes on a background queue, because a render can be megabytes.
  - It runs each tool the helper asks for through `AgentServer.shared.execute`, and
    splices the result JSON in verbatim rather than re-encoding it.
  - A cancel answers tool calls already queued with "Cancelled by the user."
  - If the helper dies, the panel says so, and Clear starts a new helper.
- **History is append-only.** Opus 5.5 rejects replayed thinking after an edited prefix,
  and an unchanged prefix is also what keeps the cache warm. The one sanctioned rewrite
  is the API's own compaction.
  - Compaction runs only at the end of a turn, once context passes a threshold
    (300 k by default), with summary instructions written for the domain.
  - Optionally, `clear_tool_uses` clears old tool results past 150 k tokens.
- **The panel** is a tab of the right-hand panel. It has a transcript, a composer whose
  Send button turns into Stop, a context meter (the window size comes from the Models
  API), Clear, and an overflow menu that opens Chat Settings.
- **The key** is `ANTHROPIC_API_KEY` if set, otherwise a `0600` file under Application
  Support. It is not kept in the Keychain because ad-hoc signing breaks the ACL, the same
  finding as road map 6's C0.

## 2. What carries over unchanged

Take the helper whole. Reelcut's copy of `agent/src/` should be **byte-identical** to
Rasterize's except `package.json`'s name and output path. To get there, first move the
three domain constants out of `main.ts` and into `configure`:

| Constant in Rasterize's `main.ts` | Becomes `configure` field |
|---|---|
| `CORE_TOOLS` | `core_tools: string[]` |
| `TOOL_SEARCH_GUIDE` | `search_guide: string` |
| `COMPACTION_INSTRUCTIONS` | `compaction_instructions: string` |

A0 measured the rename (§7 B2): with `rasterize-agent` renamed in `package.json`'s name and
outfile and in `bun.lock`'s root workspace, `bun install --frozen-lockfile` passes, so the lock
needs no regeneration and the two locks stay one diff apart.

Rasterize should take the same change, so the two helpers never drift. A shared package
can come later if a third app wants one. Until then the rule is **one diff, applied to
both**, the way issue #101 treats `drawBar`.

The following also carry over unchanged in shape: the protocol, the session class, the
build step, the signing, append-only history with end-of-turn compaction, the
empty-environment launch, and the key arriving on stdin.

## 3. What Reelcut needs that Rasterize did not

Each item was checked against the tree on 2026-09-27.

### 3a. The dispatcher is not main-thread-only here

Rasterize's `execute` asserts main and the session calls it on main. Reelcut's
`AgentServer.execute` (`AgentServer.swift:169`) runs every tool on main **except the eight
`offMainTools`**: `import_media`, `render_frame`, `export`, `save_project`, `new_project`,
`transcribe`, `record_screen` and `render_graphic`.

Those eight block on a semaphore while their work hops to main through `onMain`.
`export`, for example, waits up to 3600 s. Called on main, they deadlock. The routing
lives in the private C trampoline (`AgentServer.swift:780-801`), so it cannot be reused
from Swift as it stands.

### 3b. The dispatcher assumes a single caller

`callScope` is a per-call property. It is race-free only because "the server is
single-request" (`AgentServer.swift:52-59`): the core's `serve` loop runs one request at a
time. An in-app assistant is a **second caller**. With the MCP server also running (which
every proof session does), two tools can execute at once, and one call's `scope` can land
on the other's edit.

### 3c. The gate is empty unless the server started

`noteArguments(in:)` fills the gate's schema map only inside `start()`
(`AgentServer.swift:124`), and `start()` runs only under `-AgentServerEnabled YES`. The
gate treats a tool it has no schema for as taking **nothing** (`AgentServer+Gate.swift:62`).

So in an ordinary launch, every assistant call that carries an argument would be refused.
This is the trap most likely to ship unseen, because every proof runs with the server on.

### 3d. The target document

Rasterize's prompt tells the model to pass `document_id` on every call. Reelcut's
`target(a)` takes an optional `project` PATH. Without one, it falls back to the current
document, and then to the front window.

An untitled project has no path. If the person switches windows mid-turn, the
assistant's next edit lands on the wrong project.

### 3e. Placement

- Spec §11 says there is no left panel: "Media is an inspector tab"
  (`foundations.md`). The inspector is Reelcut's only side panel.
- **The sharp handoff forbids this outright.** `design_handoff_reelcut_sharp/README.md:4`
  says: "Do **not** add a tool rail, options bar, layers panel, **assistant panel**,
  status bar or zoom HUD to Reelcut."
- That line was written to keep Rasterize's parts out of a Reelcut pass. The user's
  request now overrides it, but only through a recorded decision (§4 AI-4).

### 3f. What the assistant may call

The MCP catalog assumes the caller is a developer's agent. An in-app assistant acts for a
person who has not seen the arguments. Four cases matter:

- **`record_screen`** captures the screen and brings Reelcut to the front (#137).
- **`transcribe`** with the cloud engine sends audio off the machine and spends money.
  R6-2 says: "Audio leaves the machine only by name, with the price in front of the
  person."
- **`export`**, **`save_project`** and **`consolidate_media`** write where the model says.
  Whether `export` replaces an existing file silently is **not yet known**; the A0 spike
  checks it.
- **The dev tools** (`snapshot_ui`, `perform_menu_item`, `cancel_sheet`,
  `select_inspector_tab`) exist in Release but not in Distribution. The assistant must see
  the same catalog in both builds.

### 3g. W-9 reads broader than it was meant

W-9 says "No language model chooses words". An assistant asked to "fix the typo in the
third caption" calls `set_text`, which is exactly that. W-9 was about AUTOMATIC styling by
meaning (road map 8's emphasis and emoji). It needs a clarifying amendment, not a
contradiction (§4 AI-6).

### 3h. Inspector hygiene

- Inspector panes rebuild when `structureSignature` changes, and `rebuild()` does not
  keep the first responder (app/CLAUDE.md pitfall). A composer that is rebuilt while the
  person types loses its text and focus. The Assistant pane must own persistent views,
  following the `MediaPane.arrange()` pattern.
- Its session must NOT live in the pane. It belongs to the window, on the controller.
- `SpaceKey.route` already sends Space to an editable field editor, so the composer gets
  its spaces. A row in `space_key_probe.swift` should prove it.

### 3i. Key hygiene is Reelcut's, not Rasterize's

Road map 6 already settled the pattern:

- The key goes through `SecretStore` (`FileStore`, a `0600` file in a `0700` folder).
- `-RCSecretFolder` (R6-9) keeps proofs away from the person's real file.
- R6-12 says no tool reads or writes a key.
- The Makefile has `unexport`, because `xcodebuild` writes its task environment into
  `XCBuildData`. `ANTHROPIC_API_KEY` needs the same `unexport`, and
  `makefile_env_proof.py` needs a row for it.
- The key is entered in **Reelcut ▸ Settings…**, a new Assistant pane beside
  Transcription, not in a sheet of the panel's own as Rasterize does.

## 4. Decisions spec §11 records first (a new `assistant.md`)

Recorded 2026-09-27 as AI-1..AI-11 in `designs/spec/11-decisions/assistant.md`, with §6's answers.

- **AI-1 — The assistant is a bundled helper, and the app never calls Anthropic itself.**
  - `Contents/Helpers/reelcut-agent` is Bun-compiled from `agent/` on the Anthropic
    TypeScript SDK's Tool Runner.
  - It is the one TypeScript in the product. G-11 ("no TypeScript") governs graphic
    Modules and is untouched.
  - The Swift side uses `Process`, pipes and GCD, so W-8's `async` confinement holds.
- **AI-2 — The helper owns no tools. Every call goes through `AgentServer.execute`, by way
  of one lane.**
  - An `AgentLane` holds one lock around every tool call from either caller: the MCP
    trampoline and the assistant session. The trampoline's call to it is the only wiring
    change in the frozen `AgentServer.swift`.
  - The lane routes a call to main, or leaves it on the lane's own queue for the
    `offMainTools` (3a).
  - The session never takes the lock on main, because an off-main tool that is holding
    it waits for main (3b).
  - The same gate, parity check, refusals and undo steps apply. There are no
    assistant-only tools.
- **AI-3 — The catalog and the gate are prepared at launch, not at `start()`.**
  - `prepareCatalog()` builds the catalog, runs `noteArguments` and runs the parity check.
    `start()` and the assistant both call it (3c).
  - A `make test`-reachable probe proves that an assistant call with an argument succeeds
    in a launch WITHOUT `-AgentServerEnabled`.
- **AI-4 — The Assistant is the inspector's fourth tab: Clip, Media, Document, Assistant.**
  - This amends the sharp handoff's "no assistant panel" line, which was about Rasterize's
    parts rather than this feature.
  - It gets a menu item with a key (spec §9).
  - The user chose the tab to start, and may move the Assistant to a floating window
    after trying it (§6). So the pane holds only views, and everything else (the
    session, the transcript's storage, the pending confirmation) lives outside it. A
    move to a window is then a new host for the same views, not a rewrite.
  - There is one conversation per window. The session lives on `EditorViewController`
    and survives tab switches, pane rebuilds and inspector collapse.
- **AI-5 — The assistant edits its own window's project.**
  - The lane pins the call's document, the way `callScope` pins the scope. The pin is a
    per-call `callDocument` that `targetDocument` checks first, and it is cleared by a
    `defer`.
  - A `project` argument naming a DIFFERENT open project is refused by name (3d).
- **AI-6 — W-9 governs automatic styling, not a person's request.**
  - No PIPELINE picks words by meaning.
  - The assistant writes a caption's text or style only because the person asked it to
    in the conversation. Each such edit is an ordinary undo step.
- **AI-7 — What the assistant may not call, and what it must ask about first.**
  - The dev tools, always.
  - `record_screen`, always: recording is a person at the Record button.
  - `transcribe` with the cloud engine, which is refused with R6-2's sentence and points
    at File ▸ Generate Captions….
  - **Ask first:** `export`, `export_captions`, `save_project` and `consolidate_media`,
    because each writes files where the model chose.
    - The call is NOT run when the helper asks for it. The transcript shows a
      confirmation row that names the tool and where it writes, with Allow and Deny.
    - The helper's `tool_request` simply waits, which the Tool Runner already does for
      every call. So the helper is unchanged: the question and the answer both live in
      the app.
    - Deny answers the call as an error: "The person declined: …". The model reads that
      and carries on.
    - Stop, Clear, closing the window and a dead helper all answer a pending
      confirmation as declined. Nothing runs later that the person did not see.
    - An MCP caller is never asked. The rule belongs to the assistant's lane, not to the
      tool.
  - Both lists are one table in one file, with a column for "withheld" or "ask first"
    and a reason on every row.
  - The helper never sees a withheld tool, and the lane refuses one if it is called
    anyway.
- **AI-8 — The key is the person's own (bring your own key), and is R6-5 and R6-12's key
  in everything but the vendor.**
  - It lives in `SecretStore` under `anthropic-key`.
  - The one override is `ANTHROPIC_API_KEY`, read only as R6-5 amended says.
  - The key is never a tool argument, a launch argument or an answer. It is handed to the
    helper on stdin only.
  - R6-5's "integrated AI offering" is THIS, and it does not unblock C2 (#125). C2 still
    needs the caller's identity.
- **AI-9 — History is append-only, and end-of-turn compaction is the one rewrite**
  (Rasterize's rule, for the same reasons).
- **AI-10 — Each tool call the assistant makes is its own undo step,** exactly as an MCP
  call is. A turn is not grouped. The Edit menu names the step as it would for the same
  call from MCP.
- **AI-11 — The default model is `claude-opus-5-5` at medium effort.** The model is a
  person's setting, chosen in Settings' Assistant pane. Like the key, no tool reads or
  writes it.

## 5. Phases

Each phase follows the root `CLAUDE.md`'s recipe and its verification line. The pattern
is the one road maps 3 to 11 used: scout, contract, then waves of subagents
(see memory `roadmap-phases-via-subagents`).

- **A0 — Spike.** No product code lands. It answers:
  - Does the Bun helper, signed as Rasterize signs it, launch from a Release build AND a
    Distribution build under the hardened runtime?
  - How big is the catalog: the byte size of `catalogJSON()`, and its tokens from
    `count_tokens`? That number decides between tool search (Rasterize's 4 core tools)
    and loading all ~85 tools up front. The spike records the figure and the choice.
  - Can a stand-in Messages server (`RC_ASSISTANT_BASE_URL`) script a turn? It would
    answer with a `tool_use`, receive the tool result, then answer with text. This is
    the proof harness for everything later, and it costs nothing.
  - Does `export` replace an existing file (3f)?
  - What does an assistant edit do to a timeline drag that is in progress? MCP has the
    same exposure today; the spike measures it rather than assumes.
- **A1 — Plumbing, with no UI.**
  - `agent/`, with Rasterize's §2 change applied to both copies.
  - **Tool search, not every tool up front** (A0 C3, §7): the catalog the assistant sees
    (84 tools, 219188 bytes) is an estimated 54797–87675 tokens, over the 10000 at which
    Anthropic's guidance turns to tool search. A1 names the core set Reelcut passes as
    `core_tools` (Rasterize's four do not exist here: A0's helper deferred all 85).
  - The `project.yml` post-build step.
  - `make typecheck` gains the helper's `tsc --noEmit`.
  - `make app` fails loudly when `bun` is missing; it never skips.
  - The Makefile gets `unexport ANTHROPIC_API_KEY`.
  - `AgentLane`, `prepareCatalog()`, `callDocument` and the AI-7 table, including the
    ask-first hook. The hook is a closure the session supplies, so A1 can prove it with
    a scripted answer before A2 draws a button.
  - Two dev tools, so a proof can drive a conversation: `assistant_send` (type a message
    into a window's Assistant and wait for the turn to finish) and `assistant_answer`
    (Allow or Deny the pending confirmation). They exist only under
    `REELCUT_DEV_TOOLS`, and V-2's catalog, gate and parity rules apply to them.
  - `AssistantSession.swift`, the port of Rasterize's session, routing through the lane.
  - A proof drives a whole scripted turn against the stand-in server and reads the edit
    back through `get_project`, WITH and WITHOUT the MCP server running. It also
    scripts an `export`: Deny writes no file and the model sees the refusal; Allow
    writes it; and a Stop while the question is pending writes nothing. The proof is
    made to fail on purpose (by removing `prepareCatalog()` from the launch path) before
    it counts.
  - `export` REPLACES an existing file with no question (A0 E2, §7), so the AI-7 ask-first
    closure is handed whether the path already exists, and the confirmation names it:
    "export writes <path>" for a new file, "export REPLACES <path>" for an existing one.
- **A2 — The tab.**
  - `InspectorTab.assistant` and `AssistantPane`, with persistent views.
  - A transcript, a composer whose Send becomes Stop, Clear, and a context meter.
  - The confirmation row, with Allow and Deny. Return does not answer it; a click does.
    It says "replaces" when the file exists (A1's wording; A0 E2).
  - Reelcut ▸ Settings… gets an Assistant pane (key and model), in its own file, since
    `SettingsWindowController.swift` is at 453 lines.
  - A menu item and a key.
  - A screen catalog entry, light and dark.
  - A `space_key_probe` row.
  - The meta lines (a tool name, a one-line summary, compaction notices) come from
    Rasterize's `handleEvent`, restyled to the sharp chrome.
- **A3 — The prompt.**
  - The system prompt says what Reelcut's model IS: tracks, clips, times, nests and
    `scope`, what `render_frame` shows, and that each call is one undo step. It also
    names the open project and the playhead.
  - The compaction instructions are written for editing video: which clips and tracks,
    by id; the edits made; and frames described, since renders do not survive
    compaction.
  - This phase is judged by scripted conversations against the real API on a small
    budget, with the spend recorded as road map 6 §3b recorded its own.
- **A4 — Close.**
  - `dist_check.py` gains rows for the helper: present, signed with the hardened runtime,
    entitlements exactly `allow-jit`, and no dev marker.
  - The README gets feature bullets. Spec §7 gets a section for the assistant.
  - The map entries in `app/CLAUDE.md`.
  - The ADR, and issues for whatever is left.

## 6. The user's answers (2026-09-27)

1. **Placement: the fourth inspector tab** (AI-4). The user may move it to a floating
   window after trying it: "one step at a time". AI-4 keeps that move cheap.
2. **Model: `claude-opus-5-5` at medium effort**, choosable in Settings (AI-11).
3. **`export` and `save_project`: ask first, in the chat.** `export_captions` and
   `consolidate_media` join them for the same reason (AI-7).
4. **Undo: one step per tool call** (AI-10).

## 7. A0 record (2026-09-27)

A0 ran as §5 describes it, with instruments under `tools/proof/` only
(`assistant_spike/`, `anthropic_fake.py`; `tools/proof/README.md` has the section). No product
code landed: the helper, its build step and a hook (`AssistantSpikeHook.swift`) exist only in a
COPY of the tree under `tools/proof/work/assistant_spike/tree/`. Every figure below is from that
run's `work/assistant_spike/answers.json`: 28 pass, 3 fail (all answer rows: H2r, H2d, D2),
1 skip (L1) of 32, digest `0bdbae422e1b21fcf9b5d3ce499c1c95341eeba0c28404192c7ce6a0234db4d0`,
exit 0. The file is the first full run (27/3/1 of 31) with the B and H rows replaced by an
`--only H` rerun the same day. The rerun added row H2t, and it tested the narrowed cleanup,
which now names the app's own helpers (its direct children on the copy's helper path) before
killing the app, and never signals any other process. In both runs the cleanup found nothing
to kill: each hook logged `exited`, because its helper had already ended.

**Host.** macOS 26.5.1 (25F80), Xcode 26.2 (17C52), bun 1.3.6, `@anthropic-ai/sdk` 0.128.0
(from Rasterize's `bun.lock`), Rasterize at `acdf6d028288` with `agent/` clean
(`main.ts` sha256 `02f5123639a7…`, `protocol.ts` `630f6ea11b5e…`). `ANTHROPIC_API_KEY` was
absent.

**B — the copy builds.** Rasterize's `agent/` copied (B1); after the rename,
`bun install --frozen-lockfile` passed in 0.1 s (B2, now in §2); nine anchors each found once
(B3). The copy's `make app` built in 132 s and its Distribution `xcodebuild` in 70 s (B4, B5;
93 s and 72 s in the first run),
each running Rasterize's `Build Agent Helper` step unchanged but for the name; the drag probe
built in 93 s over 257 sources (B6).

**H — the helper launches from both builds under the hardened runtime.**
- The helper is 57719424 bytes (57.7 MB) in each bundle, flags `adhoc,runtime`, entitlements
  exactly `{com.apple.security.cs.allow-jit: true}` (H1r, H1d).
- Each app passes `codesign --verify --strict --deep` with `adhoc,runtime`, but its entitlements
  are `audio-input` AND `com.apple.security.get-task-allow` (H2r, H2d fail: a measured "no").
  The tree's OWN `build/Build/Products/{Release,Distribution}/Reelcut.app` carry the same pair
  (H2t: the runner reads them and never builds them; binaries dated 2026-09-27 11:51:14 and
  11:52:34, built from the tree before the spike). So the pair predates this road map. It is
  filed as #145.
- The tree's `dist_check.py` scores 5/5 on the copy's two builds (H3): the hook and the helper
  step do not disturb the dev-tools marker.
- Launched by each app with only `HOME`, `TMPDIR` and `PATH`, the helper answered `ready`, and
  the launch log has no `Reelcut: ` line (H4r, H4d). Launched by the runner the same way, it
  answered `ready` in 0.858 s (H5).
- The same helper re-signed `--options runtime` with NO entitlements never reaches `ready`: it
  exits with status −5 and its first stderr line is `Ran out of executable memory while
  allocating 128 bytes.` (H6). The one entitlement is necessary, as Rasterize's plist says.

**C — the catalog wants tool search.** `catalogJSON()` is 234728 bytes and 89 tools in Release,
229367 bytes and 85 tools in Distribution (C1r, C1d; the four dev tools are the difference).
Run d's first request was 232428 bytes carrying 86 tools (the 85 plus
`tool_search_tool_bm25`), all 85 catalog tools `defer_loading` because none of Rasterize's
`CORE_TOOLS` names exists here; the tools array is 231098 bytes (C2). Without `record_screen` and
the search tool, and with `defer_loading` stripped, the assistant's catalog is 84 tools and
219188 bytes: an ESTIMATE of 54797–87675 tokens with no key, entirely over 10000, so the choice
is **tool search with a core set A1 names** (C3, now in §5 A1). No `count_tokens` call was made.

**F, T — a stand-in scripts a whole turn, at no cost.** The stand-in refused
`x-api-key: a0-not-a-dummy` with 401, recorded one failure, and logged the redaction marker,
never the value (F1). In both runs its log holds exactly three requests: one
`GET /v1/models/claude-opus-5-5` and two `POST /v1/messages?beta=true`, the credential
`proof-key` only, no failures (T1r, T1d). The hook's log shows, in order, `tool_request
add_marker`, a `tool_result` with `is_error: false`, text deltas joining to `A0 stand-in: the
marker is in.`, and `turn_finished`, and the second POST carries the `tool_result` for
`toolu_a0_1` (T2r, T2d). `get_project` lists the marker at 1200000 named `A0 spike` (T3r, T3d).

**E — `export` replaces an existing file without asking.** To a fresh path it wrote a 10085-byte
MP4 with `ftyp` at byte 4 in 0.6 s (E1). Onto a file holding `A0-SENTINEL\n` it answered
`ok: true` with the same 10085 bytes, and the file is now the movie (E2). The catalog's own
sentence, "An existing file at the path is replaced", is what happens. This goes into §5 A1/A2
as the confirmation's wording.

**D — an agent edit during a timeline drag is lost.** With no gesture, `add_marker` lands and
its undo step is "Add Marker" (D1). Run between two `continueGesture` ticks of a clip-body drag,
it answers ok and is present straight after, gone after the next tick and after mouse-up; the
clip moves 0 → 1200000 (D2 fails: a measured "no"). Undo then walks "Move Clips" (clip at 0, no
marker), "Add Marker" (clip at 580000, the first tick's frame, never committed), "Add Marker"
(the no-gesture marker removed), "Add Text". MCP has the same exposure today. No road map 12
phase fixes it; it is filed as #144.

**Limits.**
- The hook lives in a copy and is not A1's session: no lane, no `callDocument`, no ask-first,
  one scripted turn. It waits for a `ProjectDocument` that HAS a file, not just any one,
  because `new_project {path}` makes the document before it saves it and the scripted call names
  the path.
- Ad-hoc signing only; no Developer ID, no notarization, no quarantine.
- The stand-in, not the real stream: one delta per block, no thinking blocks, no tool-search
  server tool, no compaction. C3's tokens are an estimate.
- D2 is driven through `TimelineView`'s gesture methods, not NSEvents.
- L1 skipped (`host: no key`): no file was searched for a key's bytes.

**Rerun.** `python3 tools/proof/assistant_spike/assistant_spike.py [--only B,H,C,F,T,E,D,L]`
(about 5 min, the copy and both builds made fresh each run;
`tools/proof/assistant_spike/README.md`).
