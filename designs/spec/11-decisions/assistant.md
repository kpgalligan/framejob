# Spec §11 — decisions: The Assistant (road map 12)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is in progress: `designs/reelcut-roadmap-12.md` (§4 made them,
amended by the user's answers in §6).

- **AI-1 — The assistant is a bundled helper, and the app never calls Anthropic itself.**
  `Contents/Helpers/reelcut-agent` is Bun-compiled from `agent/` on the Anthropic TypeScript
  SDK's Tool Runner, as Rasterize builds its own (road map 12 §1, §2). It is the one TypeScript
  in the product; G-11 ("no TypeScript") governs graphic Modules and is untouched. The Swift
  side uses `Process`, pipes and GCD, so W-8's `async` confinement holds. Risk accepted: Bun in
  every `make app`, and a nested executable of H1's size, signed separately.
- **AI-2 — The helper owns no tools; every call goes through `AgentServer.execute` by way of
  one lane.** An `AgentLane` holds one lock around every tool call from either caller, the MCP
  trampoline and the assistant session; the trampoline's call to it is the only wiring change
  in the frozen `AgentServer.swift`. The lane routes a call to main, or leaves it on its own
  queue for the `offMainTools` (§3a), and the session never takes the lock on main, because an
  off-main tool holding it waits for main (§3b). The same gate, parity check, refusals and undo
  steps apply; there are no assistant-only tools. Risk accepted: one lock serializes both
  callers, so a long off-main call (`export`, up to 3600 s) holds the other.
- **AI-3 — The catalog and the gate are prepared at launch, not at `start()`.**
  `prepareCatalog()` builds the catalog, runs `noteArguments` and runs the parity check;
  `start()` and the assistant both call it, because the gate treats a tool it has no schema for
  as taking nothing (§3c). A `make test`-reachable probe proves that an assistant call with an
  argument succeeds in a launch WITHOUT `-AgentServerEnabled`. Risk accepted: the catalog is
  built and parity-checked at every launch, whether used or not.
- **AI-4 — The Assistant is the inspector's fourth tab: Clip, Media, Document, Assistant.** This
  amends the sharp handoff's "no assistant panel" line, which was about Rasterize's parts
  rather than this feature (§3e); it gets a menu item with a key (spec §9). The user chose the
  tab to start and may move it to a floating window after trying it (§6.1), so the pane holds
  only views: the session, the transcript's storage and the pending confirmation live outside
  it, and a move is a new host for the same views. One conversation per window; the session
  lives on `EditorViewController` and survives tab switches, pane rebuilds and inspector
  collapse (§3h). Risk accepted: the transcript gets only the inspector's width, and showing it
  hides the other tabs.
- **AI-5 — The assistant edits its own window's project.** The lane pins the call's document
  the way `callScope` pins the scope: a per-call `callDocument` that `targetDocument` checks
  first, cleared by a `defer`. A `project` argument naming a DIFFERENT open project is refused
  by name, because an untitled project has no path and a window switch mid-turn would move the
  next edit (§3d). Risk accepted: one conversation cannot edit a second open project.
- **AI-6 — W-9 governs automatic styling, not a person's request.** No PIPELINE picks words by
  meaning. The assistant writes a caption's text or style only because the person asked it to
  in the conversation, and each such edit is an ordinary undo step (§3g). Risk accepted: a
  person may ask for emphasis by meaning, which no pipeline may do.
- **AI-7 — What the assistant may not call, and what it must ask about first.** Withheld: the
  dev tools, always (V-1: they are not in Distribution, and the assistant sees one catalog in
  both builds); `record_screen`, always, because recording is a person at the Record button;
  and `transcribe` with the cloud engine, refused with R6-2's sentence and pointing at File ▸
  Generate Captions…. Ask first: `export`, `export_captions`, `save_project` and
  `consolidate_media`, because each writes files where the model chose (§3f, §6.3). Such a call
  is NOT run when the helper asks; the transcript shows a confirmation row naming the tool and
  where it writes, with Allow and Deny, and the helper's `tool_request` simply waits, so the
  helper is unchanged. Deny answers the call as an error, "The person declined: …". Stop,
  Clear, closing the window and a dead helper all answer a pending confirmation as declined.
  An MCP caller is never asked: the rule belongs to the assistant's lane, not to the tool. Both
  lists are one table in one file, with a "withheld" or "ask first" column and a reason on
  every row; the helper never sees a withheld tool, and the lane refuses one if it is called
  anyway. Risk accepted: recording and cloud transcription stay menu-only, and every file
  written costs a click.
- **AI-8 — The key is the person's own, and is R6-5 and R6-12's key in everything but the
  vendor.** It lives in `SecretStore` under `anthropic-key`; the one override is
  `ANTHROPIC_API_KEY`, read only as R6-5 amended says. It is never a tool argument, a launch
  argument or an answer, and is handed to the helper on stdin only (§1, §3i). R6-9's
  `-RCSecretFolder` keeps proofs away from the person's file. R6-5's "integrated AI offering"
  is THIS, and it does not unblock C2 (#125), which still needs the caller's identity. Risk
  accepted: a `0600` file rather than the Keychain, for R6-5's measured reason.
- **AI-9 — History is append-only, and end-of-turn compaction is the one rewrite.** Rasterize's
  rule, for the same reasons: Opus 5.5 rejects replayed thinking after an edited prefix, and an
  unchanged prefix keeps the cache warm; compaction runs only at the end of a turn, past a
  threshold (§1). Risk accepted: old renders stay in context until compaction.
- **AI-10 — Each tool call the assistant makes is its own undo step,** exactly as an MCP call
  is. A turn is not grouped, and the Edit menu names the step as it would for the same call
  from MCP (§6.4). Risk accepted: a ten-call turn is ten Undos.
- **AI-11 — The default model is `claude-opus-5-5` at medium effort.** The model is a person's
  setting, chosen in Settings' Assistant pane; like the key, no tool reads or writes it
  (§6.2). Risk accepted: the costliest default, paid with the person's key.
