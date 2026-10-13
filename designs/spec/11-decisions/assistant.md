# Spec §11 — decisions: The Assistant (road map 12)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed; its condensed record is `designs/adr/roadmap-12-assistant.md`
(the original is `archive/roadmap-12.md`, whose §4 made them, amended by the user's answers
in §6).

- **AI-1 — The assistant is a bundled helper, and the app never calls Anthropic itself.**
  `Contents/Helpers/framejob-agent` is Bun-compiled from `agent/` on the Anthropic TypeScript
  SDK's Tool Runner, as Rasterize builds its own (road map 12 §1, §2). It is the one TypeScript
  in the product; G-11 ("no TypeScript") governs graphic Modules and is untouched. The Swift
  side uses `Process`, pipes and GCD, so W-8's `async` confinement holds. Risk accepted: Bun in
  every `make app`, and a nested executable of H1's size, signed separately.
  **Amended by NM-5** (rename R0): `Contents/Helpers/reelcut-agent` is now
  `Contents/Helpers/framejob-agent`.
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
  **Amended 2026-10-01, by #40**: `close_project` is withheld, always: closing a project
  closes the window the conversation lives in (AI-5).
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
  **Amended 2026-10-01, by AI-20 (#151)**: compaction can be turned off or its threshold
  changed in Settings, and with "Clear old tool results" on, the API's clearing is a second
  rewrite — of what the model sees in a request past 150 000 tokens, possibly mid-turn, not of
  the helper's history. Each clearing breaks the prompt cache once.
- **AI-10 — Each tool call the assistant makes is its own undo step,** exactly as an MCP call
  is. A turn is not grouped, and the Edit menu names the step as it would for the same call
  from MCP (§6.4). Risk accepted: a ten-call turn is ten Undos.
- **AI-11 — The default model is `claude-opus-5-5` at medium effort.** The model is a person's
  setting, chosen in Settings' Assistant pane; like the key, no tool reads or writes it
  (§6.2). Risk accepted: the costliest default, paid with the person's key.
- **AI-12 — A tool call that arrives during a live gesture waits for mouse-up, then runs.** It
  applies to every caller, MCP and the assistant alike, because the lane (AI-2) is shared.
  "Live" means any open `ProjectDocument.isLiveEditing`: a timeline, canvas or inspector-slider
  gesture. A waiting call is never refused and never lost; before this, a call run between two
  ticks of a drag answered ok and was then undone by the next tick (#144; road map 12 §7 D2).
  The call lands above the gesture's own undo step. It is reversible: the wait is
  `AgentLane.onMainWhenIdle` alone. Risk accepted: a call, and the lane's lock with it, waits
  as long as the mouse is held down.
- **AI-13 — The assistant's one base-URL override is `RC_ASSISTANT_BASE_URL`, and with it set
  no key file is opened.** The helper's `api_base` comes from this environment variable alone
  (the shared `protocol.ts` calls it "an environment variable of its own"; A0's F and T rows
  used it). Plain `http` is accepted only for a loopback host, as R6-9 allows for AssemblyAI;
  any other value refuses the session by name. This is AI-8's R6-9 made explicit:
  `-RCSecretFolder`, from the argument domain, names the folder of `anthropic-key`; with the
  override set and no `-RCSecretFolder`, NO `FileStore` is built and the store is an empty
  `MemoryStore`, so the person's file is never read; the store is read first and
  `ANTHROPIC_API_KEY` second (R6-9 (d)). A variable rather than the argument domain because a
  variable cannot be persisted in the app's defaults, which is R6-9 (c)'s reason. Risk
  accepted: a person who exports it sends their environment's key, and only that, to the
  server it names.
- **AI-14 — A selection change that is not a click on a clip leaves the Assistant tab
  showing; a click on a clip still shows Clip.** The inspector's switch to Clip on a changed
  selection (`InspectorViewController.refresh(isLive:)`) runs only from the Media and Document
  tabs. The assistant's own calls change the selection mid-turn, and a tab that jumped to Clip
  under the person would hide the reply and the ask-first row they are waiting on.
  `clipPicked()` — a click on a clip in the timeline or canvas — still shows Clip from any
  tab. Risk accepted: a selection made by an MCP caller or a menu item while the Assistant tab
  shows does not bring the clip's properties forward; a click does.
- **AI-15 — The window's live context rides on each person message; the system prompt is fixed
  for a session.** `AssistantSession.send` writes the person's text behind a
  `<framejob_context>` block (`AssistantLiveContext.swift`): the project's name and path, the
  open nest, the playhead and the selection, as they are at send time. The system prompt, the
  tool-search guide and the compaction instructions are written once, in `configure`, and never
  change for the session. `configure` is the helper's only system channel and `agent/` is one
  diff with Rasterize (#147); a system prompt that changed per turn would break AI-9's
  unchanged prefix and the prompt cache; and the playhead and selection change between turns.
  Risk accepted: about sixty tokens on every message, and the block is the state at send time,
  so after its own edits the model re-reads with `get_project`.
  **Amended by NM-5** (rename R0): `<reelcut_context>` is now `<framejob_context>`.
- **AI-16 — Stop stops a running `export` or on-device `transcribe`; any other running call
  finishes.** Each call the session submits carries a per-call token through
  `AgentLane.submit`, and Stop cancels the running call's token. The lane answers a call whose
  token is already cancelled when it takes the lock "Cancelled by the user." without running it.
  A running `export` links its token to `Exporter.cancel()`, which only sets flags (G-17's
  cross-thread hazard does not arise; the writer removes its part-file), and an on-device
  `transcribe` links it to its `Transcriber.CancelToken`, the transcribe sheet's own path; the
  model gets the tool's own sentence ("The export was cancelled.", "The transcription was
  cancelled."). Before this, Stop only stopped the helper's turn, and an export in flight wrote
  its file to the end (#149). Risk accepted: `render_frame`, `render_graphic`, `import_media`
  (an opt-in ffmpeg conversion included), `save_project`/`new_project` and the main-thread tools
  run to their end; Clear, closing the window and a dead helper still let a running call finish,
  its result dropped, as before; cloud `transcribe` is withheld (AI-7) and not linked.
- **AI-17 — The transcript is one selectable text, and the composer is multi-line with K-2's
  Return** (issue batch B18, #153, #154). The transcript is one non-editable text view: the
  entries in order, one "\n" between them, so a selection and a plain-text copy cross entries;
  a reply that is still extending edits only its own range. The layout dump reads the entries
  as parts the transcript names (id `assistant.entry.<kind>`, text, rect), since one text view
  has no subview per entry. The composer grows from one line to five, then scrolls. A bare
  Return or keypad Enter (⇪ allowed) sends while idle and beeps otherwise; it never answers a
  question. Return with ⇧, ⌘, ⌥ or ⌃ inserts "\n", K-2's rule through the same
  `TextEditKey.route`; nothing is routed while an input method has marked text. Tab and ⇧Tab
  move focus, as the single-line field's did; they never type a tab into the message. The
  composer's typing undo is its OWN `UndoManager`: ⌘Z in the composer undoes typing, and typing
  never lands on the document's stack, never dirties the document and never enters
  `registerUndo`'s grouping (AI-10, app/CLAUDE.md's Undo); a programmatic set of its text (a
  send, the dev tools' pane path) drops that undo history. "No undo" was not chosen: a text
  view that does not register undo still answers ⌘Z through the window's manager, which is the
  document's, so ⌘Z while typing would undo a project edit. Risk accepted: accessibility sees
  one text area, not one element per entry; and the scroll to the newest line still runs on
  every change, so it can move a drag-selection during a streaming reply.
- **AI-18 — A proof lowers the end-of-turn compaction threshold with the dev-only launch default
  `-RCDevAssistantAutoCompact <tokens>`; the shipped threshold stays 300 000** (issue batch B26,
  #161). `AssistantConfiguration.settingsJSON()` sends `autoCompactTokens` (300 000, AI-9) as
  `configure.settings.auto_compact_tokens`; a build with `FRAMEJOB_DEV_TOOLS` (V-1) sends the
  knob's value instead when it is present, read from the ARGUMENT domain alone
  (`AssemblyAIConfiguration.argument`). A value that is not a whole number of 1 or more is named
  on stderr and ignored. It replaces nothing else, and a Distribution build does not compile it.
  Why: a 300 000-token context means a body far past row H's 256 000-byte bound
  (`assistant_prompt_eval.py`) and dollars of cache writes for every run, while on-demand
  compaction has no trigger or minimum of its own (the SDK's `BetaCompactionConfig`), so at 1
  every turn ends compacted and one short conversation proves the whole path against the real
  API (`assistant_compaction_proof.py`). Risk accepted: the proof shows summaries of tens of
  thousands of tokens, not of 300 000; and #151's person setting, when it lands, will not remove
  the knob.
  **Amended 2026-10-01, by AI-20 (#151)**: the knob replaces the person's threshold (300 000
  unless changed in Settings), and wins even with compaction turned off.
  **Amended by NM-6** (rename R0): `REELCUT_DEV_TOOLS` is now `FRAMEJOB_DEV_TOOLS`.
- **AI-19 — While the window's assistant waits on an ask-first question, the Assistant tab's
  title wears a dot, whichever tab is showing** (issue batch B47, #152; the owner's choice,
  2026-09-30: "badge the Assistant tab's title"). The dot is its own view over the strip
  (`InspectorTabBadge`), just right of the title, in the accent colour; `PanelTabsView` is not
  forked (Controls.swift's sync rule). It shows exactly while the window's session has a
  `pendingQuestion`, set by `assistantRefresh()`, which runs after every question and answer, so
  it goes off at Allow, Deny, Stop, Clear, a key or model change, the helper's exit and the
  window's close. It shows on the Assistant tab too, so it depends on the session alone. It is
  passive: it takes no click (a click on the tab only shows the tab) and no key, so Return still
  never answers (AI-17, K-2); the tab never switches itself and no note appears. Risk accepted:
  a collapsed inspector shows no dot (no strip is on screen), and another window shows nothing —
  a question in one window draws no attention in the others.
- **AI-20 — The chat settings are the person's, in Settings' Assistant pane, and a change
  reaches an open conversation without ending it** (issue batch B48, #151; the owner,
  2026-09-30: "Yes, make these settings available to the user"). They are Rasterize's two:
  "Compact when context reaches N tokens", on, N a whole number from 20 000 to 900 000, 300 000
  by default (AI-9); and "Clear old tool results past 150,000 tokens", off, acting past the
  helper's fixed `CLEAR_TRIGGER_TOKENS` (150 000, `agent/src/main.ts`). They live in
  `UserDefaults` under `FrameJobAssistantAutoCompact`, `FrameJobAssistantAutoCompactTokens` and
  `FrameJobAssistantClearToolResults` (`AssistantChatSettings`); like the model, no tool reads or
  writes them (AI-11's reason). A stored value outside the range reads as 300 000; a typed one
  beeps and the field shows the stored value again. `configure.settings` carries
  `auto_compact_tokens` (null when compaction is off) and `clear_tool_results`. A change applies
  at once, with no Save, and is written to every open session as `{type: "settings"}`: it ends
  nothing, unlike a key or model change. The helper reads the threshold at each turn's end and
  fixes clearing when a turn starts, so a change made mid-turn applies the threshold at that
  turn's end and clearing from the next turn. Risk accepted: with compaction off, requests fail
  at the model's window until Clear; with clearing on, the model may re-fetch a result it lost;
  and no proof has sent `context_management` to the real API — every live and stand-in run so
  far configured clearing off (`assistant_helper_proof.py`, `spend_proof.py`, the spike) and the
  unchanged helper builds the request, so a capped live clearing proof is owed, and the owner
  decides its spend.
  **Amended by NM-6** (rename R0): `ReelcutAssistantAutoCompact` is now
  `FrameJobAssistantAutoCompact`; `ReelcutAssistantAutoCompactTokens` is now
  `FrameJobAssistantAutoCompactTokens`; `ReelcutAssistantClearToolResults` is now
  `FrameJobAssistantClearToolResults`.
